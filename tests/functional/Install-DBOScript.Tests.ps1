BeforeDiscovery {
    . $PSScriptRoot\detect_types.ps1
}

Describe "<type> Install-DBOScript integration tests" -Tag IntegrationTests -ForEach $types {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type

        New-Workfolder -Force
        New-TestDatabase -Force
    }
    AfterAll {
        Remove-TestDatabase
        Remove-Workfolder
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
    }
    Context "testing regular deployment with CreateDatabase specified" {
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle doens't have databases"
            }
            # drop the database before installing the package
            Remove-TestDatabase
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) -CreateDatabase @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)
            "Created database $newDbName" | Should -BeIn $testResults.DeploymentLog

            Test-DeploymentState -Script -Version 1 -HasJournal
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeEach {
            Reset-TestDatabase
        }
        It "Should throw an error and not create any objects" {
            if ($Type -in 'MySQL', 'Oracle') {
                Set-ItResult -Skipped -Because "CREATE TABLE cannot be rolled back in $Type"
            }
            #Running package
            try {
                $null = Install-DBOScript -Path $tranFailScripts @dbConnectionParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            Test-DeploymentState -Script -Version 0
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @dbConnectionParams -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOScript -Path $tranFailScripts @dbConnectionParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            #Verifying objects
            $after = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $tableColumn = switch ($Type) {
                Oracle { "NAME" }
                Default { "name" }
            }
            $logTable | Should -BeIn $after.$tableColumn
            'a' | Should -BeIn $after.$tableColumn
            'b' | Should -Not -BeIn $after.$tableColumn
            'c' | Should -Not -BeIn $after.$tableColumn
            'd' | Should -Not -BeIn $after.$tableColumn
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams -SchemaVersionTable $logTable
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)

            Test-DeploymentState -Script -Version 1 -HasJournal
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 2) @dbConnectionParams -SchemaVersionTable $logTable
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 2)

            Test-DeploymentState -Script -Version 2 -HasJournal
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 2, 1) @dbConnectionParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-JournalScript -Version 2, 1 -Script)
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 2, 1)
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            Test-DeploymentState -Script -Version 2 -HasJournal
            #Verifying order
            $r1 = Invoke-DBOQuery @dbConnectionParams -Query "SELECT SCRIPTNAME FROM $logtable ORDER BY $idColumn"
            $r1.(Get-ColumnName ScriptName) | Should -Be (Get-JournalScript -Version 2, 1 -Script)
        }
    }
    Context "testing timeouts" {
        BeforeEach {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle driver doesn't support timeouts"
            }
            Reset-TestDatabase
        }
        It "should throw timeout error" {
            try {
                $null = Install-DBOScript -ScriptPath $delayScript @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile -ExecutionTimeout 1
            }
            catch {
                $testResults = $_
            }
            $testResults | Should -Not -BeNullOrEmpty
            $testResults.Exception.Message | Should -BeLike $timeoutError
            $output = Get-Content $outputFile -Raw
            $output | Should -BeLike $timeoutError
            $output | Should -Not -BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOScript -ScriptPath $delayScript @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile -ExecutionTimeout 6
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $delayScript).Name
            $testResults.SourcePath | Should -Be (Resolve-Path $delayScript).Path
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $output = Get-Content $outputFile -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOScript -ScriptPath $delayScript @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile -ExecutionTimeout 0
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $delayScript).Name
            $testResults.SourcePath | Should -Be (Resolve-Path $delayScript).Path
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $output = Get-Content $outputFile -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
    }
    Context "testing variable replacement" {
        BeforeAll {
            $file = "$workFolder\varQuery.sql"
            $varQuery | Out-File $file
        }
        It "should return replaced variables" {
            $vars = @{
                var1 = 1337
                var2 = 'Replaced!'
            }
            $testResults = Install-DBOScript -ScriptPath $file @dbConnectionParams -SchemaVersionTable $null -OutputFile $outputFile -Variables $vars
            $testResults.Successful | Should -Be $true
            $outputFile | Should -FileContentMatch '1337'
            $outputFile | Should -FileContentMatch 'Replaced!'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy nothing" {
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams -SchemaVersionTable $logTable -WhatIf
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script -WhatIf
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)

            "No deployment performed - WhatIf mode." | Should -BeIn $testResults.DeploymentLog
            Get-JournalScript -Version 1 -Script | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should -BeIn $testResults.DeploymentLog
            Test-DeploymentState -Script -Version 0
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script -JournalName SchemaVersions
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)
            Test-DeploymentState -Script -Version 1 -HasJournal -JournalName SchemaVersions
            Get-DeploymentTableCount | Should -Be ($before + 3)
        }
        It "should deploy version 2.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 2) @dbConnectionParams
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal -Script -JournalName SchemaVersions
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 2)
            Test-DeploymentState -Script -Version 2 -HasJournal -JournalName SchemaVersions
            Get-DeploymentTableCount | Should -Be ($before + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeAll {
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams -SchemaVersionTable $null
            $testResults | Test-DeploymentOutput -Version 1 -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)
            'Checking whether journal table exists..' | Should -Not -BeIn $testResults.DeploymentLog
            Test-DeploymentState -Script -Version 1
            Get-DeploymentTableCount | Should -Be ($before + 2)
        }
    }
    Context "testing deployments to the native DbUp SchemaVersion table" {
        BeforeEach {
            Reset-TestDatabase
        }
        It "Should deploy version 1 to an older schemaversion table" {
            # create old SchemaVersion table
            $null = Invoke-DBOQuery @dbConnectionParams -Query $schemaVersionv1
            $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-JournalScript -Version 1 -Script)
            Test-DeploymentState -Version 1 -Script -Legacy -HasJournal
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            Reset-TestDatabase
            $null = Install-DBOScript -ScriptPath (Get-PackageScript -Version 1) @dbConnectionParams -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            try {
                $testResults = $null
                $testResults = Install-DBOScript -Path $tranFailScripts -SchemaVersionTable $logTable -DeploymentMethod NoTransaction @dbConnectionParams
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should -Be $null
            $errorObject | Should -Not -BeNullOrEmpty
            $errorObject.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOScript -Path $tranFailScripts @dbConnectionParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
                $testResults = Install-DBOScript -ScriptPath (Get-PackageScript -Version 2) @dbConnectionParams -SchemaVersionTable $logTable
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should -Be $null
            $errorObject | Should -Not -BeNullOrEmpty
            $errorObject.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            Test-DeploymentState -Version 1 -Script -HasJournal
        }
    }
}
