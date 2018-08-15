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

Describe "Get-DBODefaultSetting tests" -Tag $commandName, UnitTests {
    BeforeAll {
        Set-PSFConfig -FullName dbops.TestConfig -Value 1
        Set-PSFConfig -FullName dbops.tc2 -Value 'string'
        Set-PSFConfig -FullName dbops.tc3 -Value 'another'
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force)
    }
    AfterAll {
        
    }
    Context "Getting various configs" {
        It "returns plain values" {
            Get-DBODefaultSetting -Name TestConfig -Value | Should Be 1
            $result = Get-DBODefaultSetting -Name TestConfig
            $result.Value | Should Be 1
            $result.Name | Should Be 'TestConfig'
        }
        It "returns wildcarded values" {
            $result = Get-DBODefaultSetting -Name tc* | Sort-Object Name
            $result.Value | Should Be @('string', 'another')
            $result.Name | Should Be @('tc2', 'tc3')
        }
        It "returns values from an array of configs" {
            $result = Get-DBODefaultSetting -Name tc2, tc3
            $result.Value | Should Be @('string', 'another')
            $result.Name | Should Be @('tc2', 'tc3')
        }
        It "returns a secret value" {
            $result = Get-DBODefaultSetting -Name secret -Value
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($result)
            $secret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            $secret | Should Be 'foo'
        }
    }
    Context "Negative tests" {
        It "should show warning when multiple names specified with -Value" {
            $null = Get-DBODefaultSetting -Name secret, tc2 -Value -WarningVariable result 3>$null
            $result | Should BeLike '*Provide a single item when requesting a value*'
        }
    }
}