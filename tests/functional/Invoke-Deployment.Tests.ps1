BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "<type> Invoke-Deployment functional tests" -Tag FunctionalTests -ForEach $types {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName -Type $Type -Internal

        New-Workfolder -Force
        New-TestDatabase -Force
        $tmpPackage = New-DBOPackage -Path (Join-Path $workFolder 'tmp.zip') -ScriptPath $tranFailScripts -Build 1.0 -Force
        $null = Expand-Archive -Path $tmpPackage -DestinationPath $workFolder -Force
        $packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
        $ErrorActionPreference = 'Stop'  # Needed for non-public commands
    }
    AfterAll {
        Remove-TestDatabase
        Remove-Workfolder
    }
    BeforeEach {
        $deploymentConfig = @{
            SqlInstance        = $instance
            Credential         = $credential
            SchemaVersionTable = $logTable
            Silent             = $true
            DeploymentMethod   = 'NoTransaction'
        }
        if ($Type -ne 'Oracle') { $deploymentConfig.Database = $newDbName }
    }
    Context "testing transactional deployment of extracted package" {
        BeforeEach {
            Reset-TestDatabase
        }
        It "Should throw an error and not create any objects" {
            if ($Type -in 'MySQL', 'Oracle') {
                Set-ItResult -Skipped -Because "CREATE TABLE cannot be rolled back in $Type"
            }
            $deploymentConfig.DeploymentMethod = 'SingleTransaction'
            try {
                $null = Invoke-Deployment -Type $Type -PackageFile $packageFileName -Configuration $deploymentConfig
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            Test-DeploymentState -Version 0
        }
    }
    Context "testing non transactional deployment of extracted package" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Invoke-Deployment -Type $Type -PackageFile $packageFileName -Configuration $deploymentConfig
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            #Verifying objects
            $after = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $logTable | Should -BeIn $after.(Get-ColumnName name)
            'a' | Should -BeIn $after.(Get-ColumnName name)
            'b' | Should -Not -BeIn $after.(Get-ColumnName name)
            'c' | Should -Not -BeIn $after.(Get-ColumnName name)
            'd' | Should -Not -BeIn $after.(Get-ColumnName name)
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)

            Test-DeploymentState -Script -Version 1 -HasJournal
        }
        It "should deploy version 2.0" {
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 2) -Configuration $deploymentConfig
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
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 2), (Get-ScriptFile -Version 1) -Configuration $deploymentConfig
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
            $delayScriptFile = [DBOpsFile]::new($delayScript, (Get-Item $delayScript).Name, $true)
        }
        It "should throw timeout error" {
            $deploymentConfig.ExecutionTimeout = 1
            {
                $null = Invoke-Deployment -Type $Type -ScriptFile $delayScriptFile -Configuration $deploymentConfig -OutputFile $outputFile
            } | Should -Throw $timeoutError
            $output = Get-Content $outputFile -Raw
            $output | Should -BeLike $timeoutError
            $output | Should -Not -BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $deploymentConfig.ExecutionTimeout = 6
            $testResults = Invoke-Deployment -Type $Type -ScriptFile $delayScriptFile -Configuration $deploymentConfig -OutputFile $outputFile
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $delayScript).Name
            $testResults.SourcePath | Should -Be (Resolve-Path $delayScript).Path
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 2500
            $output = Get-Content $outputFile -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $deploymentConfig.ExecutionTimeout = 0
            $testResults = Invoke-Deployment -Type $Type -ScriptFile $delayScriptFile -Configuration $deploymentConfig -OutputFile $outputFile
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $delayScript).Name
            $testResults.SourcePath | Should -Be (Resolve-Path $delayScript).Path
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 2500
            $output = Get-Content $outputFile -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            Reset-TestDatabase
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig -WhatIf
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
            $deploymentConfig.Remove('SchemaVersionTable')
            $before = Get-DeploymentTableCount
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script -JournalName SchemaVersions
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)
            Test-DeploymentState -Script -Version 1 -HasJournal -JournalName SchemaVersions
            Get-DeploymentTableCount | Should -Be ($before + 3)
        }
        It "should deploy version 2.0" {
            $deploymentConfig.Remove('SchemaVersionTable')
            $before = Get-DeploymentTableCount
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 2) -Configuration $deploymentConfig
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
            $deploymentConfig.SchemaVersionTable = $null
            $before = Get-DeploymentTableCount
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig
            $testResults | Test-DeploymentOutput -Version 1 -Script
            $testResults.SourcePath | Should -Be (Get-PackageScript -Version 1)
            'Checking whether journal table exists..' | Should -Not -BeIn $testResults.DeploymentLog
            Test-DeploymentState -Script -Version 1
            Get-DeploymentTableCount | Should -Be ($before + 2)
        }
    }
    Context "testing checksum validation deployment" {
        BeforeAll {
            New-Item -Force -ItemType Directory "$workFolder\1", "$workFolder\2"
            $file1 = "$workFolder\1\script.sql"
            $file2 = "$workFolder\2\script.sql"
            "CREATE TABLE a (a int)" | Out-File $file1
            "CREATE TABLE b (a int)" | Out-File $file2
            $scriptObject1 = Get-DbopsFile -Path $file1
            $scriptObject2 = Get-DbopsFile -Path $file2
            Reset-TestDatabase
        }

        It "should deploy script with changed content" {
            $null = Invoke-Deployment -ScriptFile $scriptObject1 -Configuration $deploymentConfig -ChecksumValidation $true
            $testResults = Invoke-Deployment -ScriptFile $scriptObject2 -Configuration $deploymentConfig -ChecksumValidation $true
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be "script.sql"
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.(Get-ColumnName name)
            'a' | Should -BeIn $testResults.(Get-ColumnName name)
            'b' | Should -BeIn $testResults.(Get-ColumnName name)

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName, Checksum FROM $fqn"
            $svResults.ScriptName | Should -Be (@("script.sql") * 2)
            $svResults[0].Checksum | Should -Not -Be $svResults[1].Checksum
        }
    }
    Context "testing registration of scripts" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "should register version 1.0 without creating any objects" {
            $before = Get-DeploymentTableCount
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig -RegisterOnly
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -Script -Register

            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults.(Get-ColumnName name) | Should -Be $logTable
            Get-DeploymentTableCount | Should -Be ($before + 1)

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName FROM $fqn"
            $svResults.ScriptName | Should -Be (Get-JournalScript -Version 1 -Script)
        }
        It "should register version 1.0 + 2.0 without creating any objects" {
            $before = Get-DeploymentTableCount
            $testResults = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1), (Get-ScriptFile -Version 2) -Configuration $deploymentConfig -RegisterOnly
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal -Script -Register


            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $testResults.(Get-ColumnName name) | Should -Be $logTable
            Get-DeploymentTableCount | Should -Be $before

            #Verifying SchemaVersions table
            $fqn = Get-QuotedIdentifier ($logtable)
            $svResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT ScriptName FROM $fqn"
            $svResults.ScriptName | Should -Be (Get-JournalScript -Version 1, 2 -Script)
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            Reset-TestDatabase
        }
        It "Should return terminating error when object exists" {
            # Deploy a non-logged script
            $deploymentConfig.SchemaVersionTable = $null
            $null = Invoke-Deployment -Type $Type -ScriptFile (Get-ScriptFile -Version 1) -Configuration $deploymentConfig
            #Running package
            try {
                $testResults = $null
                $testResults = Invoke-Deployment -Type $Type -PackageFile $packageFileName -Configuration $deploymentConfig
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
                $null = Invoke-Deployment -Type $Type -PackageFile $packageFileName -Configuration $deploymentConfig
                $testResults = "foo"
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
    Context "negative tests" {
        It "should throw if ScriptFile is not DBOpsFile" {
            { Invoke-Deployment -Type $Type -ScriptFile (Get-PackageScript -Version 1) -Configuration $deploymentConfig } | Should -Throw 'Expected DBOpsFile*'
        }
    }
}
