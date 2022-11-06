BeforeDiscovery {
    . $PSScriptRoot\detect_types.ps1
}

Describe "<type> Install-DBOPackage integration tests" -Tag IntegrationTests -ForEach $types {
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
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle doens't have databases"
            }
            # Drop database and allow the function to create it
            Remove-TestDatabase
            $testResults = Install-DBOPackage $p1 -CreateDatabase @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.Configuration.CreateDatabase | Should -Be $true
            "Created database $newDbName" | Should -BeIn $testResults.DeploymentLog

            Test-DeploymentState -Version 1 -HasJournal
        }
    }
    Context "testing transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            Reset-TestDatabase
        }
        BeforeEach {
            Reset-TestDatabase
        }
        It "Should throw an error and not create any objects" {
            if ($Type -in 'MySQL', 'Oracle') {
                Set-ItResult -Skipped -Because "CREATE TABLE cannot be rolled back in $Type"
            }
            try {
                $null = Install-DBOPackage $packageName @dbConnectionParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")

            Test-DeploymentState -Version 0
        }

    }
    Context "testing non transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOPackage $packageName @dbConnectionParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -BeLike (Get-TableExistsMessage "a")
            #Verifying objects
            $testResults = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            $tableColumn = switch ($Type) {
                Oracle { "NAME" }
                Default { "name" }
            }
            $logTable | Should -BeIn $testResults.$tableColumn
            'a' | Should -BeIn $testResults.$tableColumn
            'b' | Should -Not -BeIn $testResults.$tableColumn
            'c' | Should -Not -BeIn $testResults.$tableColumn
            'd' | Should -Not -BeIn $testResults.$tableColumn
        }
    }
    Context "testing regular deployment" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath (Get-PackageScript -Version 2) -Name $p1 -Build 2.0
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage $p1 -Build '1.0' @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile1)
            Test-DeploymentState -Version 1 -HasJournal
        }
        It "should re-deploy version 1.0 pipelining a string" {
            $testResults = "$workFolder\pv1.zip" | Install-DBOPackage -Build '1.0' @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -BeNullOrEmpty
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            $noNewScriptsText | Should -BeIn $testResults.DeploymentLog
            $noNewScriptsText | Should -BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            Test-DeploymentState -Version 1 -HasJournal
        }
        It "should deploy version 2.0 using pipelined Get-DBOPackage" {
            $testResults = Get-DBOPackage "$workFolder\pv1.zip" | Install-DBOPackage -Build '1.0', '2.0' @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile2)
            Test-DeploymentState -Version 2 -HasJournal
        }
        It "should re-deploy version 2.0 using pipelined FileSystemObject" {
            $testResults = Get-Item "$workFolder\pv1.zip" | Install-DBOPackage @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -BeNullOrEmpty
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            $noNewScriptsText | Should -BeIn $testResults.DeploymentLog
            $noNewScriptsText | Should -BeIn (Get-Content $outputFile | Select-Object -Skip 1)
            Test-DeploymentState -Version 2 -HasJournal
        }
    }
    Context "testing reversed deployment" {
        BeforeAll {
            #versions should not be sorted by default - creating a package where 1.0 is the second build
            $p3 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv3" -Build 2.0 -Force
            $null = Add-DBOBuild -ScriptPath (Get-PackageScript -Version 2) -Name $p3 -Build 1.0
            Reset-TestDatabase
        }
        It "should deploy in a reversed order: 2.0 before 1.0" {
            $testResults = Install-DBOPackage "$workFolder\pv3.zip" @dbConnectionParams -SchemaVersionTable $logTable -OutputFile $outputFile
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (@((Get-Item (Get-PackageScript -Version 1)).Name | ForEach-Object { "2.0\$_" }), ((Get-Item (Get-PackageScript -Version 2)).Name | ForEach-Object { "1.0\$_" }))
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv3.zip")

            Test-DeploymentState -Version 2 -HasJournal
        }
    }
    Context "testing pre and post-script deployment" {
        BeforeEach {
            Reset-TestDatabase
        }
        It "should deploy version 1.0 with prescripts" {
            $prePackage = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -PreScriptPath (Get-PackageScript -Version 2) -Force
            $testResults = Install-DBOPackage $prePackage -Build '1.0' @dbConnectionParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be '.dbops.prescripts\2.sql', (Get-JournalScript -Version 1)
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog
            "Executing Database Server script '.dbops.prescripts\2.sql'" | Should -BeIn $testResults.DeploymentLog
            "Executing Database Server script '$(Get-JournalScript -Version 1)'" | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            Test-DeploymentState -Version 2 -HasJournal

            # Validate log table only contains one record
            $logResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT count(*) from $logTable" -As SingleValue
            $logResults | Should -Be 1
        }
        It "should deploy version 1.0 with postscripts" {
            $postPackage = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -PostScriptPath (Get-PackageScript -Version 2) -Force
            $testResults = Install-DBOPackage $postPackage -Build '1.0' @dbConnectionParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-JournalScript -Version 1), '.dbops.postscripts\2.sql'
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog
            "Executing Database Server script '.dbops.postscripts\2.sql'" | Should -BeIn $testResults.DeploymentLog
            "Executing Database Server script '$(Get-JournalScript -Version 1)'" | Should -BeIn $testResults.DeploymentLog

            Test-DeploymentState -Version 2 -HasJournal

            # Validate log table only contains one record
            $logResults = Invoke-DBOQuery @dbConnectionParams -Query "SELECT count(*) from $logTable" -As SingleValue
            $logResults | Should -Be 1
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $delayScript -Name "$workFolder\delay" -Build 1.0 -Force -Configuration @{ ExecutionTimeout = 1 }
        }
        BeforeEach {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle driver doesn't support timeouts"
            }
            Reset-TestDatabase
        }
        It "should throw timeout error " {
            try {
                $null = Install-DBOPackage "$workFolder\delay.zip" @dbConnectionParams -OutputFile $outputFile
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
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @dbConnectionParams -OutputFile $outputFile -ExecutionTimeout 6
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be '1.0\delay.sql'
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @dbConnectionParams -OutputFile $outputFile -ExecutionTimeout 0
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be '1.0\delay.sql'
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            $output = Get-Content $outputFile -Raw
            $output | Should -Not -BeLike $timeoutError
            $output | Should -BeLike '*Successful!*'
        }
    }
    Context "WhatIf tests" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name $packageNamev1 -Build 1.0
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
            Remove-Item $packageNamev1
        }
        It "should deploy nothing" {
            $testResults = Install-DBOPackage $packageNamev1 @dbConnectionParams -SchemaVersionTable $logTable -WhatIf
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -WhatIf
            $testResults.SourcePath | Should -Be $packageNamev1
            (Get-JournalScript -Version 1) | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should -BeIn $testResults.DeploymentLog
            Test-DeploymentState -Version 0
        }
    }
    Context "testing regular deployment with configuration overrides" {
        BeforeAll {
            . Join-PSFPath $PSScriptRoot "..\..\internal\functions\ConvertTo-EncryptedString.ps1" -Normalize
            $encryptedString = 'TestPassword' | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
            (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force -ConfigurationFile $fullConfig
            $p2 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 2) -Name "$workFolder\pv2" -Build 2.0 -Force -Configuration @{
                SqlInstance        = 'nonexistingServer'
                Database           = 'nonexistingDB'
                SchemaVersionTable = 'nonexistingSchema.nonexistinTable'
                DeploymentMethod   = "SingleTransaction"
            }
            Reset-TestDatabase
        }
        It "should deploy version 1.0 using -Configuration file override" {
            $configFile = "$workFolder\config.custom.json"
            $config = @{
                SqlInstance        = $instance
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            }
            if ($Type -ne 'Oracle') { $config.Database = $newDbName}
            $config | ConvertTo-Json -Depth 2 | Out-File $configFile -Force
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" -Type $Type -Configuration $configFile -OutputFile $outputFile -Credential $credential
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")

            $output = Get-Content $outputFile | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile1)
            Test-DeploymentState -Version 1 -HasJournal
        }
        It "should deploy version 2.0 using -Configuration object override" {
            $config = @{
                SqlInstance        = $instance
                Credential         = $credential
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            }
            if ($Type -ne 'Oracle') { $config.Database = $newDbName}
            $testResults = Install-DBOPackage "$workFolder\pv2.zip" -Configuration $config -Type $Type -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")

            $output = Get-Content $outputFile | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile2)

            Test-DeploymentState -Version 2 -HasJournal
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            $p2 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 2) -Name "$workFolder\pv2" -Build 2.0 -Force
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @dbConnectionParams
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -JournalName 'SchemaVersions'
            Test-DeploymentState -Version 1 -HasJournal -JournalName 'SchemaVersions'
            Get-DeploymentTableCount | Should -Be ($before + 3)
        }
        It "should deploy version 2.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv2.zip" @dbConnectionParams
            $testResults | Test-DeploymentOutput -Version 2 -HasJournal -JournalName 'SchemaVersions'
            Test-DeploymentState -Version 2 -HasJournal -JournalName 'SchemaVersions'

            #Verifying objects
            Test-DeploymentState -Version 2 -HasJournal -JournalName 'SchemaVersions'
            Get-DeploymentTableCount | Should -Be ($before + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeEach {
            $null = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            Reset-TestDatabase
        }
        AfterEach {
            Reset-TestDatabase
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @dbConnectionParams -SchemaVersionTable $null
            $testResults | Test-DeploymentOutput -Version 1
            Test-DeploymentState -Version 1
            Get-DeploymentTableCount | Should -Be ($before + 2)
        }
    }
    Context "testing deployment with defined schema" {
        BeforeEach {
            if ($Type -eq 'Oracle') {
                Set-ItResult -Skipped -Because "Oracle user is bound to a single schema"
            }
            $null = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            Reset-TestDatabase
            $schemaName = 'testschema'

            $null = Invoke-DBOQuery @dbConnectionParams -Query "CREATE SCHEMA $schemaName"
        }
        AfterEach {
            Reset-TestDatabase
        }
        It "should deploy version 1.0 into testschema" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @dbConnectionParams -Schema $schemaName
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -JournalName 'SchemaVersions'
            $testResults.Configuration.Schema | Should -Be $schemaName

            if ($Type -eq 'MySQL') {
                $after = Invoke-DBOQuery @dbConnectionParams -Schema $schemaName -InputFile $verificationScript
            }
            else {
                $after = Invoke-DBOQuery @dbConnectionParams -InputFile $verificationScript
            }
            $after | Where-Object name -eq 'SchemaVersions' | Select-Object -ExpandProperty schema | Should -Be $schemaName
            $after.Count | Should -Be ($before + 3)
        }
    }
    Context "testing deployment using variables in config" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force -Configuration @{SqlInstance = '#{srv}'; Database = '#{db}' }
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" -Type $Type -Credential $credential -Variables @{srv = $instance; db = $newDbName } -SchemaVersionTable $logTable -OutputFile $outputFile -Silent
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal
            Test-DeploymentState -Version 1 -HasJournal
            Get-DeploymentTableCount | Should -Be ($before + 3)

            $output = Get-Content $outputFile | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile1)
        }
    }
    Context "testing deployment with custom connection string" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" -Type $Type -ConnectionString $connectionString -SqlInstance willBeIgnored -Database IgnoredAsWell -SchemaVersionTable $logTable -OutputFile $outputFile -Silent
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-JournalScript -Version 1)
            $testResults.SqlInstance | Should -BeNullOrEmpty
            $testResults.Database | Should -BeNullOrEmpty

            $output = Get-Content $outputFile | Select-Object -Skip 1
            $output | Should -Be (Get-Content $logFile1)
            Test-DeploymentState -Version 1 -HasJournal
        }
    }
    Context "testing deployment from a package with an absolute path" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force -Absolute
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $before = Get-DeploymentTableCount
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @dbConnectionParams
            $testResults.Successful | Should -Be $true
            $absolutePath = Get-Item (Get-PackageScript -Version 1) | ForEach-Object { Join-PSFPath 1.0 ($_.FullName -replace '^/|^\\|^\\\\|\.\\|\./|:', "") }
            $testResults.Scripts.Name | Should -BeIn ($absolutePath -replace '/', '\')

            #Verifying objects
            Test-DeploymentState -Version 1 -HasJournal -JournalName 'SchemaVersions'
            Get-DeploymentTableCount | Should -Be ($before + 3)
        }
    }
    Context "testing deployment from a package using an external config file" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath (Get-PackageScript -Version 1) -Name "$workFolder\pv1" -Build 1.0 -Force
            Reset-TestDatabase
        }
        AfterAll {
            Reset-TestDatabase
        }
        It "should deploy version 1.0" {
            $before = Get-DeploymentTableCount
            $configData = @{
                SqlInstance = $instance
                Database    = $newDbName
                Silent      = $true
            }
            if ($credential) {
                $configData += @{
                    Username = $credential.UserName
                    Password = $credential.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force
                }
            }
            $config = $p1 | Get-DBOConfig -Configuration $configData
            $config.SaveToFile("$workFolder\config.json")

            $testResults = Install-DBOPackage -Type $Type -Path $p1.FullName -Configuration $workFolder\config.json -OutputFile $outputFile
            $testResults | Test-DeploymentOutput -Version 1 -HasJournal -JournalName 'SchemaVersions'
            Test-DeploymentState -Version 1 -HasJournal -JournalName 'SchemaVersions'
            Get-DeploymentTableCount | Should -Be ($before + 3)
        }
    }
}
