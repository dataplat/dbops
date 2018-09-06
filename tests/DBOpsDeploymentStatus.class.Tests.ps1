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

. "$here\..\internal\classes\DBOpsDeploymentStatus.class.ps1"

Describe "DBOpsDeploymentStatus class tests" -Tag $commandName, UnitTests, DBOpsDeploymentStatus, DBOpsClass {
    Context "tests DBOpsConfig constructors" {
        It "Should return an empty status by default" {
            $results = [DBOpsDeploymentStatus]::new()
            $results.SqlInstance | Should BeNullOrEmpty
            $results.Database | Should BeNullOrEmpty
            $results.Scripts | Should BeNullOrEmpty
            $results.Successful | Should Be $null
            $results.SourcePath | Should BeNullOrEmpty
            $results.ConnectionType | Should BeNullOrEmpty
            $results.Configuration | Should BeNullOrEmpty
            $results.Error | Should BeNullOrEmpty
            $results.Duration.TotalMilliseconds | Should -Be 0
            $results.StartTime | Should BeNullOrEmpty
            $results.EndTime | Should BeNullOrEmpty
            $results.DeploymentLog | Should BeNullOrEmpty
        }
        It "Should test ToString Method" {
            $results = [DBOpsDeploymentStatus]::new()
            $results.ToString() | Should Be "Deployment status`: Not deployed. Duration`: Not run yet. Script count`: 0"
            $results.Successful = $true
            $results.ToString() | Should Be "Deployment status`: Successful. Duration`: Not run yet. Script count`: 0"
            $results.StartTime = [datetime]'00:00:01'
            $results.EndTime = [datetime]'00:00:02'
            $results.ToString() | Should Be "Deployment status`: Successful. Duration`: 00:00:01. Script count`: 0"
            $numScripts = 10
            for ($i = 0; $i -lt $numScripts; $i++ ) {
                $results.Scripts += [DbUp.Engine.SqlScript]::new("script$i.sql", "SELECT 1")
            }
            $results.ToString() | Should Be "Deployment status`: Successful. Duration`: 00:00:01. Script count`: $numScripts"
            $results.Successful = $false
            $results.ToString() | Should Be "Deployment status`: Failed. Duration`: 00:00:01. Script count`: $numScripts"

        }
        It "Should test Duration scriptproperty" {
            $results = [DBOpsDeploymentStatus]::new()
            $results.Duration.TotalMilliseconds | Should -Be 0
            $results.StartTime = [datetime]'00:00:01'
            $results.Duration.TotalMilliseconds | Should -Be 0
            $results.EndTime = [datetime]'00:00:02'
            $results.Duration.TotalMilliseconds | Should -Be 1000
            $results.EndTime = $null
            $results.Duration.TotalMilliseconds | Should -Be 0
        }
    }
}