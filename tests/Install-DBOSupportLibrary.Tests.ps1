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

Describe "Install-DBOSupportLibrary tests" -Tag $commandName, UnitTests {
    Context "Testing support for different RDBMS" {
        $dependencies = Get-Content (Join-Path "$PSScriptRoot\.." "internal\json\dbops.dependencies.json") -Raw | ConvertFrom-Json
        foreach ($d in ($dependencies | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name)) {
            It "should attempt to install $d support" {
                Install-DBOSupportLibrary -Type $d -Scope CurrentUser -Force
                foreach ($package in $dependencies.$d) {
                    $result = Get-Package $package.Name -MinimumVersion $package.Version
                    $result.Name | Should Be $package.Name
                }
            }
        }
    }
}