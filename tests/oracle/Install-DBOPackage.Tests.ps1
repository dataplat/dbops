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
    Write-Host "Running Oracle $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$oraUserName = 'DBOPSDEPLOYPS1'
$oraPassword = 'S3cur_pAss'
$testCredentials = [pscredential]::new($oraUserName, (ConvertTo-SecureString $oraPassword -AsPlainText -Force))
$connParams = @{
    Type        = 'Oracle'
    SqlInstance = $script:oracleInstance
    Silent      = $true
    Credential  = $testCredentials
}
$adminParams = @{
    Type                = 'Oracle'
    SqlInstance         = $script:oracleInstance
    Silent              = $true
    Credential          = $script:oracleCredential
    ConnectionAttribute = @{
        'DBA Privilege' = 'SYSDBA'
    }
}
$createUserScript = "CREATE USER $oraUserName IDENTIFIED BY $oraPassword/
GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $oraUserName/
GRANT EXECUTE on dbms_lock to $oraUserName"
$dropUserScript = "
    BEGIN
        FOR ln_cur IN (SELECT sid, serial# FROM v`$session WHERE username = '$oraUserName')
        LOOP
            EXECUTE IMMEDIATE ('ALTER SYSTEM KILL SESSION ''' || ln_cur.sid || ',' || ln_cur.serial# || ''' IMMEDIATE');
        END LOOP;
        FOR x IN ( SELECT count(*) cnt
            FROM DUAL
            WHERE EXISTS (SELECT * FROM DBA_USERS WHERE USERNAME = '$oraUserName')
        )
        LOOP
            IF ( x.cnt = 1 ) THEN
                EXECUTE IMMEDIATE 'DROP USER $oraUserName CASCADE';
            END IF;
        END LOOP;
    END;
    /"
$dropObjectsScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\drop.sql"
Describe "Install-DBOPackage Oracle tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        $workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
        $unpackedFolder = Join-Path $workFolder 'unpacked'
        $logTable = "testdeploy"
        $tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\transactional-failure"
        $v1scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\1.sql"
        $v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
        $v2scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\2.sql"
        $v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
        $verificationScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\select.sql"
        $packageName = Join-Path $workFolder "TempDeploymentutty.zip"
        $packageNamev1 = Join-Path $workFolder "TempDeployment_v1.zip"
        $fullConfig = Join-PSFPath -Normalize "$workFolder\tmp_full_config.json"
        $fullConfigSource = Join-PSFPath -Normalize "$testRoot\etc\full_config.json"
        $testPassword = 'TestPassword'
        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
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


        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force

        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
        $null = Invoke-DBOQuery @adminParams -Query $createUserScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @adminParams -Query $dropUserScript
    }
    Context "testing transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should throw an error and create 2 tables" {
            #Running package
            { $null = Install-DBOPackage $packageName @connParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction } | Should throw 'name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            # oracle has implicit commit, sorry folks
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }

    }
    Context "testing non transactional deployment" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $tranFailScripts -Name $packageName -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "Should throw an error and create one object" {
            #Running package
            { $null = Install-DBOPackage $packageName @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction } | Should Throw 'name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Name $p1 -Build 2.0
            #versions should not be sorted by default - creating a package where 1.0 is the second build
            $p3 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv3" -Build 2.0 -Force
            $null = Add-DBOBuild -ScriptPath $v2scripts -Name $p3 -Build 1.0
            $outputFile = Join-PSFPath -Normalize "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOPackage $p1 -Build '1.0' @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should re-deploy version 1.0 pipelining a string" {
            $testResults = "$workFolder\pv1.zip" | Install-DBOPackage @connParams -Build '1.0' -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using pipelined Get-DBOPackage" {
            $testResults = Get-DBOPackage "$workFolder\pv1.zip" | Install-DBOPackage @connParams -Build '1.0', '2.0' -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should re-deploy version 2.0 using pipelined FileSystemObject" {
            $testResults = Get-Item "$workFolder\pv1.zip" | Install-DBOPackage @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should BeNullOrEmpty
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'No new scripts need to be executed - completing.' | Should BeIn $testResults.DeploymentLog

            'No new scripts need to be executed - completing.' | Should BeIn (Get-Content "$workFolder\log.txt" | Select-Object -Skip 1)
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
        It "should deploy in a reversed order: 2.0 before 1.0" {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
            $testResults = Install-DBOPackage "$workFolder\pv3.zip" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (@((Get-Item $v1scripts).Name | ForEach-Object { "2.0\$_" }), ((Get-Item $v2scripts).Name | ForEach-Object { "1.0\$_" }))
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv3.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $content = '
                DECLARE
                    in_time number := 5;
                BEGIN
                    DBMS_LOCK.sleep(in_time);
                END;'
            $file = Join-PSFPath -Normalize "$workFolder\delay.sql"
            $content | Set-Content $file
            $null = New-DBOPackage -ScriptPath $file -Name "$workFolder\delay" -Build 1.0 -Force -Configuration @{ ExecutionTimeout = 2 }
        }
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should throw timeout error " {
            { $null = Install-DBOPackage @connParams "$workFolder\delay.zip" -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" } | Should throw 'user requested cancel of current operation'
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike "*user requested cancel of current operation*"
            $output | Should Not BeLike '*Upgrade successful*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike "*Unable to read data from the transport connection*"
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOPackage "$workFolder\delay.zip" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be '1.0\delay.sql'
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Unable to read data from the transport connection*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageNamev1 -Build 1.0
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy nothing" {
            $testResults = Install-DBOPackage $packageNamev1 @connParams -SchemaVersionTable $logTable -WhatIf
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SourcePath | Should Be (Get-Item $packageNamev1).FullName
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            $v1Journal | ForEach-Object { "$_ would have been executed - WhatIf mode." } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing regular deployment with configuration overrides" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force -ConfigurationFile $fullConfig
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force -Configuration @{
                SqlInstance        = 'nonexistingServer'
                Database           = 'nonexistingDB'
                SchemaVersionTable = 'nonexistingSchema.nonexistinTable'
                DeploymentMethod   = "SingleTransaction"
            }
            $outputFile = "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0 using -Configuration file override" {
            $configFile = "$workFolder\config.custom.json"
            @{
                SqlInstance        = $script:oracleInstance
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } | ConvertTo-Json -Depth 2 | Out-File $configFile -Force
            $testResults = Install-DBOPackage -Type Oracle "$workFolder\pv1.zip" -Configuration $configFile -OutputFile "$workFolder\log.txt" -Credential $testCredentials
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0 using -Configuration object override" {
            $testResults = Install-DBOPackage -Type Oracle "$workFolder\pv2.zip" -Configuration @{
                SqlInstance        = $script:oracleInstance
                Credential         = $testCredentials
                Database           = $newDbName
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            } -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p2 = New-DBOPackage -ScriptPath $v2scripts -Name "$workFolder\pv2" -Build 2.0 -Force
            $outputFile = "$workFolder\log.txt"
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv2.zip" @connParams -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v2Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv2.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        BeforeEach {
            $null = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        AfterEach {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should Not BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    # Disabled for now - see https://github.com/DbUp/DbUp/issues/391
    # Context "testing deployment with defined schema" {
    #     BeforeAll {
    #         $null = Invoke-DBOQuery @adminParams -Query "CREATE USER testschema IDENTIFIED BY $oraPassword"
    #         $null = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
    #     }
    #     AfterAll {
    #         $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
    #         $null = Invoke-DBOQuery @adminParams -Query "DROP USER testschema CASCADE"
    #     }
    #     It "should deploy version 1.0 into testschema" {
    #         $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
    #         $rowsBefore = ($before | Measure-Object).Count
    #         $testResults = Install-DBOPackage "$workFolder\pv1.zip" @connParams -Schema testschema
    #         $testResults.Successful | Should Be $true
    #         $testResults.Scripts.Name | Should Be $v1Journal
    #         $testResults.SqlInstance | Should Be $script:oracleInstance
    #         $testResults.Database | Should -BeNullOrEmpty
    #         $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
    #         $testResults.ConnectionType | Should Be 'Oracle'
    #         $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
    #         $testResults.Configuration.Schema | Should Be 'testschema'
    #         $testResults.Error | Should BeNullOrEmpty
    #         $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
    #         $testResults.StartTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
    #         'Upgrade successful' | Should BeIn $testResults.DeploymentLog

    #         #Verifying objects
    #         $after = Invoke-DBOQuery @connParams -InputFile $verificationScript
    #         $after | Where-Object name -eq 'SchemaVersions' | Select-Object -ExpandProperty schema | Should Be 'testschema'
    #         # postgres deploys to the public schema by default
    #         $after | Where-Object name -eq 'A' | Select-Object -ExpandProperty schema | Should Be 'testschema'
    #         $after | Where-Object name -eq 'B' | Select-Object -ExpandProperty schema | Should Be 'testschema'
    #         ($after | Measure-Object).Count | Should Be ($rowsBefore + 3)
    #     }
    # }
    Context "testing deployment using variables in config" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force -Configuration @{SqlInstance = '#{srv}'; Database = '#{db}' }
            $outputFile = "$workFolder\log.txt"
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOPackage -Type Oracle "$workFolder\pv1.zip" -Credential $testCredentials -Variables @{srv = $script:oracleInstance; db = $newDbName } -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.Database | Should -BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing deployment with custom connection string" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -InputFile $dropObjectsScript
        }
        It "should deploy version 1.0" {
            $configCS = New-DBOConfig -Configuration @{
                SqlInstance = $script:oracleInstance
                Database    = $newDbName
                Credential  = $testCredentials
            }
            $connectionString = Get-ConnectionString -Configuration $configCS -Type Oracle
            $testResults = Install-DBOPackage -Type Oracle "$workFolder\pv1.zip" -ConnectionString $connectionString -SqlInstance willBeIgnored -Database IgnoredAsWell -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
            $testResults.SqlInstance | Should BeNullOrEmpty
            $testResults.Database | Should BeNullOrEmpty
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\pv1.zip")
            $testResults.ConnectionType | Should Be 'Oracle'
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
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
