Describe "Get-DBODefaultSetting tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        Set-PSFConfig -FullName dbops.tc1 -Value 1
        Set-PSFConfig -FullName dbops.tc2 -Value 'string'
        Set-PSFConfig -FullName dbops.tc3 -Value 'another'
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force)
    }
    Context "Getting various configs" {
        It "returns plain values" {
            Get-DBODefaultSetting -Name tc1 -Value | Should -Be 1
            $testResult = Get-DBODefaultSetting -Name tc1
            $testResult.Value | Should -Be 1
            $testResult.Name | Should -Be 'tc1'
        }
        It "returns wildcarded values" {
            $testResult = Get-DBODefaultSetting -Name tc* | Sort-Object Name
            $testResult.Value | Should -Be @(1, 'string', 'another')
            $testResult.Name | Should -Be @('tc1', 'tc2', 'tc3')
        }
        It "returns values from an array of configs" {
            $testResult = Get-DBODefaultSetting -Name tc2, tc3
            $testResult.Value | Should -Be @('string', 'another')
            $testResult.Name | Should -Be @('tc2', 'tc3')
        }
        It "returns a secret value" {
            $testResult = Get-DBODefaultSetting -Name secret -Value
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should -Be 'foo'
        }
    }
    Context "Negative tests" {
        It "should show warning when multiple names specified with -Value" {
            $null = Get-DBODefaultSetting -Name secret, tc2 -Value -WarningVariable testResult 3>$null
            $testResult | Should -BeLike '*Provide a single item when requesting a value*'
        }
    }
}