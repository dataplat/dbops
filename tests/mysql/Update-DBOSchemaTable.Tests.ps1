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
    Write-Host "Running MySQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\Cleanup.sql"

$newDbName = "test_dbops_$commandName"
$connParams = @{
    SqlInstance = $script:mysqlInstance
    Credential = $script:mysqlCredential
    Silent = $true
    Type = "MySQL"
}

Describe "Update-DBOSchemaTable MySQL integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $dropDatabaseScript = 'DROP DATABASE IF EXISTS `{0}`' -f $newDbName
        $createDatabaseScript = 'CREATE DATABASE IF NOT EXISTS `{0}`' -f $newDbName
        $null = Invoke-DBOQuery @connParams -Database mysql -Query $dropDatabaseScript
        $null = Invoke-DBOQuery @connParams -Database mysql -Query $createDatabaseScript
        $schemaTableQuery = @'
        CREATE TABLE {0}
        (
            `schemaversionid` INT NOT NULL AUTO_INCREMENT,
            `scriptname` VARCHAR(255) NOT NULL,
            `applied` TIMESTAMP NOT NULL,
            PRIMARY KEY (`schemaversionid`)
        )
'@
        $verificationQuery = "SELECT column_name from INFORMATION_SCHEMA.columns WHERE table_name = '{0}'"
    }
    AfterAll {
        $null = Invoke-DBOQuery @connParams -Database mysql -Query $dropDatabaseScript
    }
    BeforeEach {
        $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
    }
    Context "testing upgrade of the schema table" {
        It "upgrade default schema table" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f 'SchemaVersions')

            $result = Update-DBOSchemaTable @connParams -Database $newDbName
            $result | Should -BeNullOrEmpty

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f 'SchemaVersions')
            $testResults.column_name | Should -Be @('schemaversionid', 'scriptname', 'applied', 'checksum', 'appliedby', 'executiontime')
        }
        It "upgrade custom schema table" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -Be @('schemaversionid', 'scriptname', 'applied', 'checksum', 'appliedby', 'executiontime')
        }
    }
    Context  "$commandName whatif tests" {
        It "should upgrade nothing" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable -WhatIf
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -Be @('schemaversionid', 'scriptname', 'applied')
        }
    }
}
