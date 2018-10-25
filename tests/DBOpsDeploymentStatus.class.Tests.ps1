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

. "$here\..\internal\classes\DBOpsDeploymentStatus.class.ps1"

Describe "DBOpsDeploymentStatus class tests" -Tag $commandName, UnitTests, DBOpsDeploymentStatus, DBOpsClass {
    Context "tests DBOpsConfig constructors" {
        It "Should return an empty status by default" {
            $testResults = [DBOpsDeploymentStatus]::new()
            $testResults.SqlInstance | Should BeNullOrEmpty
            $testResults.Database | Should BeNullOrEmpty
            $testResults.Scripts | Should BeNullOrEmpty
            $testResults.Successful | Should Be $null
            $testResults.SourcePath | Should BeNullOrEmpty
            $testResults.ConnectionType | Should BeNullOrEmpty
            $testResults.Configuration | Should BeNullOrEmpty
            $testResults.Error | Should BeNullOrEmpty
            $testResults.Duration.TotalMilliseconds | Should -Be 0
            $testResults.StartTime | Should BeNullOrEmpty
            $testResults.EndTime | Should BeNullOrEmpty
            $testResults.DeploymentLog | Should BeNullOrEmpty
        }
        It "Should test ToString Method" {
            $testResults = [DBOpsDeploymentStatus]::new()
            $testResults.ToString() | Should Be "Deployment status`: Not deployed. Duration`: Not run yet. Script count`: 0"
            $testResults.Successful = $true
            $testResults.ToString() | Should Be "Deployment status`: Successful. Duration`: Not run yet. Script count`: 0"
            $testResults.StartTime = [datetime]'00:00:01'
            $testResults.EndTime = [datetime]'00:00:02'
            $testResults.ToString() | Should Be "Deployment status`: Successful. Duration`: 00:00:01. Script count`: 0"
            $numScripts = 10
            for ($i = 0; $i -lt $numScripts; $i++ ) {
                $testResults.Scripts += [DbUp.Engine.SqlScript]::new("script$i.sql", "SELECT 1")
            }
            $testResults.ToString() | Should Be "Deployment status`: Successful. Duration`: 00:00:01. Script count`: $numScripts"
            $testResults.Successful = $false
            $testResults.ToString() | Should Be "Deployment status`: Failed. Duration`: 00:00:01. Script count`: $numScripts"

        }
        It "Should test Duration scriptproperty" {
            $testResults = [DBOpsDeploymentStatus]::new()
            $testResults.Duration.TotalMilliseconds | Should -Be 0
            $testResults.StartTime = [datetime]'00:00:01'
            $testResults.Duration.TotalMilliseconds | Should -Be 0
            $testResults.EndTime = [datetime]'00:00:02'
            $testResults.Duration.TotalMilliseconds | Should -Be 1000
            $testResults.EndTime = $null
            $testResults.Duration.TotalMilliseconds | Should -Be 0
        }
    }
}