Function Publish-DBOPackageArtifact {
    <#
    .SYNOPSIS
    Publishes DBOps package to the specific artifact repository.

    .DESCRIPTION
    Publishes a DBOps package file to an artifact repository located in a specific folder

    Repository is structured as a top-level repository folder with subfolders inside:

    RepositoryFolder
    - PackageName
      - Current
        - PackageName.zip
      - Versions
        - 1.0
          - PackageName.zip
        - 2.0
          - PackageName.zip
        ...

    Newly submitted package will replace the package in the Current folder, as well as will
    create a proper subfolder in the Versions folder and copy the file there as well.

    .PARAMETER Path
    Name of the DBOps package

    Aliases: Name, FileName, Package

    .PARAMETER Repository
    Path to the artifact repository - a folder or a network share

    Aliases: RepositoryPath

    .PARAMETER VersionOnly
    Will copy the file only to the proper Versions subfolder, skipping replacing the file in the Current folder

    .PARAMETER Force
    Will replace existing version in the repository

    .PARAMETER InputObject
    Pipeline implementation of Path. Can also contain a DBOpsPackage object.

    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Saves the package myPackage.zip in the repository \\data\repo
    Publish-DBOPackageArtifact -Name myPackage.zip -Repository \\data\repo

    .EXAMPLE
    # Saves the package myPackage.zip in the repository \\data\repo without updating the most current
    # version in the repository. Will overwrite the existing version when exists
    Get-DBOPackage myPackage.zip | Publish-DBOPackageArtifact -Repository \\data\repo -VersionOnly -Force

    .NOTES

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory = $true, Position = 1)]
        [Alias('RepositoryPath')]
        [object]$Repository,
        [Parameter(Mandatory = $true, ParameterSetName = 'Default', Position = 2)]
        [Alias('FileName', 'Package', 'Name')]
        [string]$Path,
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            ParameterSetName = 'Pipeline')]
        [object]$InputObject,
        [switch]$VersionOnly,
        [switch]$Force
    )
    begin {
        $repo = Get-Item $Repository -ErrorAction Stop
    }
    process {
        if ($PsCmdlet.ParameterSetName -eq 'Default') {
            $package = Get-DBOPackage -Path $Path
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'Pipeline') {
            $package = Get-DBOPackage -InputObject $InputObject
        }
        $pkgName = Split-Path ($package.FullName -replace '\.zip$', '') -Leaf
        if ($PsCmdlet.ShouldProcess([string]$package, "Publishing package to $repo")) {
            if ((Test-Path (Join-Path $repo Current)) -and (Test-Path (Join-Path $repo Versions))) {
                Write-PSFMessage -Level Verbose -Message "Valid folder structure found in $repo"
                $repoFolder = $repo
            }
            else {
                Write-PSFMessage -Level Verbose -Message "Assuming $repo is a top-level repo folder"
                if (Test-Path (Join-Path $repo $pkgName)) {
                    $repoFolder = Get-Item (Join-Path $repo $pkgName) -ErrorAction Stop
                }
                else {
                    $repoFolder = New-Item (Join-Path $repo $pkgName) -ItemType Directory -ErrorAction Stop
                }
            }
            'Current', 'Versions' | ForEach-Object {
                if (Test-Path (Join-Path $repoFolder $_)) {
                    $null = Get-Item (Join-Path $repoFolder $_) -ErrorAction Stop -OutVariable "repo$($_)Folder"
                }
                else {
                    Write-PSFMessage -Level Verbose -Message "Creating folder $_ inside the repo"
                    $null = New-Item (Join-Path $repoFolder $_) -ItemType Directory -ErrorAction Stop -OutVariable "repo$($_)Folder"
                }
            }
            $zipPkgName = "$pkgName.zip"
            Write-PSFMessage -Level Verbose -Message "Copying package to the versions folder"
            $versionFolder = New-Item (Join-Path $repoVersionsFolder $package.Version) -ItemType Directory -Force -ErrorAction Stop
            $destinationPath = Join-Path $versionFolder $zipPkgName
            if (-not (Get-Item $destinationPath -ErrorAction SilentlyContinue) -or $Force) {
                Copy-Item $package.FullName $destinationPath -ErrorAction Stop
            }

            if (!$VersionOnly) {
                Write-PSFMessage -Level Verbose -Message "Copying package to the current version folder"
                Copy-Item $package.FullName (Join-Path $repoCurrentFolder $zipPkgName) -ErrorAction Stop
                Get-DBOPackageArtifact -Repository $Repository -Name $pkgName
            }
            else {
                Get-DBOPackageArtifact -Repository $Repository -Name $pkgName -Version $package.Version
            }
        }
    }
    end {

    }
}