[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", '')]
param (
    [string]$CommandName = "DBOps",
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string]$Type = "SqlServer",
    [switch]$Batch
)
if (!$Batch) {
    # Explicitly import the module for testing
    Import-Module "$PSScriptRoot\..\..\dbops.psd1" -Force
    # Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
. "$PSScriptRoot\..\constants.ps1"

$buildFolder = New-Item -Path "$PSScriptRoot\..\build" -ItemType Directory -Force
$workFolder = Join-PSFPath -Normalize $buildFolder "dbops-test"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
$newDbName = "dbops_test"
$outputFile = "$workFolder\log.txt"



switch ($Type) {
    SqlServer {
        $instance = $script:mssqlInstance
        $credential = $script:mssqlCredential
        $saConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = "master"
            Type        = $Type
        }
        $dbConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = $newDbName
            Type        = $Type
        }
        $etcFolder = "sqlserver-tests"
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $createDatabaseScript = 'IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN CREATE DATABASE [{0}]; END' -f $newDbName

    }
    MySQL {
        $instance = $script:mysqlInstance
        $credential = $script:mysqlCredential
        $saConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = "mysql"
            Type        = $Type
        }
        $dbConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = $newDbName
            Type        = $Type
        }
        $etcFolder = "mysql-tests"
        $dropDatabaseScript = 'DROP DATABASE IF EXISTS `{0}`' -f $newDbName
        $createDatabaseScript = 'CREATE DATABASE IF NOT EXISTS `{0}`' -f $newDbName
    }
    PostgreSQL {
        $instance = $script:postgresqlInstance
        $credential = $script:postgresqlCredential
        $saConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = "postgres"
            Type        = $Type
        }
        $dbConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $credential
            Database    = $newDbName
            Type        = $Type
        }
        $etcFolder = "postgresql-tests"
        $dropDatabaseScript = @(
            'SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ''{0}'' AND pid <> pg_backend_pid()' -f $newDbName
            'DROP DATABASE IF EXISTS {0}' -f $newDbName
        )
        $createDatabaseScript = 'CREATE DATABASE {0}' -f $newDbName
    }
    Oracle {
        $instance = $script:oracleInstance
        $credential = $script:oracleCredential
        $logTable = "DEPLOYHISTORY"
        $dbUserName = 'DBOPSDEPLOYPS1'
        $dbPassword = 'S3cur_pAss'
        $dbCredentials = [pscredential]::new($dbUserName, (ConvertTo-SecureString $dbPassword -AsPlainText -Force))
        $saConnectionParams = @{
            SqlInstance         = $instance
            Silent              = $true
            Credential          = $credential
            Type                = $Type
            ConnectionAttribute = @{
                'DBA Privilege' = 'SYSDBA'
            }
        }
        $dbConnectionParams = @{
            SqlInstance = $instance
            Silent      = $true
            Credential  = $dbCredentials
            Type        = $Type
        }
        $etcFolder = "oracle-tests"
        $createDatabaseScript = "CREATE USER $oraUserName IDENTIFIED BY $oraPassword/
            GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $oraUserName/
            GRANT EXECUTE on dbms_lock to $oraUserName"
        $dropDatabaseScript = "
            BEGIN
                FOR ln_cur IN (SELECT sid, serial# FROM v`$session WHERE username = '$oraUserName')
                LOOP
                    EXECUTE IMMEDIATE ('ALTER SYSTEM KILL SESSION ''' || ln_cur.sid || ',' || ln_cur.serial# || ''' IMMEDIATE');
                END LOOP;
                FOR x IN ( SELECT count(*) cnt
                    FROM DUAL
                    WHERE EXISTS (SELECT * FROM DBA_USERS WHERE USERNAME = '$oraUserName')
                )
                LOOP
                    IF ( x.cnt = 1 ) THEN
                        EXECUTE IMMEDIATE 'DROP USER $oraUserName CASCADE';
                    END IF;
                END LOOP;
            END;
            /"
    }
    default {
        throw "Unknown server type $Type"
    }
}

$cleanupScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\Cleanup.sql"
$v1scripts = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\verification\select.sql"

# input data functions

function Get-PackageScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version
    )
    return $Version | Foreach-Object { Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\success\$_.sql" }
}
function Get-JournalScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version
    )
    foreach ($ver in $Version) {
        Get-Item (Get-PackageScript -Version $Version) | ForEach-Object { "$ver.0\" + $_.Name }
    }
}

# validation functions

function Test-DeploymentOutput {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$WhatIf
    )
    $InputObject.Successful | Should -Be $true
    $InputObject.SqlInstance | Should -Be $instance
    $InputObject.Scripts.Name | Should -Be (Get-JournalScript -Version $Version)
    $InputObject.Database | Should -Be $newDbName
    $InputObject.ConnectionType | Should -Be $Type
    $InputObject.Error | Should -BeNullOrEmpty
    $InputObject.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
    $InputObject.StartTime | Should -Not -BeNullOrEmpty
    $InputObject.EndTime | Should -Not -BeNullOrEmpty
    $InputObject.EndTime | Should -BeGreaterOrEqual $InputObject.StartTime
    if ($WhatIf) {
        "No deployment performed - WhatIf mode." | Should -BeIn $testResults.DeploymentLog
    }
    else {
        'Upgrade successful' | Should -BeIn $InputObject.DeploymentLog
    }
}


function Test-DeploymentState {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$HasJournal
    )
    $versionMap = @{
        0 = @()
        1 = @('a', 'b')
        2 = @('c', 'd')
    }
    $tableColumn = switch ($Type) {
        Oracle { "NAME" }
        Default { "name" }
    }

    #Verifying objects
    $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
    if ($HasJournal) {
        $logTable | Should -BeIn $testResults.$tableColumn
    }
    else {
        $logTable | Should -Not -BeIn $testResults.$tableColumn
    }
    foreach ($ver in 0..($versionMap.Keys.Count - 1)) {
        if ($Version -ge $ver) {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -BeIn $testResults.$tableColumn
            }
        }
        else {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -Not -BeIn $testResults.$tableColumn
            }
        }
    }
}

function Reset-TestDatabase {
    $null = Invoke-DBOQuery @dbConnectionParams -InputFile $cleanupScript
}
function Remove-Workfolder {
    if ((Test-Path $workFolder) -and $workFolder -like '*dbops-test') { Remove-Item $workFolder -Recurse }
}

function Remove-TestDatabase {
    $null = Invoke-DBOQuery @saConnectionParams -Query $dropDatabaseScript
    if ($Type -eq 'Postgresql') {
        [Npgsql.NpgsqlConnection]::ClearAllPools()
    }
}
function New-TestDatabase {
    param(
        [switch]$Force
    )
    if ($Force) {
        Remove-TestDatabase
    }
    $null = Invoke-DBOQuery @saConnectionParams -Query $createDatabaseScript
}

function Test-IsSkipped {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    if ($env:DBOPS_TEST_DB_TYPE) {
        $types = $env:DBOPS_TEST_DB_TYPE.split(" ")
        if ($InputObject -notin $types) {
            Set-ItResult -Skipped -Because "disabled in settings"
        }
    }
}