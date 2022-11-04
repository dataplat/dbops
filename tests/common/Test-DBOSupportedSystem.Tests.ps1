Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Describe "Test-DBOSupportedSystem tests" -Tag $commandName, UnitTests {
    Context "Testing support for different RDBMS" {
        # all packages should be already installed by this time in Install-DBOSupportLibrary.Tests.ps1
        $dependencies = Get-ExternalLibrary
        foreach ($d in ($dependencies | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name)) {
            It "should test $d support" {
                $testResult = Test-DBOSupportedSystem -Type $d 3>$null
                foreach ($package in $dependencies.$d) {
                    $expectedResult = $null -ne (Get-Package $package.Name -MinimumVersion $package.Version -ProviderName nuget)
                    $testResult | Should Be $expectedResult
                }
            }
        }
    }
}