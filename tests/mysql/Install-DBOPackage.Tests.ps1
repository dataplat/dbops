Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }
$testRoot = (Get-Item $here\.. ).FullName

if (!$Batch) {
    # Is not a part of the global batch => import module
    # Explicitly import the module for testing
    Import-Module "$testRoot\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName MySQL tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

Describe "Install-DBOPackage MySQL integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $unpackedFolder = Join-Path 'TestDrive:' 'unpacked'
        $logTable = "testdeploymenthistory"
        $cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\Cleanup.sql"
        $tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\transactional-failure"
        $v1scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\1.sql"
        $v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
        $v2scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\2.sql"
        $v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
        $verificationScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\verification\select.sql"
        $packageName = Join-Path 'TestDrive:' "TempDeployment.zip"
        $packageNamev1 = Join-Path 'TestDrive:' "TempDeployment_v1.zip"
        $fullConfig = Join-PSFPath -Normalize "TestDrive:\tmp_full_config.json"
        $fullConfigSource = Join-PSFPath -Normalize "$testRoot\etc\full_config.json"
        $testPassword = 'TestPassword'
        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
        $newDbName = "test_dbops_InstallDBOPackage"
        $dropDatabaseScript = 'DROP DATABASE IF EXISTS `{0}`' -f $newDbName
        $createDatabaseScript = 'CREATE DATABASE IF NOT EXISTS `{0}`' -f $newDbName

        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
        $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
        $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database mysql -Query $createDatabaseScript
    }
    AfterAll {
        $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
    }
    Context "testing transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        BeforeEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            try {
                $null = Install-DBOPackage -Type MySQL $packageName -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }

    }
    Context "testing non transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOPackage -Type MySQL $packageName -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Name $p1 -Build 2.0
            #versions should not be sorted by default - creating a package where 1.0 is the second build
            $p3 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv3" -Build 2.0 -Force
            $null = Add-DBOBuild -ScriptPath $v2scripts -Name $p3 -Build 1.0
            $outputFile = Join-PSFPath -Normalize "TestDrive:\log.txt"
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage -Type MySQL $p1 -Build '1.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log1.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should re-deploy version 1.0 pipelining a string" {
            $testResults = "TestDrive:\pv1.zip" | Install-DBOPackage -Type MySQL -Build '1.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$TestDrive\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using pipelined Get-DBOPackage" {
            $testResults = Get-DBOPackage "TestDrive:\pv1.zip" | Install-DBOPackage -Type MySQL -Build '1.0', '2.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log2.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should re-deploy version 2.0 using pipelined FileSystemObject" {
            $testResults = Get-Item "TestDrive:\pv1.zip" | Install-DBOPackage -Type MySQL -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$TestDrive\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should deploy in a reversed order: 2.0 before 1.0" {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv3.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (@((Get-Item $v1scripts).Name | ForEach-Object { "2.0\$_" }), ((Get-Item $v2scripts).Name | ForEach-Object { "1.0\$_" }))
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv3.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $file = Join-PSFPath -Normalize "TestDrive:\delay.sql"
            "DO SLEEP(5); SELECT 'Successful!'" | Out-File $file
            $null = New-DBOPackage -ScriptPath $file -Name "TestDrive:\delay" -Build 1.0 -Force -Configuration @{ ExecutionTimeout = 2 }
        }
        BeforeEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error " {
            try {
                $null = Install-DBOPackage -Type MySQL "TestDrive:\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            }
            catch {
                $testResults = $_
            }
            $testResults | Should Not Be $null
            $testResults.Exception.Message | Should BeLike '*Timeout Expired.*'
            $output = Get-Content "TestDrive:\log.txt" -Raw
            $output | Should BeLike '*Timeout Expired*'
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\delay.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\delay.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageNamev1 -Build 1.0
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
            Remove-Item $packageNamev1
        }
        It "should deploy nothing" {
            $testResults = Install-DBOPackage -Type MySQL $packageNamev1 -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SourcePath | Should Be $packageNamev1
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment with CreateDatabase specified" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
        }
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            # Drop database and allow the function to create it
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
            $testResults = Install-DBOPackage -Type MySQL $p1 -CreateDatabase -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Configuration.CreateDatabase | Should Be $true
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog
            "Created database $newDbName" | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment with configuration overrides" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force -ConfigurationFile $fullConfig
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "TestDrive:\pv2" -Build 2.0 -Force -Configuration @{
                SqlInstance        = 'nonexistingServer'
                Database           = 'nonexistingDB'
                SchemaVersionTable = 'nonexistingSchema.nonexistinTable'
                DeploymentMethod   = "SingleTransaction"
            }
            $outputFile = "TestDrive:\log.txt"
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0 using -Configuration file override" {
            $configFile = "TestDrive:\config.custom.json"
            @{
                SqlInstance        = $script:mysqlInstance
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } | ConvertTo-Json -Depth 2 | Out-File $configFile -Force
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -Configuration $configFile -OutputFile "TestDrive:\log.txt" -Credential $script:mysqlCredential
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log1.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using -Configuration object override" {
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv2.zip" -Configuration @{
                SqlInstance        = $script:mysqlInstance
                Credential         = $script:mysqlCredential
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } -OutputFile "TestDrive:\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv2.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log2.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "TestDrive:\pv2" -Build 2.0 -Force
            $outputFile = "TestDrive:\log.txt"
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv2.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv2.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeEach {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should Not BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with defined schema" {
        BeforeEach {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "CREATE SCHEMA testschema"
        }
        AfterEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0 into testschema" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent -Schema testschema
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Configuration.Schema | Should Be 'testschema'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $after = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $after | Where-Object name -eq 'SchemaVersions' | Select-Object -ExpandProperty schema | Should Be 'testschema'
            # disabling for SQL Server, but leaving for other rdbms in perspective
            # $testResults | Where-Object Name -eq 'a' | Select-Object -ExpandProperty schema | Should Be 'testschema'
            # $testResults | Where-Object Name -eq 'b' | Select-Object -ExpandProperty schema | Should Be 'testschema'
            ($after | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing deployment using variables in config" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force -Configuration @{SqlInstance = '#{srv}'; Database = '#{db}'}
            $outputFile = "TestDrive:\log.txt"
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -Credential $script:mysqlCredential -Variables @{srv = $script:mysqlInstance; db = $newDbName} -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log1.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing deployment with custom connection string" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "TestDrive:\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $connectionString = "Server=$script:mysqlInstance;Database=$newDbName;"
            if ($script:mysqlCredential) {
                $connectionString += "User ID=$($script:mysqlCredential.UserName);Password=$($script:mysqlCredential.GetNetworkCredential().Password)"
            }
            else {
                $connectionString += "Trusted_Connection=True"
            }
            $testResults = Install-DBOPackage -Type MySQL "TestDrive:\pv1.zip" -ConnectionString $connectionString -SqlInstance willBeIgnored -Database IgnoredAsWell -SchemaVersionTable $logTable -OutputFile "TestDrive:\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should BeNullOrEmpty
            $testResults.Database | Should BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$TestDrive\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "TestDrive:\log.txt" | Select-Object -Skip 1
            $output | Should Be (Get-Content "$testRoot\etc\mysql-tests\log1.txt")
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
