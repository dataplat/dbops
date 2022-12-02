BeforeDiscovery {
    . "$PSScriptRoot\..\detect_types.ps1"
}

Describe "Test-DBOSupportedSystem tests" -Tag IntegrationTests {
    BeforeAll {
        . "$PSScriptRoot\fixtures.ps1"
        . "$PSScriptRoot\..\..\internal\functions\Get-ExternalLibrary.ps1"
    }
    Context "Testing support for <Type>" -ForEach $types {
        BeforeAll {
            . "$PSScriptRoot\..\install_dependencies.ps1" -Type $Type
        }
        AfterAll {
            Uninstall-Dependencies -Type $Type
        }
        It "should check dependencies are present" {
            $testResult = Test-DBOSupportedSystem -Type $Type 3>$null
            $dependencies = Get-ExternalLibrary -Type $Type
            foreach ($package in $dependencies) {
                $expectedResult = $null -ne (Get-Package $package.Name -MinimumVersion $package.Version -ProviderName nuget)
                $testResult | Should -Be $expectedResult
            }
        }
    }
}