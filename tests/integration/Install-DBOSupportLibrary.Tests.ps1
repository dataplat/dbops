BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "Install-DBOSupportLibrary tests" -Tag Integration {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName
        . "$PSScriptRoot\..\..\internal\functions\Get-ExternalLibrary.ps1"
    }
    Context "Testing support for <Type>" -ForEach $types {
        It "should attempt to install dependencies" {
            $dependencies = Get-ExternalLibrary -Type $Type
            Install-DBOSupportLibrary -Type $Type -Scope CurrentUser -Force -Confirm:$false
            foreach ($package in $dependencies) {
                $packageSplat = @{ Name = $package.Name }
                if ($package.MinimumVersion) { $packageSplat.MinimumVersion = $package.MinimumVersion }
                if ($package.MaximumVersion) { $packageSplat.MaximumVersion = $package.MaximumVersion }
                if ($package.RequiredVersion) { $packageSplat.RequiredVersion = $package.RequiredVersion }
                $testResult = Get-Package @packageSplat -ProviderName nuget -Scope CurrentUser
                $testResult.Name | Should -Be $package.Name
                foreach ($dPath in $package.Path) {
                    $dllPath = Join-PSFPath -Normalize (Split-Path $testResult.Source -Parent) $dPath
                    Test-Path $dllPath | Should -Be $true
                }
            }
        }
    }
}