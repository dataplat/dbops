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

$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"

$scriptFolder = "$here\etc\install-tests\success"
$v1scripts = Join-Path $scriptFolder '1.sql'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$exportPath = Join-Path $workFolder 'exported.json'

Describe "Export-DBOConfig tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $fromSecureString | Out-File $fullConfig -Force
    }
    AfterAll {
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    It "Should throw when path is not specified" {
        { New-DBOConfig | Export-DBOConfig $null } | Should throw
    }

    It "Should return empty configuration from empty config file" {
        Get-DBOConfig "$here\etc\empty_config.json" | Export-DBOConfig $exportPath
        $result = Get-DBOConfig $exportPath
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

    It "Should export all configurations from the config file" {
        Get-DBOConfig $fullConfig | Export-DBOConfig $exportPath
        $result = Get-DBOConfig $exportPath
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

    It "Should export default configuration from a package object" {
        Get-DBOPackage $packageName | Export-DBOConfig $exportPath
        $result = Get-DBOConfig $exportPath
        foreach ($prop in $result.psobject.properties.name) {
            $result.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should export default configuration from a file passed as a string" {
        $packageName | Export-DBOConfig $exportPath
        $result = Get-DBOConfig $exportPath
        foreach ($prop in $result.psobject.properties.name) {
            $result.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a new config object" {
        New-DBOConfig | Export-DBOConfig $exportPath
        $result = Get-DBOConfig $exportPath
        foreach ($prop in $result.psobject.properties.name) {
            $result.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
}
