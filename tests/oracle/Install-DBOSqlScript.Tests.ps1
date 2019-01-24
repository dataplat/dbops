Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }
$testRoot = (Get-Item $here\.. ).FullName

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
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
$createUserScript = "CREATE USER $oraUserName IDENTIFIED BY $oraPassword;
  GRANT CONNECT, RESOURCE, CREATE ANY TABLE TO $oraUserName;
  GRANT EXECUTE on dbms_lock to $oraUserName;"
$dropUserScript = "DROP USER $oraUserName CASCADE;"

$workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploy"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\Cleanup.sql"
$tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\transactional-failure"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\success\2.sql"
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\oracle-tests\verification\select.sql"
$packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
$cleanupPackageName = Join-PSFPath -Normalize "$testRoot\etc\TempCleanup.zip"
$outFile = Join-PSFPath -Normalize "$testRoot\etc\outLog.txt"


Describe "Install-DBOSqlScript Oracle integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
        if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
        if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
    }
    Context "testing regular deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOSqlScript @connParams -ScriptPath $v1scripts -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "Should throw an error and not create any objects" {
            #Running package
            { $null = Install-DBOSqlScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction } | Should throw 'name is already used by an existing object'
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
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "Should throw an error and create one object" {
            #Running package
            { $null = Install-DBOSqlScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction } | Should throw 'name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts, $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts, $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be @($v2scripts, $v1scripts)
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
            #Verifying order
            $r1 = Invoke-DBOQuery @connParams -Query "SELECT scriptname FROM $logtable ORDER BY SCHEMAVERSIONID"
            $r1.scriptname | Should Be (Get-Item $v2scripts, $v1scripts).FullName
        }
    }
    # Context "testing timeouts" {
    #     BeforeAll {
    #         $file = "$workFolder\delay.sql"
    #         'SELECT pg_sleep(3); SELECT ''Successful!'';' | Set-Content $file
    #     }
    #     BeforeEach {
    #         $null = Invoke-DBOQuery @adminParams -Query $createUserScript
    #     }
    #     It "should throw timeout error" {
    #         { $null = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:oracleInstance -Credential $script:oracleCredential @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 2 } | Should throw 'Exception while reading from stream'
    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should BeLike "*Unable to read data from the transport connection*"
    #         $output | Should Not BeLike '*Successful!*'
    #     }
    #     It "should successfully run within specified timeout" {
    #         $testResults = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:oracleInstance -Credential $script:oracleCredential @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
    #         $testResults.Successful | Should Be $true
    #         $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.SqlInstance | Should Be $script:oracleInstance
    #         $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.ConnectionType | Should Be 'Oracle'
    #         $testResults.Configuration.SchemaVersionTable | Should Be $logTable
    #         $testResults.Error | Should BeNullOrEmpty
    #         $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
    #         $testResults.StartTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime

    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should Not BeLike '*Unable to read data from the transport connection*'
    #         $output | Should BeLike '*Successful!*'
    #     }
    #     It "should successfully run with infinite timeout" {
    #         $testResults = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:oracleInstance -Credential $script:oracleCredential @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
    #         $testResults.Successful | Should Be $true
    #         $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.SqlInstance | Should Be $script:oracleInstance
    #         $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
    #         $testResults.ConnectionType | Should Be 'Oracle'
    #         $testResults.Configuration.SchemaVersionTable | Should Be $logTable
    #         $testResults.Error | Should BeNullOrEmpty
    #         $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
    #         $testResults.StartTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should Not BeNullOrEmpty
    #         $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
    #         'Upgrade successful' | Should BeIn $testResults.DeploymentLog

    #         $output = Get-Content "$workFolder\log.txt" -Raw
    #         $output | Should Not BeLike "*Unable to read data from the transport connection*"
    #         $output | Should BeLike '*Successful!*'
    #     }
    # }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy nothing" {
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1scripts
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            "$v1scripts would have been executed - WhatIf mode." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts @connParams
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
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
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts @connParams
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v2scripts
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
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
        }
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:oracleInstance
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'Oracle'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog
            'Checking whether journal table exists..' | Should Not BeIn $testResults.DeploymentLog

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
    Context "deployments with errors should throw terminating errors" {
        AfterAll {
            $userExists = Invoke-DBOQuery @adminParams -Query "SELECT USERNAME FROM ALL_USERS WHERE USERNAME = '$oraUserName'" -As SingleValue
            if ($userExists) { $null = Invoke-DBOQuery @adminParams -Query $dropUserScript }
        }
        BeforeAll {
            $null = Invoke-DBOQuery @adminParams -Query $createUserScript
            $null = Install-DBOSqlScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            { $null = Install-DBOSqlScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction } | Should throw 'name is already used by an existing object'
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOSqlScript -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
                $testResults = Install-DBOSqlScript -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should -BeLike '*name is already used by an existing object'
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
