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

Describe "Install-DBOSupportLibrary tests" -Tag $commandName, UnitTests {
    Context "Testing support for different RDBMS" {
        $dependencies = Get-ExternalLibrary
        foreach ($d in ($dependencies | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name)) {
            It "should attempt to install $d libraries" {
                Install-DBOSupportLibrary -Type $d -Scope CurrentUser -Force -Confirm:$false
                foreach ($package in $dependencies.$d) {
                    $testResult = Get-NugetPackage $package
                    $testResult.Name | Should Be $package.Name
                    foreach ($dPath in $package.Path) {
                        $dllPath = Join-PSFPath -Normalize (Split-Path $testResult.Source -Parent) $dPath
                        Test-Path $dllPath | Should -Be $true
                    }
                }
            }
        }
    }
}