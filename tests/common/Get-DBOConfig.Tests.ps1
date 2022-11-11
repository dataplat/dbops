Describe "Get-DBOConfig tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
        $encryptedString = $securePassword | ConvertTo-EncryptedString 3>$null
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        Remove-Workfolder
    }
    It "Should throw when path does not exist" {
        { Get-DBOConfig 'asdqweqsdfwer' } | Should -Throw
    }

    It "Should return empty configuration from empty config file" {
        $testResult = Get-DBOConfig "$etcFolder\empty_config.json"
        $testResult.ApplicationName | Should -Be $null
        $testResult.SqlInstance | Should -Be $null
        $testResult.Database | Should -Be $null
        $testResult.DeploymentMethod | Should -Be $null
        $testResult.ConnectionTimeout | Should -Be $null
        $testResult.Encrypt | Should -Be $null
        $testResult.Credential | Should -Be $null
        $testResult.Username | Should -Be $null
        $testResult.Password | Should -Be $null
        $testResult.SchemaVersionTable | Should -Be $null
        $testResult.Silent | Should -Be $null
        $testResult.Variables | Should -Be $null
        $testResult.CreateDatabase | Should -Be $null
    }

    It "Should return all configurations from the config file" {
        $testResult = Get-DBOConfig $fullConfig
        $testResult.ApplicationName | Should -Be "MyTestApp"
        $testResult.SqlInstance | Should -Be "TestServer"
        $testResult.Database | Should -Be "MyTestDB"
        $testResult.DeploymentMethod | Should -Be "SingleTransaction"
        $testResult.ConnectionTimeout | Should -Be 40
        $testResult.Encrypt | Should -Be $null
        $testResult.Credential.UserName | Should -Be "CredentialUser"
        $testResult.Credential.GetNetworkCredential().Password | Should -Be "TestPassword"
        $testResult.Username | Should -Be "TestUser"
        [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should -Be "TestPassword"
        $testResult.SchemaVersionTable | Should -Be "test.Table"
        $testResult.Silent | Should -Be $true
        $testResult.Variables.foo | Should -Be 'bar'
        $testResult.Variables.boo | Should -Be 'far'
        $testResult.Schema | Should -Be 'testschema'
        $testResult.CreateDatabase | Should -Be $false
    }

    It "Should override configurations of the config file" {
        $testResult = Get-DBOConfig $fullConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3; Database = $null }
        $testResult.ApplicationName | Should -Be "MyNewApp"
        $testResult.SqlInstance | Should -Be "TestServer"
        $testResult.Database | Should -Be $null
        $testResult.DeploymentMethod | Should -Be "SingleTransaction"
        $testResult.ConnectionTimeout | Should -Be 3
        $testResult.Encrypt | Should -Be $null
        $testResult.Credential.UserName | Should -Be "CredentialUser"
        $testResult.Credential.GetNetworkCredential().Password | Should -Be "TestPassword"
        $testResult.Username | Should -Be "TestUser"
        [PSCredential]::new('test', $testResult.Password).GetNetworkCredential().Password | Should -Be "TestPassword"
        $testResult.SchemaVersionTable | Should -Be "test.Table"
        $testResult.Silent | Should -Be $true
        $testResult.Variables.foo | Should -Be 'bar'
        $testResult.Variables.boo | Should -Be 'far'
        $testResult.Schema | Should -Be 'testschema'
        $testResult.CreateDatabase | Should -Be $false
    }
    It "Should return default configuration from a package object" {
        $testResult = Get-DBOPackage $packageName | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a file passed as a string" {
        $testResult = $packageName | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a new config object" {
        $testResult = New-DBOConfig | Get-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
}
