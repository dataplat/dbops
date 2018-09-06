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
$v1scripts = "$here\etc\install-tests\success\1.sql"
$verificationScript = "$here\etc\install-tests\verification\select.sql"
$packageName = Join-Path $workFolder 'TempDeployment.zip'

Describe "Invoke-DBODeployment integration tests" -Tag $commandName, IntegrationTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        $packageName = New-DBOPackage -Path $packageName -ScriptPath $v1scripts -Build 1.0 -Force
        $null = Expand-Archive -Path $packageName -DestinationPath $workFolder -Force
    }
    AfterAll {
        $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "testing deployment of extracted package" {
        BeforeEach {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
        }
        It "should deploy with a -Configuration parameter" {
            $deploymentConfig = @{
                SqlInstance        = $script:instance1
                Database           = $script:database1
                SchemaVersionTable = $logTable
                Silent             = $true
                DeploymentMethod   = 'NoTransaction'
            }
            $results = & $workFolder\deploy.ps1 -Configuration $deploymentConfig
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $script:database1
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
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
        It "should deploy with a set of parameters" {
            $results = & $workFolder\deploy.ps1 -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent
            $results.Successful | Should Be $true
            $results.Scripts.Name | Should Be (Resolve-Path $v1scripts).Path
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $script:database1
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
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
            $logTable | Should BeIn $results.name
            'a' | Should BeIn $results.name
            'b' | Should BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
    Context  "$commandName whatif tests" {
        BeforeAll {
            $null = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $cleanupScript
        }
        AfterAll {
        }
        It "should deploy nothing" {
            $results = & $workFolder\deploy.ps1 -SqlInstance $script:instance1 -Database $script:database1 -SchemaVersionTable $logTable -OutputFile "$workFolder\log.txt" -Silent -WhatIf
            $results.Successful | Should Be $true
            $results.Scripts | Should BeNullOrEmpty
            $results.SqlInstance | Should Be $script:instance1
            $results.Database | Should Be $script:database1
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
            $results = Invoke-SqlCmd2 -ServerInstance $script:instance1 -Database $script:database1 -InputFile $verificationScript
            $logTable | Should Not BeIn $results.name
            'a' | Should Not BeIn $results.name
            'b' | Should Not BeIn $results.name
            'c' | Should Not BeIn $results.name
            'd' | Should Not BeIn $results.name
        }
    }
}
