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
    Write-Host "Running MySQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

Describe "Install-DBOPackage MySQL tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
        $unpackedFolder = Join-Path $workFolder 'unpacked'
        $logTable = "testdeploymenthistory"
        $cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\Cleanup.sql"
        $tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\transactional-failure"
        $v1scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\1.sql"
        $v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
        $v2scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\2.sql"
        $v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
        $verificationScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\verification\select.sql"
        $packageName = Join-Path $workFolder "TempDeployment.zip"
        $packageNamev1 = Join-Path $workFolder "TempDeployment_v1.zip"
        $fullConfig = Join-PSFPath -Normalize "$workFolder\tmp_full_config.json"
        $fullConfigSource = Join-PSFPath -Normalize "$testRoot\etc\full_config.json"
        $testPassword = 'TestPassword'
        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
        $newDbName = "test_dbops_InstallDBOPackage"
        $standardOutput = @(
            "Beginning database upgrade"
            "Checking whether journal table exists.."
            "Journal table does not exist"
            "Executing Database Server script '1.0\1.sql'"
            "Checking whether journal table exists.."
            "Upgrade successful"
        )
        $standardOutput2 = @(
            "Beginning database upgrade"
            "Checking whether journal table exists.."
            "Fetching list of already executed scripts."
            "Executing Database Server script '2.0\2.sql'"
            "Checking whether journal table exists.."
            "-------------"
            "|   a |   b |"
            "-------------"
            "|   1 |   2 |"
            "-------------"
            ""
            ""
            "Upgrade successful"
        )
        $dropDatabaseScript = 'DROP DATABASE IF EXISTS `{0}`' -f $newDbName
        $createDatabaseScript = 'CREATE DATABASE IF NOT EXISTS `{0}`' -f $newDbName

        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
    }
    Context "testing transactional deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
        }
        It "Should throw an error and create two tables" {
            #Running package
            { $null = Install-DBOPackage -Type MySQL $packageName -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent } | Should throw "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            # Create table cannot be rolled back in MySQL
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }

    }
    Context "testing non transactional deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
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
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Name $p1 -Build 2.0
            #versions should not be sorted by default - creating a package where 1.0 is the second build
            $p3 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv3" -Build 2.0 -Force
            $null = Add-DBOBuild -ScriptPath $v2scripts -Name $p3 -Build 1.0
            $outputFile = Join-PSFPath -Normalize "$workFolder\log.txt"
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage -Type MySQL $p1 -Build '1.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the `{0}` table' -f $logTable | Should -BeIn $output
            'The `{0}` table has been created' -f $logTable | Should -BeIn $output

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should re-deploy version 1.0 pipelining a string" {
            $testResults = "$workFolder\pv1.zip" | Install-DBOPackage -Type MySQL -Build '1.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using pipelined Get-DBOPackage" {
            $testResults = Get-DBOPackage "$workFolder\pv1.zip" | Install-DBOPackage -Type MySQL -Build '1.0', '2.0' -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $output | Should BeIn $standardOutput2
            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should re-deploy version 2.0 using pipelined FileSystemObject" {
            $testResults = Get-Item "$workFolder\pv1.zip" | Install-DBOPackage -Type MySQL -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
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
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv3.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (@((Get-Item $v1scripts).Name | ForEach-Object { "2.0\$_" }), ((Get-Item $v2scripts).Name | ForEach-Object { "1.0\$_" }))
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv3.zip")
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
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $file = Join-PSFPath -Normalize "$workFolder\delay.sql"
            "DO SLEEP(5); SELECT 'Successful!'" | Out-File $file
            $null = New-DBOPackage -ScriptPath $file -Name "$workFolder\delay" -Build 1.0 -Force -Configuration @{ ExecutionTimeout = 2 }
            $timeoutError = if ($PSVersionTable.PSVersion.Major -eq 6) { 'Fatal error encountered during command execution' } else { 'Timeout expired.'}
        }
        BeforeEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error " {
            { $null = Install-DBOPackage -Type MySQL "$workFolder\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent } | Should throw $timeoutError
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike "*$timeoutError*"
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike "*$timeoutError*"
            $output | Should BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\delay.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageNamev1 -Build 1.0
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
        }
        It "should deploy nothing" {
            $testResults = Install-DBOPackage -Type MySQL $packageNamev1 -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SourcePath | Should Be (Get-Item $packageNamev1).FullName
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
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            $testResults = Install-DBOPackage -Type MySQL $p1 -CreateDatabase -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
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
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force -ConfigurationFile $fullConfig
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force -Configuration @{
                SqlInstance        = 'nonexistingServer'
                Database           = 'nonexistingDB'
                SchemaVersionTable = 'nonexistingSchema.nonexistinTable'
                DeploymentMethod   = "SingleTransaction"
            }
            $outputFile = "$workFolder\log.txt"
        }
        It "should deploy version 1.0 using -Configuration file override" {
            $configFile = "$workFolder\config.custom.json"
            @{
                SqlInstance        = $script:mysqlInstance
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } | ConvertTo-Json -Depth 2 | Out-File $configFile -Force
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -Configuration $configFile -OutputFile "$workFolder\log.txt" -Credential $script:mysqlCredential
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the `{0}` table' -f $logTable | Should -BeIn $output
            'The `{0}` table has been created' -f $logTable | Should -BeIn $output

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using -Configuration object override" {
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv2.zip" -Configuration @{
                SqlInstance        = $script:mysqlInstance
                Credential         = $script:mysqlCredential
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $output | Should BeIn $standardOutput2
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
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force
            $outputFile = "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
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
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv2.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
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
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
        }
        AfterEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
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
        BeforeAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
        }
        BeforeEach {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $cleanupScript
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "DROP SCHEMA IF EXISTS testschema", "CREATE SCHEMA testschema"
        }
        AfterEach {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "DROP SCHEMA IF EXISTS testschema"
        }
        It "should deploy version 1.0 into testschema" {
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -SqlInstance $script:mysqlInstance -Credential $script:mysqlCredential -Database $newDbName -Silent -Schema testschema
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
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
            $after = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Schema testschema -Silent -Credential $script:mysqlCredential -InputFile $verificationScript
            'SchemaVersions' | Should -BeIn $after.name
        }
    }
    Context "testing deployment using variables in config" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force -Configuration @{SqlInstance = '#{srv}'; Database = '#{db}'}
            $outputFile = "$workFolder\log.txt"
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
        }
        AfterAll {
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -Credential $script:mysqlCredential -Variables @{srv = $script:mysqlInstance; db = $newDbName} -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the `{0}` table' -f $logTable | Should -BeIn $output
            'The `{0}` table has been created' -f $logTable | Should -BeIn $output
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
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery -Type MySQL -SqlInstance $script:mysqlInstance -Silent -Credential $script:mysqlCredential -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
        }
        It "should deploy version 1.0" {
            $configCS = New-DBOConfig -Configuration @{
                SqlInstance = $script:mysqlInstance
                Database    = $newDbName
                Credential  = $script:mysqlCredential
            }
            $connectionString = Get-ConnectionString -Configuration $configCS -Type MySQL
            $testResults = Install-DBOPackage -Type MySQL "$workFolder\pv1.zip" -ConnectionString $connectionString -SqlInstance willBeIgnored -Database IgnoredAsWell -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should BeNullOrEmpty
            $testResults.Database | Should BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the `{0}` table' -f $logTable | Should -BeIn $output
            'The `{0}` table has been created' -f $logTable | Should -BeIn $output
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
