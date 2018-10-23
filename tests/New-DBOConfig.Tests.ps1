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

Describe "New-DBOConfig tests" -Tag $commandName, UnitTests {
    It "Should throw when config is not a known type" {
        { New-DBOConfig -Configuration 'asdqweqsdfwer' } | Should throw
    }

    It "Should return a default config by default" {
        $result = New-DBOConfig
        foreach ($prop in $result.psobject.properties.name) {
            $result.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }

    It "Should override properties in an empty config" {
        $result = New-DBOConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3}
        $result.ApplicationName | Should Be 'MyNewApp'
        $result.SqlInstance | Should Be 'localhost'
        $result.Database | Should Be $null
        $result.DeploymentMethod | Should Be 'NoTransaction'
        $result.ConnectionTimeout | Should Be 3
        $result.Encrypt | Should Be $false
        $result.Credential | Should Be $null
        $result.Username | Should Be $null
        $result.Password | Should Be $null
        $result.SchemaVersionTable | Should Be 'SchemaVersions'
        $result.Silent | Should Be $false
        $result.Variables | Should Be $null
        $result.CreateDatabase | Should Be $false
    }
}
