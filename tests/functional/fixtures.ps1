[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", '')]
param (
    [string]$CommandName = "DBOps",
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [string]$Type = "SqlServer",
    [switch]$Internal,
    [switch]$Batch
)
if (!$Batch) {
    # Explicitly import the module for testing
    Import-Module "$PSScriptRoot\..\..\dbops.psd1" -Force
    if ($Internal) {
        Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
    }
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
$idColumn = "Id"

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
        $varQuery = "SELECT '#{var1}'; PRINT ('#{var2}')"
        $schemaVersionv1 = @"
create table $logTable (
    [Id] int identity(1,1) not null constraint $($logTable)_pk primary key,
    [ScriptName] nvarchar(255) not null,
    [Applied] datetime not null
)
"@
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
        $varQuery = "SELECT '#{var1}'; SELECT '#{var2}'"
        $schemaVersionv1 = @'
        CREATE TABLE {0}
        (
            `schemaversionid` INT NOT NULL AUTO_INCREMENT,
            `scriptname` VARCHAR(255) NOT NULL,
            `applied` TIMESTAMP NOT NULL,
            PRIMARY KEY (`schemaversionid`)
        )
'@ -f $logtable
        $idColumn = "schemaversionid"
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
        $varQuery = "SELECT '#{var1}'; SELECT '#{var2}'"
        $schemaVersionv1 = @"
CREATE TABLE $logtable
(
    schemaversionsid serial NOT NULL,
    scriptname character varying(255) NOT NULL,
    applied timestamp without time zone NOT NULL,
    CONSTRAINT $($logtable)_pk PRIMARY KEY (schemaversionsid)
)
"@
        $idColumn = "schemaversionsid"
    }
    Oracle {
        $instance = $script:oracleInstance
        $logTable = "DEPLOYHISTORY"
        $dbUserName = 'DBOPSDEPLOYPS1'
        $dbPassword = 'S3cur_pAss'
        $dbCredentials = [pscredential]::new($dbUserName, (ConvertTo-SecureString $dbPassword -AsPlainText -Force))
        $credential = $dbCredentials
        $saConnectionParams = @{
            SqlInstance         = $instance
            Silent              = $true
            Credential          = $script:oracleCredential
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
        $createDatabaseScript = "CREATE USER $dbUserName IDENTIFIED BY $dbPassword account unlock/
            GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $dbUserName/
            GRANT EXECUTE on dbms_lock to $dbUserName"
        $dropDatabaseScript = "
            BEGIN
                FOR ln_cur IN (SELECT sid, serial# FROM v`$session WHERE username = '$dbUserName')
                LOOP
                    EXECUTE IMMEDIATE ('ALTER SYSTEM KILL SESSION ''' || ln_cur.sid || ',' || ln_cur.serial# || ''' IMMEDIATE');
                END LOOP;
                FOR x IN ( SELECT count(*) cnt
                    FROM DUAL
                    WHERE EXISTS (SELECT * FROM DBA_USERS WHERE USERNAME = '$dbUserName')
                )
                LOOP
                    IF ( x.cnt = 1 ) THEN
                        EXECUTE IMMEDIATE 'DROP USER $dbUserName CASCADE';
                    END IF;
                END LOOP;
            END;
            /"
        $timeoutError = "*user requested cancel of current operation*"
        $defaultSchema = $dbUserName
        $connectionString = "DATA SOURCE=localhost;USER ID=$dbUserName;PASSWORD=$dbPassword"
        $varQuery = @"
SELECT '#{var1}' FROM dual
/
SELECT '#{var2}' FROM dual
"@
        $schemaVersionv1 = @"
CREATE TABLE $logTable (
    schemaversionid NUMBER(10),
    scriptname VARCHAR2(255) NOT NULL,
    applied TIMESTAMP NOT NULL,
    CONSTRAINT PK_$logTable PRIMARY KEY (schemaversionid)
)
/
CREATE SEQUENCE $($logTable)_sequence
/
CREATE OR REPLACE TRIGGER $($logTable)_on_insert
BEFORE INSERT ON $logTable
FOR EACH ROW
BEGIN
    SELECT $($logTable)_sequence.nextval
    INTO :new.schemaversionid
    FROM dual;
END;
"@
        $idColumn = "schemaversionid"
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
    return $Version | Foreach-Object { Join-PSFPath -Normalize (Resolve-Path "$PSScriptRoot\..\etc\$etcFolder\success\$_.sql").Path }
}
function Get-JournalScript {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version,
        [switch]$Script,
        [switch]$Absolute
    )
    foreach ($ver in $Version) {
        Get-PackageScript -Version $ver | Get-Item | ForEach-Object {
            if ($Script) {
                if ($Absolute) { (Resolve-Path $_).Path }
                else { $_.Name }
            }
            else { "$ver.0\" + $_.Name }
        }
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
        [switch]$Script,
        [switch]$WhatIf
    )
    $InputObject.Successful | Should -Be $true
    $InputObject.SqlInstance | Should -Be $instance
    $InputObject.Scripts.Name | Should -Be (Get-JournalScript -Version $Version -Script:$Script)
    if ($Type -ne 'Oracle') {
        $InputObject.Database | Should -Be $newDbName
    }
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

function Get-ColumnName {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputObject
    )
    $InputObject | Foreach-Object { if ($Type -eq 'Oracle') { $_.ToUpper() } else { $_ } }
}
function Test-DeploymentState {
    param (
        [Parameter(Mandatory)]
        [int]$Version,
        [switch]$HasJournal,
        [switch]$Legacy,
        [switch]$Script,
        [string]$JournalName = $logTable,
        [string]$Schema = $defaultSchema
    )
    $versionMap = @{
        0 = @()
        1 = @('a', 'b')
        2 = @('c', 'd')
    }


    #Verifying objects
    $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
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
    if ($HasJournal) {
        $JournalName | Should -BeIn $testResults.(Get-ColumnName name)
        #Validating schema version table
        $fqn = Get-QuotedIdentifier ($Schema + '.' + $JournalName)
        $fields = @(
            $idColumn
            "ScriptName"
            "Applied"
        )
        if (-not $Legacy) {
            $fields += @(
                "Checksum"
                "ExecutionTime"
                "AppliedBy"
            )
        }
        $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT $($fields -join ', ') FROM $fqn"
        foreach ($row in $svResults) {
            $row.(Get-ColumnName $idColumn) | Should -Not -BeNullOrEmpty
            $row.(Get-ColumnName ScriptName) | Should -BeIn (Get-JournalScript -Version (1..$Version) -Script:$Script)
            $row.(Get-ColumnName Applied) | Should -Not -BeNullOrEmpty
            if (-not $Legacy) {
                $row.(Get-ColumnName Checksum) | Should -Not -BeNullOrEmpty
                $row.(Get-ColumnName ExecutionTime) | Should -BeGreaterOrEqual 0
                if ($credential) {
                    $row.(Get-ColumnName AppliedBy) | Should -Be $credential.UserName
                }
                else {
                    $row.(Get-ColumnName AppliedBy) | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
    else {
        $JournalName | Should -Not -BeIn $testResults.(Get-ColumnName name)
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
        Oracle { '*name is already used by an existing object*' }
    }
}
function Get-QuotedIdentifier {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputObject
    )
    $ids = foreach ($part in $InputObject.Split('.')) {
        switch ($Type) {
            SqlServer { "[$part]" }
            MySQL { '`{0}`' -f $part }
            PostgreSQL { "`"$part`"" }
            Oracle { $part.ToUpper() }
        }
    }
    $ids -Join '.'
}

function Get-ScriptFile {
    param(
        [Parameter(Mandatory)]
        [int[]]$Version
    )
    Get-PackageScript -Version $Version | Get-Item | ForEach-Object {
        [DBOpsFile]::new($_, $_.Name, $true)
    }
}
