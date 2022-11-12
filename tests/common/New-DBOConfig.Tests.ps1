Describe "New-DBOConfig tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName
    }
    It "Should throw when config is not a known type" {
        { New-DBOConfig -Configuration 'asdqweqsdfwer' } | Should -Throw
    }

    It "Should return a default config by default" {
        $testResult = New-DBOConfig
        foreach ($prop in $testResult.psobject.properties.name) {
            $testResult.$prop | Should -Be (Get-PSFConfigValue -FullName dbops.$prop)
        }
    }

    It "Should override properties in an empty config" {
        $testResult = New-DBOConfig -Configuration @{ApplicationName = 'MyNewApp'; ConnectionTimeout = 3 }
        $testResult.ApplicationName | Should -Be 'MyNewApp'
        $testResult.SqlInstance | Should -Be 'localhost'
        $testResult.Database | Should -Be $null
        $testResult.DeploymentMethod | Should -Be 'NoTransaction'
        $testResult.ConnectionTimeout | Should -Be 3
        $testResult.Encrypt | Should -Be $false
        $testResult.Credential | Should -Be $null
        $testResult.Username | Should -Be $null
        $testResult.Password | Should -Be $null
        $testResult.SchemaVersionTable | Should -Be 'SchemaVersions'
        $testResult.Silent | Should -Be $false
        $testResult.Variables | Should -Be $null
        $testResult.CreateDatabase | Should -Be $false
    }
}
