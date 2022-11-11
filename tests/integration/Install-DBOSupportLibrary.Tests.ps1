BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "Install-DBOSupportLibrary tests" -Tag Integration {
    BeforeAll {
        . "$PSScriptRoot\fixtures.ps1"
        . "$PSScriptRoot\..\..\internal\functions\Get-ExternalLibrary.ps1"
    }
    Context "Testing support for <Type>" -ForEach $types {
        AfterAll {
            Uninstall-Dependencies -Type $Type
        }
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