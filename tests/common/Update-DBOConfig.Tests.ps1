Describe "Update-DBOConfig tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
        $encryptedString = $securePassword | ConvertTo-EncryptedString 3>$null
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force -ConfigurationFile $fullConfig
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "Updating single config item (config/value pairs)" {
        It "updates config item with new value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value 'MyNewApplication'
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be 'MyNewApplication'
        }
        It "updates config item with null value" {
            Update-DBOConfig -Path $packageName -ConfigName ApplicationName -Value $null
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be $null
        }
        It "should throw when config item is not specified" {
            { Update-DBOConfig -Path $packageName -ConfigName $null -Value '123' } | Should -Throw
        }
        It "should throw when config item does not exist" {
            { Update-DBOConfig -Path $packageName -ConfigName NonexistingItem -Value '123' } | Should -Throw
        }
    }
    Context "Updating config items using hashtable (values)" {
        It "updates config items with new values" {
            Update-DBOConfig -Path $packageName -Configuration @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb' }
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be 'MyHashApplication'
            $testResults.Database | Should -Be 'MyNewDb'
        }
        It "updates config items with a null value" {
            Update-DBOConfig -Path $packageName -Configuration @{ApplicationName = $null; Database = $null }
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be $null
            $testResults.Database | Should -Be $null
        }
        It "should throw when config item is not specified" {
            { Update-DBOConfig -Path $packageName -Configuration $null } | Should -Throw
        }
        It "should throw when config item does not exist" {
            { Update-DBOConfig -Path $packageName -Configuration @{NonexistingItem = '123' } } | Should -Throw
        }
    }
    Context "Updating config items using DBOpsConfig and a pipeline" {
        It "updates config items with new values" {
            $config = New-DBOConfig -Configuration @{ApplicationName = 'MyHashApplication'; Database = 'MyNewDb' }
            Get-DBOPackage $packageName | Update-DBOConfig -Configuration $config
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be 'MyHashApplication'
            $testResults.Database | Should -Be 'MyNewDb'
        }
        It "updates config items with a null value" {
            $config = New-DBOConfig -Configuration @{ApplicationName = $null; Database = $null }
            $packageName | Update-DBOConfig -Configuration $config
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be $null
            $testResults.Database | Should -Be $null
        }
    }
    Context "Updating config items using a file template" {
        It "updates config items with an empty config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile "$etcFolder\empty_config.json"
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be $null
            $testResults.SqlInstance | Should -Be $null
            $testResults.Database | Should -Be $null
            $testResults.DeploymentMethod | Should -Be $null
            $testResults.ConnectionTimeout | Should -Be $null
            $testResults.Encrypt | Should -Be $null
            $testResults.Credential | Should -Be $null
            $testResults.Username | Should -Be $null
            $testResults.Password | Should -Be $null
            $testResults.SchemaVersionTable | Should -Be $null
            $testResults.Silent | Should -Be $null
            $testResults.Variables.foo | Should -Be 'bar'
            $testResults.Variables.boo | Should -Be 'far'
            $testResults.Schema | Should -Be $null
        }
        It "updates config items with a proper config file" {
            Update-DBOConfig -Path $packageName -ConfigurationFile $fullConfig
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.ApplicationName | Should -Be "MyTestApp"
            $testResults.SqlInstance | Should -Be "TestServer"
            $testResults.Database | Should -Be "MyTestDB"
            $testResults.DeploymentMethod | Should -Be "SingleTransaction"
            $testResults.ConnectionTimeout | Should -Be 40
            $testResults.Encrypt | Should -Be $null
            $testResults.Credential.UserName | Should -Be "CredentialUser"
            $testResults.Credential.GetNetworkCredential().Password | Should -Be "TestPassword"
            $testResults.Username | Should -Be "TestUser"
            [PSCredential]::new('test', $testResults.Password).GetNetworkCredential().Password | Should -Be "TestPassword"
            $testResults.SchemaVersionTable | Should -Be "test.Table"
            $testResults.Silent | Should -Be $true
            $testResults.Variables.foo | Should -Be 'bar'
            $testResults.Variables.boo | Should -Be 'far'
            $testResults.Schema | Should -Be 'testschema'
        }
        It "should throw when config file is not specified" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile $null } | Should -Throw
        }
        It "should throw when config items are wrong in the file" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile "$etcFolder\wrong_config.json" } | Should -Throw
        }
        It "should throw when config file does not exist" {
            { Update-DBOConfig -Path $packageName -ConfigurationFile "$etcFolder\nonexistingconfig.json" } | Should -Throw
        }
    }
    Context "Updating variables" {
        It "updates config variables with new hashtable" {
            Update-DBOConfig -Path $packageName -Variables @{foo = 'bar' }
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.Variables.foo | Should -Be 'bar'
        }
        It "overrides specified config with a value from -Variables" {
            Update-DBOConfig -Path $packageName -Configuration @{Variables = @{ foo = 'bar' } } -Variables @{foo = 'bar2' }
            $testResults = (Get-DBOPackage -Path $packageName).Configuration
            $testResults.Variables.foo | Should -Be 'bar2'
        }
    }
}
