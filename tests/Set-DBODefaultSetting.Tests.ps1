Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Describe "Set-DBODefaultSetting tests" -Tag $commandName, UnitTests {
    BeforeAll {
        Set-PSFConfig -FullName dbops.tc1 -Value 1
        Set-PSFConfig -FullName dbops.tc2 -Value 'string'
        Set-PSFConfig -FullName dbops.tc3 -Value 'another'
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force)
    }
    AfterAll {
        Unregister-PSFConfig -Module dbops -Name tc1
        Unregister-PSFConfig -Module dbops -Name tc2
        Unregister-PSFConfig -Module dbops -Name tc3
        Unregister-PSFConfig -Module dbops -Name secret
    }
    Context "Setting various configs" {
        It "sets plain value" {
            $result = Set-DBODefaultSetting -Name tc1 -Value 1
            $result.Value | Should Be 1
            $result.Name | Should Be 'tc1'
        }
        It "sets temporary value" {
            $result = Set-DBODefaultSetting -Name tc2 -Value 2 -Temporary
            $result.Value | Should Be 2
            $result.Name | Should Be 'tc2'
        }
        It "sets a AllUsers-scoped value" {
            try {
                $result = Set-DBODefaultSetting -Name tc3 -Value 3 -Scope AllUsers
                $result.Value | Should Be 3
                $result.Name | Should Be 'tc3'
            }
            catch {
                $_.Exception.Message | Should BeLike '*Access to the registry key*'
            }
            }
        It "sets a secret value" {
            $result = Set-DBODefaultSetting -Name secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($result.Value)
            $secret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $secret | Should Be 'bar'
        }
    }
    Context "Negative tests" {
        It "should throw when setting does not exist" {
            try {
                $null = Set-DBODefaultSetting -Name nonexistent -Value 4
            }
            catch { $result = $_ }
            $result.Exception.Message | Should BeLike '*Setting named nonexistent does not exist.*'
        }
    }
}