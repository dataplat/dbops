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
    Write-Host "Running PostgreSQL $commandName tests" -ForegroundColor Cyan
}

. "$testRoot\constants.ps1"

$workFolder = Join-PSFPath -Normalize "$testRoot\etc" "$commandName.Tests.dbops"
$logTable = "testdeploymenthistory"
$cleanupScript = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\Cleanup.sql"
$v1scripts = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\success\1.sql"
$v1Journal = Get-Item $v1scripts | ForEach-Object { '1.0\' + $_.Name }
$v2scripts = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\success\2.sql"
$v2Journal = Get-Item $v2scripts | ForEach-Object { '2.0\' + $_.Name }
$verificationScript = Join-PSFPath -Normalize "$testRoot\etc\postgresql-tests\verification\select.sql"

$newDbName = "test_dbops_registerdbopackage"
$connParams = @{
    Type        = 'PostgreSQL'
    SqlInstance = $script:postgresqlInstance
    Silent      = $true
    Credential  = $script:postgresqlCredential
}
$dropDatabaseScript = @(
    'SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = ''{0}'' AND pid <> pg_backend_pid()' -f $newDbName
    'DROP DATABASE IF EXISTS {0}' -f $newDbName
)
$createDatabaseScript = 'CREATE DATABASE {0}' -f $newDbName

Describe "Register-DBOPackage PostgreSQL integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
        [Npgsql.NpgsqlConnection]::ClearAllPools()
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $createDatabaseScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            [Npgsql.NpgsqlConnection]::ClearAllPools()
    }
    Context "testing registration with CreateDatabase specified" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Package $p1 -Build 2.0
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            [Npgsql.NpgsqlConnection]::ClearAllPools()
        }
        It "should register version 1.0 in a new database using -CreateDatabase switch" {
            $testResults = Register-DBOPackage -Type PostgreSQL $p1 -CreateDatabase -SqlInstance $script:postgresqlInstance -Credential $script:postgresqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be (@($v1Journal) + @($v2Journal))
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
            $v1Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog
            $v2Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog
            "Created database $newDbName" | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -Query "SELECT * FROM $logTable ORDER BY schemaversionsid"
            $testResults.scriptname | Should Be (@($v1Journal) + @($v2Journal))
        }
    }
    Context "testing registration of scripts" {
        BeforeAll {
            $p2 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv2" -Build 1.0 -Force
            $p2 = Add-DBOBuild -ScriptPath $v2scripts -Package $p2 -Build 2.0
            $outputFile = "$workFolder\log.txt"
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            [Npgsql.NpgsqlConnection]::ClearAllPools()
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $createDatabaseScript
        }
        It "should register version 1.0 without creating any objects" {
            $before = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Register-DBOPackage -Type PostgreSQL -Package $p2 -Build 1.0 -SqlInstance $script:postgresqlInstance -Credential $script:postgresqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
            $testResults.Successful | Should Be $true
            $testResults.Scripts.Name | Should Be $v1Journal
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
            $v1Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be ($rowsBefore + 1)

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -Query "SELECT * FROM $logTable ORDER BY schemaversionsid"
            $testResults.scriptname | Should Be $v1Journal
        }
        It "should register version 1.0 + 2.0 without creating any objects" {
            $before = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $testResults = Register-DBOPackage -Type PostgreSQL -Package $p2 -SqlInstance $script:postgresqlInstance -Credential $script:postgresqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent
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
            $v2Journal | ForEach-Object { "$_ was registered in table $logtable" } | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
            ($testResults | Measure-Object).Count | Should Be $rowsBefore

            #Verifying SchemaVersions table
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -Query "SELECT * FROM $logTable ORDER BY schemaversionsid"
            $testResults.scriptname | Should Be (@($v1Journal) + @($v2Journal))
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $dropDatabaseScript
            [Npgsql.NpgsqlConnection]::ClearAllPools()
            $null = Invoke-DBOQuery @connParams -Database postgres -Query $createDatabaseScript
        }
        It "should deploy nothing" {
            $testResults = Register-DBOPackage -Type PostgreSQL $p1 -SqlInstance $script:postgresqlInstance -Credential $script:postgresqlCredential -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $testResults.SqlInstance | Should Be $script:postgresqlInstance
            $testResults.Database | Should Be $newDbName
            $testResults.SourcePath | Should Be $p1.FullName
            $testResults.ConnectionType | Should Be 'PostgreSQL'
            $testResults.Configuration.SchemaVersionTable | Should Be $logTable
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $testResults.StartTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should Not BeNullOrEmpty
            $testResults.EndTime | Should -BeGreaterOrEqual $testResults.StartTime
            "Running in WhatIf mode - no registration performed." | Should BeIn $testResults.DeploymentLog

            #Verifying objects
            $testResults = Invoke-DBOQuery -Type PostgreSQL -SqlInstance $script:postgresqlInstance -Silent -Credential $script:postgresqlCredential -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $testResults.name
            'a' | Should Not BeIn $testResults.name
            'b' | Should Not BeIn $testResults.name
            'c' | Should Not BeIn $testResults.name
            'd' | Should Not BeIn $testResults.name
        }
    }
}
