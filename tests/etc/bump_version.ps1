Param (
    $Path = '.\dbops.psd1'
)
#$path = '.\dbops.psd1'

$scriptBlock = [scriptblock]::Create((gc $path -Raw))
$moduleFile = Invoke-Command -ScriptBlock $scriptBlock
$version = [Version]$moduleFile.ModuleVersion
$regEx = "^([\s]*ModuleVersion[\s]*\=[\s]*)\'(" + [regex]::Escape($version) + ")\'[\s]*`$"
Write-Host "Current build $version"

if ($env:gitcommitmessage -notlike "*Bumping up version*") {
    [string]$newVersion = [Version]::new($version.Major, $version.Minor, ($version.Build + 1))
    Get-Content $Path | % { $_ -replace $regEx, "`$1'$newVersion'" } | Out-File $Path -Force
    $manifest = Test-ModuleManifest $Path -ErrorAction Stop
    Write-Host "New build $($manifest.Version)"
}