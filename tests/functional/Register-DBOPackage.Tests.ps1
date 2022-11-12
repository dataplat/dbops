BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "<type> Register-DBOPackage integration tests" -Tag FunctionalTests -ForEach $types {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type -Internal

        New-Workfolder -Force
        New-TestDatabase -Force
    }
    AfterAll {
        Remove-TestDatabase
        Remove-Workfolder
    }

    Context "testing registration with CreateDatabase specified" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath (Get-PackageScript -Version 2) -Package $p1 -Build 2.0
            if ($Type -ne 'Oracle') {
                Remove-TestDatabase
            }
        }
        It "should register version 1.0 in a new database using -CreateDatabase switch" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle doens't have databases"
            }
            $testResults = Register-DBOPackage $p1 -CreateDatabase @dbConnectionParams -SchemaVersionTable $logTable
            $testResults | Test-DeploymentOutput -Version 1, 2 -HasJournal -Register
            "Created database $newDbName" | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults.(Get-ColumnName name) | Should -Be $logTable

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName FROM $fqn"
            $svResults.ScriptName | Should -Be (Get-JournalScript -Version 1, 2)
        }
    }
    Context "testing registration of scripts" {
        BeforeAll {
            $p2 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv2" -Build 1.0 -Force
            $p2 = Add-DBOBuild -ScriptPath (Get-PackageScript -Version 2) -Package $p2 -Build 2.0
            Reset-TestDatabase
        }
        It "should register version 1.0 without creating any objects" {
            $before = Get-DeploymentTableCount
            $testResults = Register-DBOPackage -Package $p2 -Build 1.0 @dbConnectionParams -SchemaVersionTable $logTable
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Register

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults.(Get-ColumnName name) | Should -Be $logTable
            Get-DeploymentTableCount | Should -Be ($before + 1)

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName FROM $fqn"
            $svResults.ScriptName | Should -Be (Get-JournalScript -Version 1)
        }
        It "should register version 1.0 + 2.0 without creating any objects" {
            $before = Get-DeploymentTableCount
            $testResults = Register-DBOPackage -Package $p2 @dbConnectionParams -SchemaVersionTable $logTable
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal -Register

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults.(Get-ColumnName name) | Should -Be $logTable
            Get-DeploymentTableCount | Should -Be $before

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName FROM $fqn"
            $svResults.ScriptName | Should -Be (Get-JournalScript -Version 1, 2)

        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy nothing" {
            $testResults = Register-DBOPackage $p1 @dbConnectionParams -SchemaVersionTable $logTable -WhatIf
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Register -WhatIf

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults | Should -BeNullOrEmpty
        }
    }
}
