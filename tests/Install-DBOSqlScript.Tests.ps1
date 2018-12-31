Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\constants.ps1"

$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$here\etc\install-tests\Cleanup.sql"
$tranFailScripts = Join-PSFPath -Normalize "$here\etc\install-tests\transactional-failure"
$v1scripts = Join-PSFPath -Normalize "$here\etc\install-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$here\etc\install-tests\success\2.sql"
$verificationScript = Join-PSFPath -Normalize "$here\etc\install-tests\verification\select.sql"
$packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
$cleanupPackageName = Join-PSFPath -Normalize "$here\etc\TempCleanup.zip"
$outFile = Join-PSFPath -Normalize "$here\etc\outLog.txt"
$newDbName = "_test_$commandName"

Describe "Install-DBOSqlScript integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
    }
    AfterAll {
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
    }
    Context "testing regular deployment with CreateDatabase specified" {
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts -CreateDatabase -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
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
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeEach {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            try {
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts, $v1scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts, $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be @($v2scripts, $v1scripts)
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
            #Verifying order
            $r1 = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -Query "SELECT ScriptName FROM $logtable ORDER BY Id"
            $r1.ScriptName | Should Be (Get-Item $v2scripts, $v1scripts).FullName
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $file = "$workFolder\delay.sql"
            "WAITFOR DELAY '00:00:03'; PRINT ('Successful!')" | Out-File $file
        }
        BeforeEach {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error" {
            try {
                $null = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 2
            }
            catch {
                $testResults = $_
            }
            $testResults | Should Not Be $null
            $testResults.Exception.Message | Should BeLike '*Timeout Expired.*'
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike '*Timeout Expired*'
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should Be 'SQLServer'
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
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1scripts
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            "$v1scripts would have been executed - WhatIf mode." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
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
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
        }
        AfterEach {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOSqlScript -ScriptPath $v1scripts  -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -Silent -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mssqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog
            'Checking whether journal table exists..' | Should Not BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should Not BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $cleanupScript
            $null = Install-DBOSqlScript -ScriptPath $v1scripts  -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -Silent -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            try {
                $testResults = $null
                $testResults = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "There is already an object named 'a' in the database."
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
                $testResults = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:mssqlInstance -Credential $script:mssqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database $newDbName -InputFile $verificationScript
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
