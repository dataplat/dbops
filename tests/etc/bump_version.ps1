Param (
    $Path = '.\dbops.psd1'
)
$moduleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
$version = [Version]$moduleFile.ModuleVersion
$regEx = "^([\s]*ModuleVersion[\s]*\=[\s]*)\'(" + [regex]::Escape($version) + ")\'[\s]*`$"
Write-Host "Current build $version"

if ($env:gitcommitmessage -notlike "*Bumping up version*") {
    [string]$newVersion = [Version]::new($version.Major, $version.Minor, ($version.Build + 1))
    $content = Get-Content $Path
    $content | % { $_ -replace $regEx, "`$1'$newVersion'" } | Out-File $Path -Force -Encoding utf8
    $newModuleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
    Write-Host "New build $($newModuleFile.ModuleVersion)"
}