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
$logTable = "testdeploymenthistory"
$cleanupScript = "$here\etc\install-tests\Cleanup.sql"
$v1scripts = "$here\etc\install-tests\success\1.sql"
$v2scripts = "$here\etc\install-tests\success\2.sql"
$verificationScript = "$here\etc\install-tests\verification\select.sql"

$newDbName = "_test_$commandName"

Describe "Register-DBOPackage integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $dropDatabaseScript = 'IF EXISTS (SELECT * FROM sys.databases WHERE name = ''{0}'') BEGIN ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}]; END' -f $newDbName
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database master -Query $dropDatabaseScript
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database master -Query $dropDatabaseScript
    }
    Context "testing registration with CreateDatabase specified" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $p1 = Add-DBOBuild -ScriptPath $v2scripts -Package $p1 -Build 2.0
        }
        It "should register version 1.0 in a new database using -CreateDatabase switch" {
            $results = Register-DBOPackage $p1 -CreateDatabase -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be ((Get-Item $v1scripts).Name | ForEach-Object {'1.0\' + $_}), ((Get-Item $v2scripts).Name | ForEach-Object {'2.0\' + $_})
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be "$workFolder\pv1.zip"
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Configuration.CreateDatabase | Should Be $true
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            "1.0\$((Get-Item $v1scripts).Name) was registered in table $logtable" | Should BeIn $results.DeploymentLog
            "2.0\$((Get-Item $v2scripts).Name) was registered in table $logtable" | Should BeIn $results.DeploymentLog
            "Created database $newDbName" | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name

            #Verifying SchemaVersions table
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "SELECT * FROM $logTable"
            $results.ScriptName | Should Be "1.0\$((Get-Item $v1scripts).Name)", "2.0\$((Get-Item $v2scripts).Name)"
        }
    }
    Context "testing registration of scripts" {
        BeforeAll {
            $p2 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv2" -Build 1.0 -Force
            $p2 = Add-DBOBuild -ScriptPath $v2scripts -Package $p2 -Build 2.0
            $outputFile = "$workFolder\log.txt"
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "should register version 1.0 without creating any objects" {
            $before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $results = Register-DBOPackage -Package $p2 -Build 1.0 -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be ((Get-Item $v1scripts).Name | ForEach-Object {'1.0\' + $_})
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be "$workFolder\pv2.zip"
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            "1.0\$((Get-Item $v1scripts).Name) was registered in table $logtable" | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
            ($results | Measure-Object).Count | Should Be ($rowsBefore + 1)

            #Verifying SchemaVersions table
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "SELECT * FROM $logTable"
            $results.ScriptName | Should Be "1.0\$((Get-Item $v1scripts).Name)"
        }
        It "should register version 1.0 + 2.0 without creating any objects" {
            $before = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $rowsBefore = ($before | Measure-Object).Count
            $results = Register-DBOPackage -Package $p2 -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be ((Get-Item $v2scripts).Name | ForEach-Object {'2.0\' + $_})
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be "$workFolder\pv2.zip"
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            "2.0\$((Get-Item $v2scripts).Name) was registered in table $logtable" | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
            ($results | Measure-Object).Count | Should Be $rowsBefore

            #Verifying SchemaVersions table
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -Query "SELECT * FROM $logTable"
            $results.ScriptName | Should Be "1.0\$((Get-Item $v1scripts).Name)", "2.0\$((Get-Item $v2scripts).Name)"
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $p1 = New-DBOPackage -ScriptPath $v1scripts -Name "$workFolder\pv1" -Build 1.0 -Force
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        AfterAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $cleanupScript
        }
        It "should deploy nothing" {
            $results = Register-DBOPackage $p1 -SqlInstance $script:instance1 -Database $newDbName -SchemaVersionTable $logTable -Silent -WhatIf
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $newDbName
            $results.SourcePath | Should Be $p1.FullName
            $results.ConnectionType | Should Be 'SQLServer'
            $results.Configuration.SchemaVersionTable | Should Be $logTable
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -BeGreaterOrEqual 0
            $results.StartTime | Should Not BeNullOrEmpty
            $results.EndTime | Should Not BeNullOrEmpty
            $results.EndTime | Should -BeGreaterOrEqual $results.StartTime
            "Running in WhatIf mode - no registration performed." | Should BeIn $results.DeploymentLog

            #Verifying objects
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $newDbName -InputFile $verificationScript
            $logTable | Should Not BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
}
