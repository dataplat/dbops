Describe "Export-DBOConfig tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $exportPath = Join-PSFPath -Normalize $workFolder 'exported.json'
        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force
        $encryptedString = $securePassword | ConvertTo-EncryptedString 3>$null
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        Remove-Workfolder
    }
    It "Should throw when path is not specified" {
        { New-DBOConfig | Export-DBOConfig $null } | Should -Throw
    }

    It "Should return empty configuration from empty config file" {
        Get-DBOConfig "$etcFolder\empty_config.json" | Export-DBOConfig $exportPath
        $testResult = Get-DBOConfig $exportPath
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

    It "Should export all configurations from the config file" {
        Get-DBOConfig $fullConfig | Export-DBOConfig $exportPath
        $testResult = Get-DBOConfig $exportPath
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

    It "Should export default configuration from a package object" {
        Get-DBOPackage $packageName | Export-DBOConfig $exportPath
        $testResult = Get-DBOConfig $exportPath
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should export default configuration from a file passed as a string" {
        $packageName | Export-DBOConfig $exportPath
        $testResult = Get-DBOConfig $exportPath
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
    It "Should return default configuration from a new config object" {
        New-DBOConfig | Export-DBOConfig $exportPath
        $testResult = Get-DBOConfig $exportPath
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }
}
