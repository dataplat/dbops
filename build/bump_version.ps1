Param (
    $Path = '.\dbops.psd1'
)
$moduleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
$version = [Version]$moduleFile.ModuleVersion
$regEx = "^([\s]*ModuleVersion[\s]*\=[\s]*)\'(" + [regex]::Escape($version) + ")\'[\s]*`$"
Write-Host "Current build $version"

$magicPhrase = "Bumping up version"
$commitMessage = git log -1 --pretty=%B
Install-PackageProvider nuget -force
[version]$publishedVersion = Find-Module dbops -ErrorAction Stop | Select-Object -ExpandProperty Version

if ($version -le $publishedVersion -and $commitMessage -notlike "$magicPhrase*") {
    # increase version and push back to git
    [string]$newVersion = [Version]::new($publishedVersion.Major, $publishedVersion.Minor, ($publishedVersion.Build + 1))
    $content = Get-Content $Path
    $content | Foreach-Object { $_ -replace $regEx, "`$1'$newVersion'" } | Out-File $Path -Force -Encoding utf8
    $newModuleFile = Invoke-Command -ScriptBlock ([scriptblock]::Create((Get-Content $Path -Raw)))
    Write-Host "New build $($newModuleFile.ModuleVersion)"
    git config --global user.email "nvarscar@gmail.com"
    git config --global user.name "nvarscar"
    git add .\dbops.psd1
    git commit -m "$magicPhrase`: $newVersion"
    git push origin HEAD:master 2>&1 > $null
    git push origin HEAD:development 2>&1 > $null
}
else {
    # trigger the release pipeline
    Write-Host "##vso[build.addbuildtag]Release"
}