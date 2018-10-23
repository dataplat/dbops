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

$fullConfig = "$here\etc\tmp_full_config.json"
$fullConfigSource = "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$fromSecureString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertFrom-SecureString

Describe "Get-DBOConfig tests" -Tag $commandName, UnitTests {
    BeforeAll {
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $fromSecureString | Out-File $fullConfig -Force
    }
    AfterAll {
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
    }
    It "Should throw when path does not exist" {
        { Get-DBOConfig 'asdqweqsdfwer' } | Should throw
    }

    It "Should return empty configuration from empty config file" {
        $result = Get-DBOConfig "$here\etc\empty_config.json"
        $result.ApplicationName | Should Be $null
        $result.SqlInstance | Should Be $null
        $result.Database | Should Be $null
        $result.DeploymentMethod | Should Be $null
        $result.ConnectionTimeout | Should Be $null
        $result.Encrypt | Should Be $null
        $result.Credential | Should Be $null
        $result.Username | Should Be $null
        $result.Password | Should Be $null
        $result.SchemaVersionTable | Should Be $null
        $result.Silent | Should Be $null
        $result.Variables | Should Be $null
        $result.CreateDatabase | Should Be $null
    }

    It "Should return all configurations from the config file" {
        $result = Get-DBOConfig $fullConfig
        $result.ApplicationName | Should Be "MyTestApp"
        $result.SqlInstance | Should Be "TestServer"
        $result.Database | Should Be "MyTestDB"
        $result.DeploymentMethod | Should Be "SingleTransaction"
        $result.ConnectionTimeout | Should Be 40
        $result.Encrypt | Should Be $null
        $result.Credential.UserName | Should Be "CredentialUser"
        $result.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
        $result.Username | Should Be "TestUser"
        [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
        $result.SchemaVersionTable | Should Be "test.Table"
        $result.Silent | Should Be $true
        $result.Variables | Should Be $null
        $result.Schema | Should Be 'testschema'
        $result.CreateDatabase | Should Be $false
    }

    It "Should override configurations of the config file" {
        $result = Get-DBOConfig $fullConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3; Database = $null}
        $result.ApplicationName | Should Be "MyNewApp"
        $result.SqlInstance | Should Be "TestServer"
        $result.Database | Should Be $null
        $result.DeploymentMethod | Should Be "SingleTransaction"
        $result.ConnectionTimeout | Should Be 3
        $result.Encrypt | Should Be $null
        $result.Credential.UserName | Should Be "CredentialUser"
        $result.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
        $result.Username | Should Be "TestUser"
        [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
        $result.SchemaVersionTable | Should Be "test.Table"
        $result.Silent | Should Be $true
        $result.Variables | Should Be $null
        $result.Schema | Should Be 'testschema'
        $result.CreateDatabase | Should Be $false
    }
}
