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



$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'

$packageName = Join-Path $workFolder 'TempDeployment.zip'
$v1scripts = Join-PSFPath -Normalize "$here\etc\install-tests\success"
$fullConfig = Join-PSFPath -Normalize "$here\etc\tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString

Describe "Update-DBOConfig tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
        $null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile $fullConfig
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
    }
    Context "Updating single config item (config/value pairs)" {
        It "updates config item with new value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value 'MyNewApplication'
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be 'MyNewApplication'
        }
        It "updates config item with null value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value $null
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be $null
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
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be 'MyHashApplication'
            $testResults.Database | Should Be 'MyNewDb'
        }
        It "updates config items with a null value" {
            Update-DBOConfig -Path $packageName -Configuration @{ApplicationName = $null; Database = $null}
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be $null
            $testResults.Database | Should Be $null
        }
        It "should throw when config item is not specified" {
            { Update-DBOConfig -Path $packageName -Configuration $null } | Should throw
        }
        It "should throw when config item does not exist" {
            { Update-DBOConfig -Path $packageName -Configuration @{NonexistingItem = '123' } } | Should throw
        }
    }
    Context "Updating config items using DBOpsConfig and a pipeline" {
        It "updates config items with new values" {
            $config = New-DBOConfig -Configuration @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb'}
            Get-DBOPackage $packageName | Update-DBOConfig -Configuration $config
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be 'MyHashApplication'
            $testResults.Database | Should Be 'MyNewDb'
        }
        It "updates config items with a null value" {
            $config = New-DBOConfig -Configuration @{ApplicationName = $null; Database = $null}
            $packageName | Update-DBOConfig -Configuration $config
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be $null
            $testResults.Database | Should Be $null
        }
    }
    Context "Updating config items using a file template" {
        It "updates config items with an empty config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile "$here\etc\empty_config.json"
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be $null
            $testResults.SqlInstance | Should Be $null
            $testResults.Database | Should Be $null
            $testResults.DeploymentMethod | Should Be $null
            $testResults.ConnectionTimeout | Should Be $null
            $testResults.Encrypt | Should Be $null
            $testResults.Credential | Should Be $null
            $testResults.Username | Should Be $null
            $testResults.Password | Should Be $null
            $testResults.SchemaVersionTable | Should Be $null
            $testResults.Silent | Should Be $null
            $testResults.Variables | Should Be $null
            $testResults.Schema | Should Be $null
        }
        It "updates config items with a proper config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile $fullConfig
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should Be "MyTestApp"
            $testResults.SqlInstance | Should Be "TestServer"
            $testResults.Database | Should Be "MyTestDB"
            $testResults.DeploymentMethod | Should Be "SingleTransaction"
            $testResults.ConnectionTimeout | Should Be 40
            $testResults.Encrypt | Should Be $null
            $testResults.Credential.UserName | Should Be "CredentialUser"
            $testResults.Credential.GetNetworkCredential().Password | Should Be "TestPassword"
            $testResults.Username | Should Be "TestUser"
            [PSCredential]::new('test', $testResults.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $testResults.SchemaVersionTable | Should Be "test.Table"
            $testResults.Silent | Should Be $true
            $testResults.Variables | Should Be $null
            $testResults.Schema | Should Be 'testschema'
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
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.Variables.foo | Should Be 'bar'
        }
        It "overrides specified config with a value from -Variables" {
            Update-DBOConfig -Path $packageName -Configuration @{Variables = @{ foo = 'bar'}} -Variables @{foo = 'bar2'}
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.Variables.foo | Should Be 'bar2'
        }
    }
}
