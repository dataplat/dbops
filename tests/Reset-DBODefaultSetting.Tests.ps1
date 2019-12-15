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
        Unregister-PSFConfig -Module dbops -Name tc1 -Scope UserDefault
        Unregister-PSFConfig -Module dbops -Name tc2 -Scope UserDefault
        Unregister-PSFConfig -Module dbops -Name tc3 -Scope UserDefault
        Unregister-PSFConfig -Module dbops -Name secret -Scope UserDefault
        try {
            Unregister-PSFConfig -Module dbops -Name tc3 -Scope SystemDefault
        }
        catch {
            $_.Exception.Message | Should BeLike '*access*'
        }
    }
    Context "Resetting various configs" {
        BeforeEach {
            Set-PSFConfig -FullName dbops.tc1 -Value 2
            Set-PSFConfig -FullName dbops.tc2 -Value 'string2'
            Set-PSFConfig -FullName dbops.tc3 -Value 'another2'
            Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
            Get-PSFConfig -FullName dbops.tc1 | Register-PSFConfig -Scope UserDefault
            Get-PSFConfig -FullName dbops.tc2 | Register-PSFConfig -Scope UserDefault
            Get-PSFConfig -FullName dbops.tc3 | Register-PSFConfig -Scope UserDefault
            Get-PSFConfig -FullName dbops.secret | Register-PSFConfig -Scope UserDefault
        }
        It "resets one config" {
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            $testResult = Reset-DBODefaultSetting -Name tc1
            $testResult | Should -BeNullOrEmpty
            Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            $scriptBlock = {
                Import-Module PSFramework, Pester
                Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
                Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
            }
            $job = Start-Job -ScriptBlock $scriptBlock
            $job | Wait-Job | Receive-Job
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
            $scriptBlock = {
                Import-Module PSFramework, Pester
                Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
                Set-PSFConfig -FullName dbops.tc2 -Value 'string' -Initialize
                Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
                Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
            }
            $job = Start-Job -ScriptBlock $scriptBlock
            $job | Wait-Job | Receive-Job
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
            $scriptBlock = {
                Import-Module PSFramework, Pester
                Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
                Set-PSFConfig -FullName dbops.tc2 -Value 'string' -Initialize
                Set-PSFConfig -FullName dbops.tc3 -Value 'another' -Initialize
                Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force) -Initialize
                Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 1
                Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
                Get-PSFConfigValue -FullName dbops.tc3 | Should -Be 'another'
                $testResult = Get-PSFConfigValue -FullName dbops.secret
                $cred = [pscredential]::new('test', $testResult)
                $cred.GetNetworkCredential().Password | Should Be 'foo'
            }
            $job = Start-Job -ScriptBlock $scriptBlock
            $job | Wait-Job | Receive-Job
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