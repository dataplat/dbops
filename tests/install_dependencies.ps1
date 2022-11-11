param (
    $Type = @('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL'),
    [switch]$Load
)

. "$PSScriptRoot\import.ps1" -Internal

foreach ($t in $Type) {
    foreach ($lib in (Get-ExternalLibrary -Type $t)) {
        if (-not ($ver = $lib.RequiredVersion)) {
            $ver = $lib.MaximumVersion
        }

        $package = Install-NugetPackage -Name $lib.Name -RequiredVersion $ver -Force -Confirm:$false -Scope CurrentUser
        if ($Load) {
            foreach ($path in $lib.Path) {
                Add-Type -Path (Join-Path (Split-Path $package.Source -Parent) $path)
            }
        }
    }
}