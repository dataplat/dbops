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

Describe "New-DBOConfig tests" -Tag $commandName, UnitTests {
    It "Should throw when config is not a known type" {
        { New-DBOConfig -Configuration 'asdqweqsdfwer' } | Should throw
    }

    It "Should return a default config by default" {
        $testResult = New-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }

    It "Should override properties in an empty config" {
        $testResult = New-DBOConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3}
        $testResult.ApplicationName | Should Be 'MyNewApp'
        $testResult.SqlInstance | Should Be 'localhost'
        $testResult.Database | Should Be $null
        $testResult.DeploymentMethod | Should Be 'NoTransaction'
        $testResult.ConnectionTimeout | Should Be 3
        $testResult.Encrypt | Should Be $false
        $testResult.Credential | Should Be $null
        $testResult.Username | Should Be $null
        $testResult.Password | Should Be $null
        $testResult.SchemaVersionTable | Should Be 'SchemaVersions'
        $testResult.Silent | Should Be $false
        $testResult.Variables | Should Be $null
        $testResult.CreateDatabase | Should Be $false
    }
}
