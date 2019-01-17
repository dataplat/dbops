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
    Write-Host "Running PostgreSQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"
$connParams = @{
    Type        = 'PostgreSQL'
    SqlInstance = $script:postgresqlInstance
    Silent      = $true
    Credential  = $script:postgresqlCredential
}

Describe "Install-DBOPackage PostgreSQL tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
        $unpackedFolder = Join-Path $workFolder 'unpacked'
        $logTable = "testdeploymenthistory"
        $cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\Cleanup.sql"
        $tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\transactional-failure"
        $v1scripts = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\success\1.sql"
        $v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
        $v2scripts = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\success\2.sql"
        $v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
        $verificationScript = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\verification\select.sql"
        $packageName = Join-Path $workFolder "TempDeployment.zip"
        $packageNamev1 = Join-Path $workFolder "TempDeployment_v1.zip"
        $fullConfig = Join-PSFPath -Normalize "$workFolder\tmp_full_config.json"
        $fullConfigSource = Join-PSFPath -Normalize "$testRoot\etc\full_config.json"
        $testPassword = 'TestPassword'
        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
        $newDbName = "test_dbops_installdbopackage"
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
        $dropDatabaseScript = @(
            'SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ''{0}'' AND pid <> pg_backend_pid()' -f $newDbName
            'DROP DATABASE IF EXISTS {0}' -f $newDbName
        )
        $createDatabaseScript = 'CREATE DATABASE {0}' -f $newDbName

        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
    }
    Context "testing transactional deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $createDatabaseScript
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        }
        It "Should throw an error and create no tables" {
            #Running package
            { $null = Install-DBOPackage $packageName @connParams -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction } | Should throw 'relation "a" already exists'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            # Create table cannot be rolled back in PostgreSQL
            $logTable | Should -Not -BeIn $testResults.name
            'a' | Should -Not -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }

    }
    Context "testing non transactional deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        }
        It "Should throw an error and create one object" {
            #Running package
            { $null = Install-DBOPackage $packageName @connParams -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction  } | Should Throw 'relation "a" already exists'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Name $p1 -Build 2.0
            #versions should not be sorted by default - creating a package where 1.0 is the second build
            $p3 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv3" -Build 2.0 -Force
            $null = Add-DBOBuild -ScriptPath $v2scripts -Name $p3 -Build 1.0
            $outputFile = Join-PSFPath -Normalize "$workFolder\log.txt"
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage $p1 -Build '1.0' @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the "{0}" table' -f $logTable | Should -BeIn $output
            'The "{0}" table has been created' -f $logTable | Should -BeIn $output

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should re-deploy version 1.0 pipelining a string" {
            $testResults = "$workFolder\pv1.zip" | Install-DBOPackage @connParams -Build '1.0' -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using pipelined Get-DBOPackage" {
            $testResults = Get-DBOPackage "$workFolder\pv1.zip" | Install-DBOPackage @connParams -Build '1.0', '2.0' -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
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
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should re-deploy version 2.0 using pipelined FileSystemObject" {
            $testResults = Get-Item "$workFolder\pv1.zip" | Install-DBOPackage @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should deploy in a reversed order: 2.0 before 1.0" {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
            $testResults = Install-DBOPackage "$workFolder\pv3.zip" @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (@((Get-Item $v1scripts).Name | ForEach-Object { "2.0\$_" }), ((Get-Item $v2scripts).Name | ForEach-Object { "1.0\$_" }))
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv3.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $file = Join-PSFPath -Normalize "$workFolder\delay.sql"
            'SELECT pg_sleep(3); SELECT ''Successful!'';' | Set-Content $file
            $null = New-DBOPackage -ScriptPath $file -Name "$workFolder\delay" -Build 1.0 -Force -Configuration @{ ExecutionTimeout = 2 }
        }
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error " {
            { $null = Install-DBOPackage @connParams "$workFolder\delay.zip" -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" } | Should throw 'Exception while reading from stream'
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike "*Unable to read data from the transport connection*"
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike "*Unable to read data from the transport connection*"
            $output | Should BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Unable to read data from the transport connection*'
            $output | Should BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageNamev1 -Build 1.0
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        }
        It "should deploy nothing" {
            $testResults = Install-DBOPackage $packageNamev1 @connParams -Database $newDbName -SchemaVersionTable $logTable -WhatIf
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SourcePath | Should Be (Get-Item $packageNamev1).FullName
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment with CreateDatabase specified" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            $testResults = Install-DBOPackage $p1 -CreateDatabase @connParams -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
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
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment with configuration overrides" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
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
                SqlInstance        = $script:postgresqlInstance
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } | ConvertTo-Json -Depth 2 | Out-File $configFile -Force
            $testResults = Install-DBOPackage -Type PostgreSQL "$workFolder\pv1.zip" -Configuration $configFile -OutputFile "$workFolder\log.txt" -Credential $script:postgresqlCredential
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the "{0}" table' -f $logTable | Should -BeIn $output
            'The "{0}" table has been created' -f $logTable | Should -BeIn $output

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using -Configuration object override" {
            $testResults = Install-DBOPackage -Type PostgreSQL "$workFolder\pv2.zip" -Configuration @{
                SqlInstance        = $script:postgresqlInstance
                Credential         = $script:postgresqlCredential
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
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
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force
            $outputFile = "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv2.zip" @connParams -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
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
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
        }
        AfterEach {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -Database $newDbName -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
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
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "CREATE SCHEMA testschema"
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        }
        It "should deploy version 1.0 into testschema" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -Database $newDbName -Schema testschema
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Configuration.Schema | Should Be 'testschema'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $after = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $after | Where-Object name -eq 'SchemaVersions' | Select-Object -ExpandProperty schema | Should Be 'testschema'
            # postgres deploys to the public schema by default
            'a' | Should -BeIn $after.name
            'b' | Should -BeIn $after.name
            ($after | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing deployment using variables in config" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force -Configuration @{SqlInstance = '#{srv}'; Database = '#{db}'}
            $outputFile = "$workFolder\log.txt"
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type PostgreSQL "$workFolder\pv1.zip" -Credential $script:postgresqlCredential -Variables @{srv = $script:postgresqlInstance; db = $newDbName} -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the "{0}" table' -f $logTable | Should -BeIn $output
            'The "{0}" table has been created' -f $logTable | Should -BeIn $output
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing deployment with custom connection string" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery @connParams -Database postgres -Query ($dropDatabaseScript + $createDatabaseScript)
        }
        It "should deploy version 1.0" {
            $configCS = New-DBOConfig -Configuration @{
                SqlInstance = $script:postgresqlInstance
                Database    = $newDbName
                Credential  = $script:postgresqlCredential
            }
            $connectionString = Get-ConnectionString -Configuration $configCS -Type PostgreSQL
            $testResults = Install-DBOPackage -Type PostgreSQL "$workFolder\pv1.zip" -ConnectionString $connectionString -SqlInstance willBeIgnored -Database IgnoredAsWell -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should BeNullOrEmpty
            $testResults.Database | Should BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" | Select-Object -Skip 1
            $standardOutput | Should -BeIn $output
            'Creating the "{0}" table' -f $logTable | Should -BeIn $output
            'The "{0}" table has been created' -f $logTable | Should -BeIn $output
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
