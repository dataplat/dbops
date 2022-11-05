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
$cleanupScript = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\Cleanup.sql"
$tranFailScripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\transactional-failure"
$v1scripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$v2scripts = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$verificationScript = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\verification\select.sql"
$packageFileName = Join-PSFPath -Normalize $workFolder "dbops.package.json"
$cleanupPackageName = Join-PSFPath -Normalize "$here\etc\TempCleanup.zip"
$outFile = Join-PSFPath -Normalize "$here\etc\outLog.txt"
$newDbName = "_test_$commandName"
$dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
$createDatabaseScript = 'IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN CREATE DATABASE [{0}]; END' -f $newDbName
$connParams = @{
    SqlInstance = $script:mssqlInstance
    Silent      = $true
    Credential  = $script:mssqlCredential
    Database    = $newDbName
}

Describe "Install-DBOScript integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $createDatabaseScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
    }
    Context "testing regular deployment with CreateDatabase specified" {
        It "should deploy version 1.0 to a new database using -CreateDatabase switch" {
            # drop the database before installing the package
            $null = Invoke-DBOQuery -SqlInstance $script:mssqlInstance -Silent -Credential $script:mssqlCredential -Database master -Query $dropDatabaseScript
            $testResults = Install-DBOScript -Absolute -ScriptPath $v1scripts -CreateDatabase @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Schema dbo
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v1scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Configuration.CreateDatabase | Should -Be $true
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog
            "Created database $newDbName" | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should -Be ($rowsBefore + 3)
        }
    }
    Context "testing transactional deployment of scripts" {
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "Should throw an error and not create any objects" {
            #Running package
            try {
                $null = Install-DBOScript -Absolute -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod SingleTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -Not -BeIn $testResults.name
            'a' | Should -Not -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }
    }
    Context "testing non transactional deployment of scripts" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "Should throw an error and create one object" {
            #Running package
            try {
                $null = Install-DBOScript -Absolute -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
            }
            catch {
                $testResults = $_
            }
            $testResults.Exception.Message | Should -Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }
    }
    Context "testing script deployment" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "should deploy version 1.0" {
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $v1scripts).Name
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v1scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name

            #Validating schema version table
            $svResults = Invoke-DBOQuery @connParams -Query "SELECT * FROM $logTable"
            $svResults.Checksum | Should -Not -BeNullOrEmpty
            $svResults.ExecutionTime | Should -BeGreaterOrEqual 0
            if ($script:mssqlCredential) {
                $svResults.AppliedBy | Should -Be $script:mssqlCredential.UserName
            }
            else {
                $svResults.AppliedBy | Should -Not -BeNullOrEmpty
            }
        }
        It "should deploy version 2.0" {
            $testResults = Install-DBOScript -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $v2scripts).Name
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v2scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -BeIn $testResults.name
            'd' | Should -BeIn $testResults.name
        }
    }
    Context "testing deployment order" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "should deploy 2.sql before 1.sql" {
            $testResults = Install-DBOScript -Absolute -ScriptPath $v2scripts, $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Resolve-Path $v2scripts, $v1scripts).Path
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be @($v2scripts, $v1scripts)
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -BeIn $testResults.name
            'd' | Should -BeIn $testResults.name
            #Verifying order
            $r1 = Invoke-DBOQuery @connParams -Query "SELECT ScriptName FROM $logtable ORDER BY Id"
            $r1.ScriptName | Should -Be (Get-Item $v2scripts, $v1scripts).FullName
        }
    }
    Context "testing timeouts" {
        BeforeAll {
            $file = "$workFolder\delay.sql"
            "WAITFOR DELAY '00:00:03'; PRINT ('Successful!')" | Out-File $file
        }
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "should throw timeout error" {
            try {
                $null = Install-DBOScript -Absolute -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 2
            }
            catch {
                $testResults = $_
            }
            $testResults | Should -Not -BeNullOrEmpty
            $testResults.Exception.Message | Should -BeLike '*Timeout Expired.*'
            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should -BeLike '*Timeout Expired*'
            $output | Should -Not -BeLike '*Successful!*'
        }
        It "should successfully run within specified timeout" {
            $testResults = Install-DBOScript -Absolute -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 6
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterThan 3000
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterThan $testResults.StartTime

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should -Not -BeLike '*Timeout Expired*'
            $output | Should -BeLike '*Successful!*'
        }
        It "should successfully run with infinite timeout" {
            $testResults = Install-DBOScript -Absolute -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -ExecutionTimeout 0
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be (Join-PSFPath -Normalize "$workFolder\delay.sql")
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            $output = Get-Content "$workFolder\log.txt" -Raw
            $output | Should -Not -BeLike '*Timeout Expired*'
            $output | Should -BeLike '*Successful!*'
        }
    }
    Context "testing variable replacement" {
        BeforeAll {
            $file = "$workFolder\delay.sql"
            "SELECT '#{var1}'; PRINT ('#{var2}')" | Out-File $file
        }
        It "should return replaced variables" {
            $vars = @{
                var1 = 1337
                var2 = 'Replaced!'
            }
            $testResults = Install-DBOScript -ScriptPath "$workFolder\delay.sql" @connParams -SchemaVersionTable $null -OutputFile "$workFolder\log.txt" -Variables $vars
            $testResults.Successful | Should -Be $true
            "$workFolder\log.txt" | Should -FileContentMatch '1337'
            "$workFolder\log.txt" | Should -FileContentMatch 'Replaced!'
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $testResults = Install-DBOScript -Absolute -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable -WhatIf
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be $v1scripts
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v1scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be $logTable
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "No deployment performed - WhatIf mode." | Should -BeIn $testResults.DeploymentLog
            "$v1scripts would have been executed - WhatIf mode." | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -Not -BeIn $testResults.name
            'a' | Should -Not -BeIn $testResults.name
            'b' | Should -Not -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }
    }
    Context "testing deployment without specifying SchemaVersion table" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-DBOQuery @connParams -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -Absolute -ScriptPath $v1scripts @connParams
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v1scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be 'SchemaVersions'
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should -Be ($rowsBefore + 3)
        }
        It "should deploy version 2.0" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -Absolute -ScriptPath $v2scripts @connParams
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Resolve-Path $v2scripts).Path
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v2scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -Be 'SchemaVersions'
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -BeIn $testResults.name
            'd' | Should -BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should -Be ($rowsBefore + 2)
        }
    }
    Context "testing deployment with no history`: SchemaVersion is null" {
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        AfterEach {
            $null = Invoke-DBOQuery @connParams -Query "IF OBJECT_ID('SchemaVersions') IS NOT NULL DROP TABLE SchemaVersions"
        }
        It "should deploy version 1.0 without creating SchemaVersions" {
            $before = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Install-DBOScript -Absolute -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Resolve-Path $v1scripts).Path
            $testResults.SqlInstance | Should -Be $script:mssqlInstance
            $testResults.Database | Should -Be $newDbName
            $testResults.SourcePath | Should -Be $v1scripts
            $testResults.ConnectionType | Should -Be 'SQLServer'
            $testResults.Configuration.SchemaVersionTable | Should -BeNullOrEmpty
            $testResults.Error | Should -BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -Not -BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            'Upgrade successful' | Should -BeIn $testResults.DeploymentLog
            'Checking whether journal table exists..' | Should -Not -BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'SchemaVersions' | Should -Not -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should -Be ($rowsBefore + 2)
        }
    }
    Context "testing deployments to the native DbUp SchemaVersion table" {
        BeforeEach {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
        }
        It "Should deploy version 1 to an older schemaversion table" {
            # create old SchemaVersion table
            $query = @"
                create table $logTable (
                [Id] int identity(1,1) not null constraint $($logTable)_pk primary key,
                [ScriptName] nvarchar(255) not null,
                [Applied] datetime not null
                )
"@
            $null = Invoke-DBOQuery @connParams -Query $query
            $testResults = Install-DBOScript -ScriptPath $v1scripts @connParams -SchemaVersionTable $logTable
            $testResults.Successful | Should -Be $true
            $testResults.Scripts.Name | Should -Be (Get-Item $v1scripts).Name
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            $logTable | Should -BeIn $testResults.name
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
            $schemaTableContents = Invoke-DBOQuery @connParams -Query "SELECT * FROM $logTable" -As DataTable
            $schemaTableContents.Columns.ColumnName | Should -Be @("Id", "ScriptName", "Applied")
            $schemaTableContents.Rows[0].ScriptName | Should -Be (Get-Item $v1scripts).Name
        }
    }
    Context "deployments with errors should throw terminating errors" {
        BeforeAll {
            $null = Invoke-DBOQuery @connParams -InputFile $cleanupScript
            $null = Install-DBOScript -Absolute -ScriptPath $v1scripts @connParams -SchemaVersionTable $null
        }
        It "Should return terminating error when object exists" {
            #Running package
            try {
                $testResults = $null
                $testResults = Install-DBOScript -Absolute -Path $tranFailScripts -SchemaVersionTable $logTable -DeploymentMethod NoTransaction @connParams
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should -Be $null
            $errorObject | Should -Not -BeNullOrEmpty
            $errorObject.Exception.Message | Should -Be "There is already an object named 'a' in the database."
        }
        It "should not deploy anything after throwing an error" {
            #Running package
            try {
                $testResults = $null
                $null = Install-DBOScript -Absolute -Path $tranFailScripts @connParams -SchemaVersionTable $logTable -DeploymentMethod NoTransaction
                $testResults = Install-DBOScript -Absolute -ScriptPath $v2scripts @connParams -SchemaVersionTable $logTable
            }
            catch {
                $errorObject = $_
            }
            $testResults | Should -Be $null
            $errorObject | Should -Not -BeNullOrEmpty
            $errorObject.Exception.Message | Should -Be "There is already an object named 'a' in the database."
            #Verifying objects
            $testResults = Invoke-DBOQuery @connParams -InputFile $verificationScript
            'a' | Should -BeIn $testResults.name
            'b' | Should -BeIn $testResults.name
            'c' | Should -Not -BeIn $testResults.name
            'd' | Should -Not -BeIn $testResults.name
        }
    }
}
