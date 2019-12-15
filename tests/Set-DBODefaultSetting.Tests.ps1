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

$userScope = switch ($isWindows) {
    $false { 'FileUserLocal' }
    default { 'UserDefault' }
}

$systemScope = switch ($isWindows) {
    $false { 'FileUserShared' }
    default { 'SystemDefault' }
}

Describe "Set-DBODefaultSetting tests" -Tag $commandName, UnitTests {
    BeforeAll {
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
            $_.Exception.Message | Should BeLike '*access*'
        }
    }
    Context "Setting various configs" {
        It "sets plain value" {
            $testResult = Set-DBODefaultSetting -Name tc1 -Value 2
            $testResult | Should -Not -BeNullOrEmpty
            $testResult.Value | Should Be 2
            $testResult.Name | Should Be 'tc1'
            $scriptBlock = {
                Import-Module PSFramework, Pester
                Set-PSFConfig -FullName dbops.tc1 -Value 1 -Initialize
                Get-PSFConfigValue -FullName dbops.tc1 | Should -Be 2
            }
            $job = Start-Job -ScriptBlock $scriptBlock
            $job | Wait-Job | Receive-Job
        }
        It "sets temporary value" {
            $testResult = Set-DBODefaultSetting -Name tc2 -Value 2 -Temporary
            $testResult | Should -Not -BeNullOrEmpty
            $testResult.Value | Should Be 2
            $testResult.Name | Should Be 'tc2'
            $scriptBlock = {
                Import-Module PSFramework, Pester
                Set-PSFConfig -FullName dbops.tc2 -Value 'string' -Initialize
                Get-PSFConfigValue -FullName dbops.tc2 | Should -Be 'string'
            }
            $job = Start-Job -ScriptBlock $scriptBlock
            $job | Wait-Job | Receive-Job
        }
        It "sets a AllUsers-scoped value" {
            try {
                $testResult = Set-DBODefaultSetting -Name tc3 -Value 3 -Scope AllUsers
                $testResult | Should -Not -BeNullOrEmpty
                $testResult.Value | Should Be 3
                $testResult.Name | Should Be 'tc3'
                $scriptBlock = {
                    Import-Module PSFramework, Pester
                    Set-PSFConfig -FullName dbops.tc3 -Value 'another' -Initialize
                    Get-PSFConfigValue -FullName dbops.tc3 | Should Be 3
                }
                $job = Start-Job -ScriptBlock $scriptBlock
                $job | Wait-Job | Receive-Job
            }
            catch {
                $_.Exception.Message | Should BeLike '*access*'
            }
        }
        It "sets a secret value" {
            # encryption on Linux does not work in Register-PSFConfig just yet
            if (Test-Windows -Not) {
                Mock -CommandName Register-PSFConfig -MockWith { } -ModuleName dbops
            }
            $testResult = Set-DBODefaultSetting -Name secret -Value (ConvertTo-SecureString -AsPlainText 'bar' -Force)
            $testResult | Should -Not -BeNullOrEmpty
            $cred = [pscredential]::new('test', $testResult.Value)
            $cred.GetNetworkCredential().Password | Should Be 'bar'
            if (Test-Windows -Not) {
                Assert-MockCalled -CommandName Register-PSFConfig -Exactly 1 -ModuleName dbops -Scope It
            }
        }
    }
    Context "Negative tests" {
        It "should throw when setting does not exist" {
            try {
                $null = Set-DBODefaultSetting -Name nonexistent -Value 4
            }
            catch { $testResult = $_ }
            $testResult.Exception.Message | Should BeLike '*Setting named nonexistent does not exist.*'
        }
    }
}