# install modules
. "$PSScriptRoot\pester.prep.ps1"

# install and import libraries
. "$PSScriptRoot\import.ps1" -Internal

foreach ($type in @('Oracle', 'MySQL', 'PostgreSQL')) {
    foreach ($lib in (Get-ExternalLibrary -Type $type)) {
        if (-not ($ver = $lib.RequiredVersion)) {
            $ver = $lib.MaximumVersion
        }

        $package = Install-NugetPackage -Name $lib.Name -RequiredVersion $ver -Force -Confirm:$false -Scope CurrentUser
        foreach ($path in $lib.Path) {
            Add-Type -Path (Join-Path (Split-Path $package.Source -Parent) $path)
        }
    }
}