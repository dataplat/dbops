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
    Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
. "$PSScriptRoot\..\constants.ps1"

$buildFolder = New-Item -Path "$PSScriptRoot\..\build" -ItemType Directory -Force
$workFolder = Join-PSFPath -Normalize $buildFolder "dbops-test"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'
$newDbName = "dbops_test"
$outputFile = "$workFolder\log.txt"
$testPassword = 'TestPassword'
$fullConfig = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\full_config.json"
$noNewScriptsText = 'No new scripts need to be executed - completing.'

# for replacement
$packageNamev1 = Join-Path $workFolder "TempDeployment_v1.zip"

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
        $timeoutError = '*Timeout Expired.*'
        $defaultSchema = 'dbo'
        $connectionString = "Server=$instance;Database=$newDbName;"
        if ($credential) {
            $connectionString += "User ID=$($credential.UserName);Password=$($credential.GetNetworkCredential().Password)"
        }
        else {
            $connectionString += "Trusted_Connection=True"
        }
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
        $timeoutError = if ($PSVersionTable.PSVersion.Major -ge 6) { '*Fatal error encountered during command execution*' } else { '*Timeout expired*' }
        $defaultSchema = $newDbName
        $connectionString = "server=$($instance.Split(':')[0]);port=$($instance.Split(':')[1]);database=$newDbName;user id=$($credential.UserName);password=$($credential.GetNetworkCredential().Password)"

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
        $timeoutError = if ($PSVersionTable.PSVersion.Major -ge 6) { '*Exception while reading from stream*' } else { "*Unable to read data from the transport connection*" }
        $defaultSchema = 'public'
        $connectionString = "Host=$instance;Database=$newDbName;Username=$($credential.UserName);Password=$($credential.GetNetworkCredential().Password)"
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
        $timeoutError = "*user requested cancel of current operation*"
        $defaultSchema = $dbUserName
        $configCS = New-DBOConfig -Configuration @{
            SqlInstance = $instance
            Credential  = $credential
        }
        $connectionString = Get-ConnectionString -Configuration $configCS -Type $Type
        Write-Host $connectionString
    }
    default {
        throw "Unknown server type $Type"
    }
}

$cleanupScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\Cleanup.sql"
$delayScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\delay.sql"
$tranFailScripts = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\transactional-failure"
$verificationScript = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\verification\select.sql"
$logFile1 = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\verification\log1.txt"
$logFile2 = Join-PSFPath -Normalize "$PSScriptRoot\..\etc\$etcFolder\verification\log2.txt"

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
        [string]$JournalName = $logTable,
        [switch]$HasJournal,
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
    if ($HasJournal) {
        $InputObject.Configuration.SchemaVersionTable | Should -Be $JournalName
    }
    else {
        $InputObject.Configuration.SchemaVersionTable | Should -BeNullOrEmpty
    }
}


function Test-DeploymentState {
    param (
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$HasJournal,
        [string]$JournalName = $logTable,
        [string]$Schema = $defaultSchema
    )
    $versionMap = @{
        0 = @()
        1 = @('a', 'b')
        2 = @('c', 'd')
    }
    function Get-ColumnName {
        param (
            [Parameter(Mandatory, ValueFromPipeline)]
            [string]$InputObject
        )
        $InputObject | Foreach-Object { if ($Type -eq 'Oracle') { $_.ToUpper() } else { $_ } }
    }

    #Verifying objects
    $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
    if ($HasJournal) {
        $JournalName | Should -BeIn $testResults.(Get-ColumnName name)
    }
    else {
        $JournalName | Should -Not -BeIn $testResults.(Get-ColumnName name)
    }
    foreach ($ver in 0..($versionMap.Keys.Count - 1)) {
        if ($Version -ge $ver) {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -BeIn $testResults.(Get-ColumnName name)
            }
        }
        else {
            foreach ($table in $versionMap[$ver]) {
                $table | Should -Not -BeIn $testResults.(Get-ColumnName name)
            }
        }
    }
    if ($testResults) {
        $testResults.(Get-ColumnName schema) | ForEach-Object { $_ | Should -Be $Schema }
    }
}

function Get-DeploymentTableCount {
    return @(Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript).Count
}
function Reset-TestDatabase {
    $null = Invoke-DBOQuery @dbConnectionParams -InputFile $cleanupScript
    if ($Type -eq 'Postgresql') {
        [Npgsql.NpgsqlConnection]::ClearAllPools()
    }
}
function Remove-Workfolder {
    param(
        [switch]$Unpacked
    )
    if ($Unpacked) {
        $folder = $unpackedFolder
    }
    else {
        $folder = $workFolder
    }
    if ((Test-Path $folder) -and $workFolder -like '*dbops-test*') { Remove-Item $folder -Recurse }
}
function New-Workfolder {
    param(
        [switch]$Force,
        [switch]$Unpacked
    )
    if ($Force) {
        Remove-Workfolder -Unpacked:$Unpacked
    }
    if ($Unpacked) {
        New-Workfolder
        $folder = $unpackedFolder
    }
    else {
        $folder = $workFolder
    }
    $null = New-Item $folder -ItemType Directory -Force
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

function Get-TableExistsMessage {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputObject
    )
    switch ($Type) {
        SqlServer { "There is already an object named '$InputObject' in the database." }
        MySQL { "Table '$InputObject' already exists" }
        PostgreSQL { "*relation `"$InputObject`" already exists*" }
        Oracle { 'name is already used by an existing object' }
    }
}
