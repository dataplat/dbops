Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

. "$here\constants.ps1"
. "$here\etc\Invoke-SqlCmd2.ps1"

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$cleanupScript = "$here\etc\install-tests\Cleanup.sql"
$tranFailScripts = "$here\etc\install-tests\transactional-failure"
$v1scripts = "$here\etc\install-tests\success\1.sql"
$v2scripts = "$here\etc\install-tests\success\2.sql"
$verificationScript = "$here\etc\install-tests\verification\select.sql"
$packageFileName = Join-Path $workFolder ".\dbops.package.json"
$cleanupPackageName = "$here\etc\TempCleanup.zip"
$outFile = "$here\etc\outLog.txt"
$newDbName = "_test_$commandName"

Describe "Install-DBOSqlScript integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database master -Query $dropDatabaseScript
    }
    AfterAll {
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database master -Query $dropDatabaseScript
    }
    Context "testing regular deployment with CreateDatabase specified" {
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            $results = Install-DBOSqlScript -ScriptPath $v1scripts -CreateDatabase -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v1scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Configuration.CreateDatabase | Should Be $true
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog
            "Created database $newDbName" | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
            ($results | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeEach {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            try {
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction -Silent
            }
            catch {
                $results = $_
            }
            $results.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
            }
            catch {
                $results = $_
            }
            $results.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $results = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v1scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
        It "should deploy version 2.0" {
            $results = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v2scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should BeIn $results.name
            'd' | Should BeIn $results.name
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy 2.sql before 1.sql" {
            $results = Install-DBOSqlScript -ScriptPath $v2scripts, $v1scripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v2scripts, $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be @($v2scripts, $v1scripts)
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should BeIn $results.name
            'd' | Should BeIn $results.name
            #Verifying order
            $r1 = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "SELECT ScriptName FROM $logtable ORDER BY Id"
            $r1.ScriptName | Should Be (Get-Item $v2scripts, $v1scripts).FullName
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $file = "$workFolder\delay.sql"
            "WAITFOR DELAY '00:00:03'; PRINT ('Successful!')" | Out-File $file
        }
        BeforeEach {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error" {
            try {
                $null = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 2
            }
            catch {
                $results = $_
            }
            $results | Should Not Be $null
            $results.Exception.Message | Should BeLike '*Timeout Expired.*'
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike '*Timeout Expired*'
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $results = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 6
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be "$workFolder\delay.sql"
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be "$workFolder\delay.sql"
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterThan $results.StartTime

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $results = Install-DBOSqlScript -ScriptPath "$workFolder\delay.sql" -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -ExecutionTimeout 0
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be "$workFolder\delay.sql"
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be "$workFolder\delay.sql"
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike '*Timeout Expired*'
            $output | Should BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $results = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $results.Successful | Should Be $true
            $results.Scripts | Should BeNullOrEmpty
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v1scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            "Running in WhatIf mode - no deployment performed." | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $results = Install-DBOSqlScript -ScriptPath $v1scripts -SqlInstance $script:instance1 -Database $newDbName -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v1scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
            ($results | Measure-Object).Count | Should Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $results = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:instance1 -Database $newDbName -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v2scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should BeIn $results.name
            'd' | Should BeIn $results.name
            ($results | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeEach {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        AfterEach {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $results = Install-DBOSqlScript -ScriptPath $v1scripts  -SqlInstance $script:instance1 -Database $newDbName -Silent -SchemaVersionTable $null
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $v1scripts
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            'Upgrade successful' | Should BeIn $results.DeploymentLog
            'Checking whether journal table exists..' | Should Not BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            'SchemaVersions' | Should Not BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
            ($results | Measure-Object).Count | Should Be ($rowsBefore + 2)
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
            $null = Install-DBOSqlScript -ScriptPath $v1scripts  -SqlInstance $script:instance1 -Database $newDbName -Silent -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            try {
                $results = $null
                $results = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
            }
            catch {
                $errorObject = $_
            }
            $results | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "There is already an object named 'a' in the database."
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $results = $null
                $null = Install-DBOSqlScript -Path $tranFailScripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction -Silent
                $results = Install-DBOSqlScript -ScriptPath $v2scripts -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            }
            catch {
                $errorObject = $_
            }
            $results | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "There is already an object named 'a' in the database."
            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
}
