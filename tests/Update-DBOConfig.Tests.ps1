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



$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$packageName = Join-Path $workFolder 'TempDeployment.zip'
$v1scripts = "$here\etc\install-tests\success"
$fullConfig = "$here\etc\tmp_full_config.json"
$fullConfigSource = "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$fromSecureString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertFrom-SecureString

Describe "Update-DBOConfig tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $fromSecureString | Out-File $fullConfig -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile $fullConfig
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
    }
    Context "Updating single config item (config/value pairs)" {
        It "updates config item with new value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value 'MyNewApplication'
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be 'MyNewApplication'
        }
        It "updates config item with null value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value $null
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be $null
        }
        It "should throw when config item is not specified" {
            { Update-DBOConfig -Path $packageName -ConfigName $null -Value '123' } | Should throw
        }
        It "should throw when config item does not exist" {
            { Update-DBOConfig -Path $packageName -ConfigName NonexistingItem -Value '123' } | Should throw
        }
    }
    Context "Updating config items using hashtable (values)" {
        It "updates config items with new values" {
            Update-DBOConfig -Path $packageName -Configuration @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb'}
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be 'MyHashApplication'
            $results.Database | Should Be 'MyNewDb'
        }
        It "updates config items with a null value" {
            Update-DBOConfig -Path $packageName -Configuration @{ApplicationName = $null; Database = $null}
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be $null
            $results.Database | Should Be $null
        }
        It "should throw when config item is not specified" {
            { Update-DBOConfig -Path $packageName -Configuration $null } | Should throw
        }
        It "should throw when config item does not exist" {
            { Update-DBOConfig -Path $packageName -Configuration @{NonexistingItem = '123' } } | Should throw
        }
    }
    Context "Updating config items using a file template" {
        It "updates config items with an empty config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile "$here\etc\empty_config.json"
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be $null
            $results.SqlInstance | Should Be $null
            $results.Database | Should Be $null
            $results.DeploymentMethod | Should Be $null
            $results.ConnectionTimeout | Should Be $null
            $results.Encrypt | Should Be $null
            $results.Credential | Should Be $null
            $results.Username | Should Be $null
            $results.Password | Should Be $null
            $results.SchemaVersionTable | Should Be $null
            $results.Silent | Should Be $null
            $results.Variables | Should Be $null
            $results.Schema | Should Be $null
        }
        It "updates config items with a proper config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile $fullConfig
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.ApplicationName | Should Be "MyTestApp"
            $results.SqlInstance | Should Be "TestServer"
            $results.Database | Should Be "MyTestDB"
            $results.DeploymentMethod | Should Be "SingleTransaction"
            $results.ConnectionTimeout | Should Be 40
            $results.Encrypt | Should Be $null
            $results.Credential.UserName | Should Be "CredentialUser"
            $results.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
            $results.Username | Should Be "TestUser"
            [PSCredential]::new('test', $results.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $results.SchemaVersionTable | Should Be "test.Table"
            $results.Silent | Should Be $true
            $results.Variables | Should Be $null
            $results.Schema | Should Be 'testschema'
        }
        It "should throw when config file is not specified" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile $null } | Should throw
        }
        It "should throw when config items are wrong in the file" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile "$here\etc\wrong_config.json" } | Should throw
        }
        It "should throw when config file does not exist" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile "$here\etc\nonexistingconfig.json" } | Should throw
        }
    }
    Context "Updating variables" {
        It "updates config variables with new hashtable" {
            Update-DBOConfig -Path $packageName -Variables @{foo='bar'}
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.Variables.foo | Should Be 'bar'
        }
        It "overrides specified config with a value from -Variables" {
            Update-DBOConfig -Path $packageName -Configuration @{Variables = @{ foo = 'bar'}} -Variables @{foo = 'bar2'}
            $results = (Get-DBOPackage -Path $packageName).Configuration
            $results.Variables.foo | Should Be 'bar2'
        }
    }
}
