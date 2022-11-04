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

Describe "Get-DBODefaultSetting tests" -Tag $commandName, UnitTests {
    BeforeAll {
        Set-PSFConfig -FullName dbops.tc1 -Value 1
        Set-PSFConfig -FullName dbops.tc2 -Value 'string'
        Set-PSFConfig -FullName dbops.tc3 -Value 'another'
        Set-PSFConfig -FullName dbops.secret -Value (ConvertTo-SecureString -AsPlainText 'foo' -Force)
    }
    AfterAll {
        
    }
    Context "Getting various configs" {
        It "returns plain values" {
            Get-DBODefaultSetting -Name tc1 -Value | Should Be 1
            $testResult = Get-DBODefaultSetting -Name tc1
            $testResult.Value | Should Be 1
            $testResult.Name | Should Be 'tc1'
        }
        It "returns wildcarded values" {
            $testResult = Get-DBODefaultSetting -Name tc* | Sort-Object Name
            $testResult.Value | Should Be @(1, 'string', 'another')
            $testResult.Name | Should Be @('tc1', 'tc2', 'tc3')
        }
        It "returns values from an array of configs" {
            $testResult = Get-DBODefaultSetting -Name tc2, tc3
            $testResult.Value | Should Be @('string', 'another')
            $testResult.Name | Should Be @('tc2', 'tc3')
        }
        It "returns a secret value" {
            $testResult = Get-DBODefaultSetting -Name secret -Value
            $cred = [pscredential]::new('test',$testResult)
            $cred.GetNetworkCredential().Password | Should Be 'foo'
        }
    }
    Context "Negative tests" {
        It "should show warning when multiple names specified with -Value" {
            $null = Get-DBODefaultSetting -Name secret, tc2 -Value -WarningVariable testResult 3>$null
            $testResult | Should BeLike '*Provide a single item when requesting a value*'
        }
    }
}