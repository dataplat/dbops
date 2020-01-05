function Get-NugetPackage {
    # internal function to extract package details from the package storage based on package definition from Get-ExternalLibrary
    Param (
        [object]$Package
    )
    $packageSplat = @{ Name = $package.Name }
    if ($package.MinimumVersion) { $packageSplat.MinimumVersion = $package.MinimumVersion }
    if ($package.MaximumVersion) { $packageSplat.MaximumVersion = $package.MaximumVersion }
    if ($package.RequiredVersion) { $packageSplat.RequiredVersion = $package.RequiredVersion }
    Get-Package @packageSplat -ProviderName nuget -ErrorAction SilentlyContinue
}