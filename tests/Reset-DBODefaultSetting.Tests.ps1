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

Describe "Reset-DBODefaultSetting tests" -Tag $commandName, UnitTests {
    BeforeAll {
        Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
        Set-PSFConfig -FullName dbops.tc2 -Value 'string' -Initialize
        Set-PSFConfig -FullName dbops.tc3 -Value 'another' -Initialize
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force) -Initialize
    }
    AfterAll {
        Unregister-PSFConfig -Module dbops -Name tc1
        Unregister-PSFConfig -Module dbops -Name tc2
        Unregister-PSFConfig -Module dbops -Name tc3 -Scope SystemDefault
        Unregister-PSFConfig -Module dbops -Name secret
    }
    Context "Resetting various configs" {
        BeforeEach {
            Set-PSFConfig -FullName dbops.tc1 -Value 2
            Set-PSFConfig -FullName dbops.tc2 -Value 'string2'
            Set-PSFConfig -FullName dbops.tc3 -Value 'another2'
            Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
        }
        It "resets one config" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            $testResult = Reset-DBODefaultSetting -Name tc1
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
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
        }
        It "resets all configs" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string2'
            Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another2'
            $testResult = Get-PSFConfigValue -FullName dbops.secret
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should Be 'bar'
            $testResult = Reset-DBODefaultSetting -All
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
            Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another'
            $testResult = Get-PSFConfigValue -FullName dbops.secret
            $cred = [pscredential]::new('test', $testResult)
            $cred.GetNetworkCredential().Password | Should Be 'foo'
        }
        It "resets an AllUsers-scoped value" {
            try {
                Register-PSFConfig -FullName dbops.tc3 -Scope SystemDefault
                $testResult = Reset-DBODefaultSetting -Name tc3 -Scope AllUsers
                $testResult | Should -BeNullOrEmpty
                Get-PSFConfigValue -FullName dbops.tc3 | Should Be 'another'
            }
            catch {
                $_.Exception.Message | Should BeLike '*access*'
            }
        }
    }
    Context "Negative tests" {
        It "should throw when setting does not exist" {
            try {
                $null = Reset-DBODefaultSetting -Name nonexistent
            }
            catch { $testResult = $_ }
            $testResult.Exception.Message | Should -Be 'Unable to find setting nonexistent'
        }
    }
}