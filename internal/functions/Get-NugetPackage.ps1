function Get-NugetPackage {
    # internal function to extract package details from the package storage based on package definition from Get-ExternalLibrary
    Param (
        [object]$Package
    )
    $packageSplat = @{
        Name            = $package.Name
        MinimumVersion  = $package.MinimumVersion
        MaximumVersion  = $package.MaximumVersion
        RequiredVersion = $package.RequiredVersion
    }
    Get-Package @packageSplat -ProviderName nuget -ErrorAction SilentlyContinue
}