Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\constants.ps1"

$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\Cleanup.sql"

$newDbName = "_test_$commandName"
$connParams = @{
    SqlInstance = $script:mssqlInstance
    Silent = $true
    Credential = $script:mssqlCredential
}

Describe "Update-DBOSchemaTable integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $createDatabaseScript = 'CREATE DATABASE [{0}]' -f $newDbName
        $null = Invoke-DBOQuery @connParams -Database master -Query $dropDatabaseScript
        $null = Invoke-DBOQuery @connParams -Database master -Query $createDatabaseScript
        $schemaTableQuery = @"
            create table {0} (
            [Id] int identity(1,1) not null constraint {0}_pk primary key,
            [ScriptName] nvarchar(255) not null,
            [Applied] datetime not null
            )
"@
        $verificationQuery = "SELECT column_name from INFORMATION_SCHEMA.columns WHERE table_name = '{0}'"
    }
    AfterAll {
        $null = Invoke-DBOQuery @connParams -Database master -Query $dropDatabaseScript
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
            $testResults.column_name | Should -BeIn @('Id', 'ScriptName', 'Applied', 'Checksum', 'AppliedBy', 'ExecutionTime')
        }
        It "upgrade custom schema table" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @('Id', 'ScriptName', 'Applied', 'Checksum', 'AppliedBy', 'ExecutionTime')
        }
    }
    Context  "$commandName whatif tests" {
        It "should upgrade nothing" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query ($schemaTableQuery -f $logTable)

            $result = Update-DBOSchemaTable @connParams -Database $newDbName -SchemaVersionTable $logTable -WhatIf
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @('Id', 'ScriptName', 'Applied')
        }
    }
}
