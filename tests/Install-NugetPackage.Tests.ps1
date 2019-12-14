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

Describe "Install-NugetPackage tests" -Tag $commandName, UnitTests {
    Context "Testing support for different RDBMS" {
        $dependencies = Get-ExternalLibrary
        foreach ($d in ($dependencies | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name)) {
            It "should attempt to install $d libraries" {
                foreach ($package in $dependencies.$d) {
                    $null = Get-Package $package.Name -RequiredVersion $package.Version -ProviderName nuget -Scope CurrentUser -ErrorAction SilentlyContinue | Uninstall-Package $package.Name -ErrorAction SilentlyContinue -Force
                    $result = Install-NugetPackage -Name $package.Name -RequiredVersion $package.Version -Scope CurrentUser -Force -Confirm:$false
                    $result.Source | Should -Not -BeNullOrEmpty
                    $result.Name | Should -Be $package.Name
                    $result.Version | Should -Be $package.Version

                    $testResult = Get-Package $package.Name -RequiredVersion $package.Version -ProviderName nuget -Scope CurrentUser
                    $testResult.Name | Should Be $result.Name
                    $testResult.Version | Should -Be $result.Version
                    $testResult.Source | Should -Be $result.Source
                }
            }
        }
    }
}