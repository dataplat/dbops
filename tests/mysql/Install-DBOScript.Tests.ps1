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
    Write-Host "Running MySQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-PSFPath -Normalize $workFolder 'unpacked'
$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\Cleanup.sql"
$tranFailScripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\transactional-failure"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\success\2.sql"
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\mysql-tests\verification\select.sql"
$packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
$cleanupPackageName = Join-PSFPath -Normalize "$testRoot\etc\TempCleanup.zip"
$outFile = Join-PSFPath -Normalize "$testRoot\etc\outLog.txt"
$newDbName = "test_dbops_InstallDBOSqlScript"
$dropDatabaseScript = 'DROP DATABASE IF EXISTS `{0}`' -f $newDbName
$createDatabaseScript = 'CREATE DATABASE IF NOT EXISTS `{0}`' -f $newDbName
$connParams = @{
    Type = "MySQL"
    SqlInstance = $script:mysqlInstance
    Credential = $script:mysqlCredential
    Silent = $true
}

Describe "Install-DBOScript MySQL integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = Invoke-DBOQuery @connParams -Database mysql -Query $dropDatabaseScript, $createDatabaseScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @connParams -Database mysql -Query $dropDatabaseScript
    }
    Context "testing regular deployment with CreateDatabase specified" {
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            # drop the database before installing the package
            $null = Invoke-DBOQuery @connParams -Database mysql -Query $dropDatabaseScript
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -CreateDatabase  -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt"
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
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
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
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
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            try {
                $null = Install-DBOScript -Absolute @connParams -Path $tranFailScripts -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            # Create table cannot be rolled back in MySQL
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOScript -Absolute @connParams -Path $tranFailScripts -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should Be "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -Database $newDbName -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name

            #Validating schema version table
            $svResults = Invoke-DBOQuery @connParams -Database $newDbName -Query "SELECT * FROM $logTable"
            $svResults.Checksum | Should -Not -BeNullOrEmpty
            $svResults.ExecutionTime | Should -BeGreaterOrEqual 0
            if ($script:mysqlCredential) {
                $svResults.AppliedBy | Should -Be $script:mysqlCredential.UserName
            }
            else {
                $svResults.AppliedBy | Should -Not -BeNullOrEmpty
            }
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v2scripts -Database $newDbName -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v2scripts, $v1scripts -Database $newDbName -SchemaVersionTable $logTable
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts, $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be @($v2scripts, $v1scripts)
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should BeIn $testResults.name
            'd' | Should BeIn $testResults.name
            #Verifying order
            $r1 = Invoke-DBOQuery @connParams -Database $newDbName -Query "SELECT scriptname FROM $logtable ORDER BY schemaversionid"
            $r1.scriptname | Should Be (Get-Item $v2scripts, $v1scripts).FullName
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $file = "$workFolder\delay.sql"
            "DO SLEEP(5); SELECT 'Successful!'" | Out-File $file
            $timeoutError = if ($PSVersionTable.PSVersion.Major -ge 6) { 'Fatal error encountered during command execution' } else { 'Timeout expired.' }
        }
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "should throw timeout error" {
            try {
                $null = Install-DBOScript -Absolute @connParams -ScriptPath "$workFolder\delay.sql" -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 2
            }
            catch {
                $testResults = $_
            }
            $testResults | Should Not Be $null
            $testResults.Exception.Message | Should BeLike "*$timeoutError*"
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should BeLike "*$timeoutError*"
            $output | Should Not BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath "$workFolder\delay.sql" -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 6
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should Be 'MySQL'
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
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath "$workFolder\delay.sql" -Database $newDbName -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 0
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should Not BeLike "*$timeoutError*"
            $output | Should BeLike '*Successful!*'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -Database $newDbName -SchemaVersionTable $logTable -WhatIf
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1scripts
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should BeIn $testResults.DeploymentLog
            "$v1scripts would have been executed - WhatIf mode." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'MySQL'
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
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v2scripts -Database $newDbName
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v2scripts
            $testResults.ConnectionType | Should Be 'MySQL'
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
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        AfterEach {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -Query "DROP TABLE IF EXISTS SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -Database $newDbName -SchemaVersionTable $null
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should Be $script:mysqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $v1scripts
            $testResults.ConnectionType | Should Be 'MySQL'
            $testResults.Configuration.SchemaVersionTable | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should BeIn $testResults.DeploymentLog
            'Checking whether journal table exists..' | Should Not BeIn $testResults.DeploymentLog

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
    Context "testing deployments to the native DbUp SchemaVersion table" {
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
        }
        It "Should deploy version 1 to an older schemaversion table" {
            # create old SchemaVersion table
            $query = @'
            CREATE TABLE {0}
            (
                `schemaversionid` INT NOT NULL AUTO_INCREMENT,
                `scriptname` VARCHAR(255) NOT NULL,
                `applied` TIMESTAMP NOT NULL,
                PRIMARY KEY (`schemaversionid`)
            )
'@ -f $logtable
            $null = Invoke-DBOQuery @connParams -Query $query -Database $newDbName
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable -Database $newDbName
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $v1scripts).Name
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            $schemaTableContents = Invoke-DBOQuery @connParams -Database $newDbName -Query "SELECT * FROM $logTable" -As DataTable
            $schemaTableContents.Columns.ColumnName | Should -Be @("schemaversionid", "scriptname", "applied")
            $schemaTableContents.Rows[0].ScriptName | Should -Be (Get-Item $v1scripts).Name
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $cleanupScript
            $null = Install-DBOScript -Absolute @connParams -ScriptPath $v1scripts -Database $newDbName -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            try {
                $testResults = $null
                $testResults = Install-DBOScript -Absolute @connParams -Path $tranFailScripts -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "Table 'a' already exists"
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOScript -Absolute @connParams -Path $tranFailScripts -Database $newDbName -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
                $testResults = Install-DBOScript -Absolute @connParams -ScriptPath $v2scripts -Database $newDbName -SchemaVersionTable $logTable
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should Be $null
            $errorObject | Should Not BeNullOrEmpty
            $errorObject.Exception.Message | Should Be "Table 'a' already exists"
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -Database $newDbName -InputFile $verificationScript
            'a' | Should BeIn $testResults.name
            'b' | Should BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
