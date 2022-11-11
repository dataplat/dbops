Describe "Set-DBODefaultSetting tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName


        $userScope = switch ($isWindows) {
            $false { 'FileUserLocal' }
            default { 'UserDefault' }
        }

        $systemScope = switch ($isWindows) {
            $false { 'FileUserShared' }
            default { 'SystemDefault' }
        }

        Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
        Set-PSFConfig -FullName dbops.tc2 -Value 'string' -Initialize
        Set-PSFConfig -FullName dbops.tc3 -Value 'another' -Initialize
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force) -Initialize
    }
    AfterAll {
        Unregister-PSFConfig -Module dbops -Name tc1 -Scope $userScope
        Unregister-PSFConfig -Module dbops -Name tc2 -Scope $userScope
        Unregister-PSFConfig -Module dbops -Name tc3 -Scope $userScope
        Unregister-PSFConfig -Module dbops -Name secret -Scope $userScope
        try {
            Unregister-PSFConfig -Module dbops -Name tc3 -Scope $systemScope
        }
        catch {
            $_.Exception.Message | Should -BeLike '*access*'
        }
    }
    Context "Setting various configs" {
        It "sets plain value" {
            $testResult = Set-DBODefaultSetting -Name tc1 -Value 2
            $testResult | Should -Not -BeNullOrEmpty
            $testResult.Value | Should -Be 2
            $testResult.Name | Should -Be 'tc1'
            Set-NewScopeInitConfigValue -Name tc1 -Value 1 | Should -Be 2
        }
        It "sets temporary value" {
            $testResult = Set-DBODefaultSetting -Name tc2 -Value 2 -Temporary
            $testResult | Should -Not -BeNullOrEmpty
            $testResult.Value | Should -Be 2
            $testResult.Name | Should -Be 'tc2'
            Set-NewScopeInitConfigValue -Name tc2 -Value 'string' | Should -Be 'string'
        }
        It "sets a AllUsers-scoped value" {
            try {
                $testResult = Set-DBODefaultSetting -Name tc3 -Value 3 -Scope AllUsers
                $testResult | Should -Not -BeNullOrEmpty
                $testResult.Value | Should -Be 3
                $testResult.Name | Should -Be 'tc3'
                Set-NewScopeInitConfigValue -Name tc3 -Value 'another' | Should -Be 3
            }
            catch {
                $_.Exception.Message | Should -BeLike '*access*'
            }
        }
        It "sets a secret value" {
            . "$PSScriptRoot\..\..\internal\functions\Test-Windows.ps1"
            # encryption on Linux does not work in Register-PSFConfig just yet
            if (Test-Windows -Not) {
                Mock -CommandName Register-PSFConfig -MockWith { } -ModuleName dbops
            }
            $testResult = Set-DBODefaultSetting -Name secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
            $testResult | Should -Not -BeNullOrEmpty
            $cred = [pscredential]::new('test', $testResult.Value)
            $cred.GetNetworkCredential().Password | Should -Be 'bar'
            if (Test-Windows -Not) {
                Assert-MockCalled -CommandName Register-PSFConfig -Exactly 1 -ModuleName dbops -Scope It
            }
        }
    }
    Context "Negative tests" {
        It "should throw when setting does not exist" {
            {
                Set-DBODefaultSetting -Name nonexistent -Value 4
            } | Should -Throw '*Setting named nonexistent does not exist.*'
        }
    }
}