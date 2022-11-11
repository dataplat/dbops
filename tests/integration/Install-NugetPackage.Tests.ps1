BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "Install-NugetPackage tests" -Tag Integration {
    BeforeAll {
        . "$PSScriptRoot\fixtures.ps1"
        . "$PSScriptRoot\..\..\internal\functions\Get-ExternalLibrary.ps1"
        . "$PSScriptRoot\..\..\internal\functions\Install-NugetPackage.ps1"
    }
    Context "Testing support for <Type>" -ForEach $types {
        AfterAll {
            Uninstall-Dependencies -Type $Type
        }
        It "should attempt to install dependencies" {
            $dependencies = Get-ExternalLibrary -Type $Type
            if ($Type -ne 'SqlServer') {
                $dependencies | Measure-Object | Select-Object -ExpandProperty Count | Should -BeGreaterThan 0
            }
            foreach ($package in $dependencies) {
                $packageSplat = @{
                    Name            = $package.Name
                    MinimumVersion  = $package.MinimumVersion
                    MaximumVersion  = $package.MaximumVersion
                    RequiredVersion = $package.RequiredVersion
                }
                #$null = Get-Package @packageSplat -ProviderName nuget -Scope CurrentUser -ErrorAction SilentlyContinue -AllVersions | Uninstall-Package  -Force
                $result = Install-NugetPackage @packageSplat -Scope CurrentUser -Force -Confirm:$false
                $result.Source | Should -Not -BeNullOrEmpty
                $result.Name | Should -Be $package.Name
                $result.Version | Should -Not -BeNullOrEmpty

                $testResult = Get-Package @packageSplat -ProviderName nuget -Scope CurrentUser
                $testResult.Name | Should -Be $result.Name
                $testResult.Version | Should -Not -BeNullOrEmpty
                $testResult.Source | Should -Be $result.Source
                Test-Path (Join-PSFPath (Split-Path $testResult.Source) lib -Normalize) | Should -Be $true
            }
        }
        It "should attempt to install $d libraries for a wrong version" {
            $dependencies = Get-ExternalLibrary -Type $Type
            foreach ($package in $dependencies) {
                { Install-NugetPackage -Name $package.Name -RequiredVersion "0.somerandomversion" -Scope CurrentUser -Force -Confirm:$false } | Should -Throw '*Not Found*'
                { Install-NugetPackage -Name $package.Name -MinimumVersion "10.0" -MaximumVersion "1.0" -Scope CurrentUser -Force -Confirm:$false } | Should -Throw '*Version could not be found*'
            }
        }
    }
}
