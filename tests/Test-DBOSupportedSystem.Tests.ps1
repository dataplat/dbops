Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    Import-Module "$here\..\dbops.psd1" -Force
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Describe "Test-DBOSupportedSystem tests" -Tag $commandName, UnitTests {
    Context "Testing support for different RDBMS" {
        It "should test SQL Server support" {
            Test-DBOSupportedSystem -Type SQLServer | Should Be $true
        }
        It "should test Oracle support" {
            $expectedResult = [bool](Get-Package Oracle.ManagedDataAccess -MinimumVersion 12.2.1100 -ErrorAction SilentlyContinue)
            $result = Test-DBOSupportedSystem -Type Oracle 3>$null
            $result | Should Be $expectedResult
        }
    }
}