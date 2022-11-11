Describe "Reset-DBODefaultSetting tests" -Tag UnitTests {
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
    Context "Resetting various configs" {
        BeforeEach {
            Set-PSFConfig -FullName dbops.tc1 -Value 2
            Set-PSFConfig -FullName dbops.tc2 -Value 'string2'
            Set-PSFConfig -FullName dbops.tc3 -Value 'another2'
            Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
            Get-PSFConfig -FullName dbops.tc1 | Register-PSFConfig -Scope $userScope
            Get-PSFConfig -FullName dbops.tc2 | Register-PSFConfig -Scope $userScope
            Get-PSFConfig -FullName dbops.tc3 | Register-PSFConfig -Scope $userScope
            Get-PSFConfig -FullName dbops.secret | Register-PSFConfig -Scope $userScope
        }
        It "resets one config" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            $testResult = Reset-DBODefaultSetting -Name tc1
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            Set-NewScopeInitConfigValue -Name tc1 -Value 1 | Should -Be 1
        }
        It "resets temporary config" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            $testResult = Reset-DBODefaultSetting -Name tc1 -Temporary
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
        }
        It "resets two configs" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string2'
            $testResult = Reset-DBODefaultSetting -Name tc1, tc2
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
            Set-NewScopeInitConfigValue -Name tc1 -Value 1 | Should -Be 1
            Set-NewScopeInitConfigValue -Name tc2 -Value 'string' | Should -Be 'string'
        }
        It "resets all configs" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string2'
            Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another2'
            $testResult = Get-PSFConfigValue -FullName dbops.secret
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should -Be 'bar'
            $testResult = Reset-DBODefaultSetting -All
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
            Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another'
            $testResult = Get-PSFConfigValue -FullName dbops.secret
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should -Be 'foo'
            Set-NewScopeInitConfigValue -Name tc1 -Value 1 | Should -Be 1
            Set-NewScopeInitConfigValue -Name tc2 -Value 'string' | Should -Be 'string'
            Set-NewScopeInitConfigValue -Name tc2 -Value 'string' | Should -Be 'string'
            $testResult = Set-NewScopeInitConfigValue -Name secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force)
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should -Be 'foo'
        }
        It "resets an AllUsers-scoped value" {
            try {
                Register-PSFConfig -FullName dbops.tc3 -Scope $systemScope
                $testResult = Reset-DBODefaultSetting -Name tc3 -Scope AllUsers
                $testResult | Should -BeNullOrEmpty
                Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another'
            }
            catch {
                $_.Exception.Message | Should -BeLike '*access*'
            }
        }
    }
    Context "Negative tests" {
        It "should throw when setting does not exist" {
            {
                Reset-DBODefaultSetting -Name nonexistent
            } | Should -Throw 'Unable to find setting nonexistent*'
        }
    }
}