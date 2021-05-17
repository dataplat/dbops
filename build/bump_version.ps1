Param (
    $Path = '.\dbops.psd1'
)
git config --global user.email $env:git_user_email
git config --global user.name $env:git_username
$moduleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
$version = [Version]$moduleFile.ModuleVersion
$regEx = "^([\s]*ModuleVersion[\s]*\=[\s]*)\'(" + [regex]::Escape($version) + ")\'[\s]*`$"
Write-Host "Current build $version"

# Install-PackageProvider nuget -force
[version]$publishedVersion = Find-Module dbops -ErrorAction Stop | Select-Object -ExpandProperty Version
if ($version -le $publishedVersion) {
    # increase version and push back to git
    [string]$newVersion = [Version]::new($publishedVersion.Major, $publishedVersion.Minor, ($publishedVersion.Build + 1))
    $content = Get-Content $Path
    $content | Foreach-Object { $_ -replace $regEx, "`$1'$newVersion'" } | Out-File $Path -Force -Encoding utf8
    $newModuleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
    Write-Host "New build $($newModuleFile.ModuleVersion)"
    git add $moduleFile
    git commit -m "v$version"
}
git push origin HEAD:development
git branch release/$version
git push --all origin