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

$fullConfig = Join-PSFPath -Normalize "$here\etc\tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString

$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"

$scriptFolder = "$here\etc\install-tests\success"
$v1scripts = Join-PSFPath -Normalize $scriptFolder '1.sql'
$packageName = Join-PSFPath -Normalize $workFolder 'TempDeployment.zip'

Describe "Get-DBOConfig tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    It "Should throw when path does not exist" {
        { Get-DBOConfig 'asdqweqsdfwer' } | Should throw
    }

    It "Should return empty configuration from empty config file" {
        $testResult = Get-DBOConfig "$here\etc\empty_config.json"
        $testResult.ApplicationName | Should Be $null
        $testResult.SqlInstance | Should Be $null
        $testResult.Database | Should Be $null
        $testResult.DeploymentMethod | Should Be $null
        $testResult.ConnectionTimeout | Should Be $null
        $testResult.Encrypt | Should Be $null
        $testResult.Credential | Should Be $null
        $testResult.Username | Should Be $null
        $testResult.Password | Should Be $null
        $testResult.SchemaVersionTable | Should Be $null
        $testResult.Silent | Should Be $null
        $testResult.Variables | Should Be $null
        $testResult.CreateDatabase | Should Be $null
    }

    It "Should return all configurations from the config file" {
        $testResult = Get-DBOConfig $fullConfig
        $testResult.ApplicationName | Should Be "MyTestApp"
        $testResult.SqlInstance | Should Be "TestServer"
        $testResult.Database | Should Be "MyTestDB"
        $testResult.DeploymentMethod | Should Be "SingleTransaction"
        $testResult.ConnectionTimeout | Should Be 40
        $testResult.Encrypt | Should Be $null
        $testResult.Credential.UserName | Should Be "CredentialUser"
        $testResult.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
        $testResult.Username | Should Be "TestUser"
        [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
        $testResult.SchemaVersionTable | Should Be "test.Table"
        $testResult.Silent | Should Be $true
        $testResult.Variables | Should Be $null
        $testResult.Schema | Should Be 'testschema'
        $testResult.CreateDatabase | Should Be $false
    }

    It "Should override configurations of the config file" {
        $testResult = Get-DBOConfig $fullConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3; Database = $null}
        $testResult.ApplicationName | Should Be "MyNewApp"
        $testResult.SqlInstance | Should Be "TestServer"
        $testResult.Database | Should Be $null
        $testResult.DeploymentMethod | Should Be "SingleTransaction"
        $testResult.ConnectionTimeout | Should Be 3
        $testResult.Encrypt | Should Be $null
        $testResult.Credential.UserName | Should Be "CredentialUser"
        $testResult.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
        $testResult.Username | Should Be "TestUser"
        [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should Be "TestPassword"
        $testResult.SchemaVersionTable | Should Be "test.Table"
        $testResult.Silent | Should Be $true
        $testResult.Variables | Should Be $null
        $testResult.Schema | Should Be 'testschema'
        $testResult.CreateDatabase | Should Be $false
    }
    It "Should return default configuration from a package object" {
        $testResult = Get-DBOPackage $packageName | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a file passed as a string" {
        $testResult = $packageName | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a new config object" {
        $testResult = New-DBOConfig | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
}
