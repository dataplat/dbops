Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }
$testRoot = (Get-Item $here\.. ).FullName

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$testRoot\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running Oracle $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$oraUserName = 'DBOPSDEPLOYPS1'
$oraPassword = 'S3cur_pAss'
$testCredentials = [pscredential]::new($oraUserName, (ConvertTo-SecureString $oraPassword -AsPlainText -Force))
$connParams = @{
    Type        = 'Oracle'
    SqlInstance = $script:oracleInstance
    Silent      = $true
    Credential  = $testCredentials
}
$adminParams = @{
    Type                = 'Oracle'
    SqlInstance         = $script:oracleInstance
    Silent              = $true
    Credential          = $script:oracleCredential
    ConnectionAttribute = @{
        'DBA Privilege' = 'SYSDBA'
    }
}
$createUserScript = "CREATE USER $oraUserName IDENTIFIED BY $oraPassword/
GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $oraUserName/
GRANT EXECUTE on dbms_lock to $oraUserName"
$dropUserScript = "
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
$dropObjectsScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\drop.sql"

$logTable = "TESTDEPLOY"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\Cleanup.sql"

Describe "Update-DBOSchemaTable Oracle integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
        $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        $schemaTableQuery = @'
        CREATE TABLE {0}
        (
            schemaversionid NUMBER(10),
            scriptname VARCHAR2(255) NOT NULL,
            applied TIMESTAMP NOT NULL,
            CONSTRAINT PK_{0} PRIMARY KEY (schemaversionid)
        )
'@
        $verificationQuery = "select c.COLUMN_NAME from USER_TAB_COLUMNS c where c.TABLE_NAME = '{0}'"
    }
    AfterAll {
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
    }
    BeforeEach {
        $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
    }
    Context "testing upgrade of the schema table" {
        It "upgrade default schema table" {
            $null = Invoke-DBOQuery @connParams -Query ($schemaTableQuery -f 'SCHEMAVERSIONS')

            $result = Update-DBOSchemaTable @connParams -Database $newDbName
            $result | Should -BeNullOrEmpty

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery @connParams -Query ($verificationQuery -f 'SCHEMAVERSIONS')
            $testResults.COLUMN_NAME | Should -Be @('SCHEMAVERSIONID', 'SCRIPTNAME', 'APPLIED', 'CHECKSUM', 'APPLIEDBY', 'EXECUTIONTIME')
        }
        It "upgrade custom schema table" {
            $null = Invoke-DBOQuery @connParams -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -SchemaVersionTable $logTable
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Query ($verificationQuery -f $logTable)
            $testResults.COLUMN_NAME | Should -Be @('SCHEMAVERSIONID', 'SCRIPTNAME', 'APPLIED', 'CHECKSUM', 'APPLIEDBY', 'EXECUTIONTIME')
        }
    }
    Context  "$commandName whatif tests" {
        It "should upgrade nothing" {
            $null = Invoke-DBOQuery @connParams -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -SchemaVersionTable $logTable -WhatIf
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Query ($verificationQuery -f $logTable)
            $testResults.COLUMN_NAME | Should -Be @('SCHEMAVERSIONID', 'SCRIPTNAME', 'APPLIED')
        }
    }
}
