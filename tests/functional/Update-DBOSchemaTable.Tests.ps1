BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "<type> Update-DBOSchemaTable integration tests" -Tag FunctionalTests -ForEach $types {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type -Internal
        New-TestDatabase -Force
        $verificationQuery = switch ($Type) {
            Oracle { "SELECT column_name from sys.all_tab_columns WHERE table_name = UPPER('{0}')" }
            Default { "SELECT column_name from INFORMATION_SCHEMA.columns WHERE table_name = '{0}'" }
        }
    }
    AfterAll {
        Remove-TestDatabase
    }
    BeforeEach {
        Reset-TestDatabase
    }
    Context "testing upgrade of the schema table" {
        It "upgrade default schema table" {
            $null = Invoke-DBOQuery @dbConnectionParams -Query ($schemaVersionv1.Replace($logTable, "SchemaVersions"))

            $result = Update-DBOSchemaTable @dbConnectionParams
            $result | Should -BeNullOrEmpty

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery @dbConnectionParams -Query ($verificationQuery -f 'SchemaVersions')
            $testResults.column_name | Should -BeIn @($idColumn, 'ScriptName', 'Applied', 'Checksum', 'AppliedBy', 'ExecutionTime')
        }
        It "upgrade custom schema table" {
            $null = Invoke-DBOQuery @dbConnectionParams -Query $schemaVersionv1

            $result = Update-DBOSchemaTable @dbConnectionParams -SchemaVersionTable $logTable
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @dbConnectionParams -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @($idColumn, 'ScriptName', 'Applied', 'Checksum', 'AppliedBy', 'ExecutionTime')
        }
    }
    Context  "$commandName whatif tests" {
        It "should upgrade nothing" {
            $null = Invoke-DBOQuery @dbConnectionParams -Query $schemaVersionv1

            $result = Update-DBOSchemaTable @dbConnectionParams -SchemaVersionTable $logTable -WhatIf
            $result | Should -BeNullOrEmpty

            $testResults = Invoke-DBOQuery @dbConnectionParams -Query ($verificationQuery -f $logTable)
            $testResults.column_name | Should -BeIn @($idColumn, 'ScriptName', 'Applied')
        }
    }
}
