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
    Write-Host "Running PostgreSQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\Cleanup.sql"

$newDbName = "test_dbops_$commandName"
$connParams = @{
    Type        = 'PostgreSQL'
    SqlInstance = $script:postgresqlInstance
    Silent      = $true
    Credential  = $script:postgresqlCredential
}


Describe "Update-DBOSchemaTable Postgresql integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $dropDatabaseScript = @(
            'SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ''{0}'' AND pid <> pg_backend_pid()' -f $newDbName
            'DROP DATABASE IF EXISTS "{0}"' -f $newDbName
        )
        $createDatabaseScript = 'CREATE DATABASE "{0}"' -f $newDbName
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $createDatabaseScript
        $schemaTableQuery = @'
        CREATE TABLE "{0}"
        (
            schemaversionsid serial NOT NULL,
            scriptname character varying(255) NOT NULL,
            applied timestamp without time zone NOT NULL,
            CONSTRAINT {0}_fk PRIMARY KEY (schemaversionsid)
        )
'@
        $verificationQuery = "SELECT column_name from INFORMATION_SCHEMA.columns WHERE table_name = '{0}'"
    }
    AfterAll {
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
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
            $testResults.column_name | Should -BeIn @('schemaversionsid', 'scriptname', 'applied', 'checksum', 'appliedby', 'executiontime')
        }
        It "upgrade custom schema table" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @('schemaversionsid', 'scriptname', 'applied', 'checksum', 'appliedby', 'executiontime')
        }
    }
    Context  "$commandName whatif tests" {
        It "should upgrade nothing" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable -WhatIf
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @('schemaversionsid', 'scriptname', 'applied')
        }
    }
}
