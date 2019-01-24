Function Get-DBOPackageArtifact {
    <#
    .SYNOPSIS
    Returns a path to a DBOps package  file stored in the specific artifact repository.
    
    .DESCRIPTION
    Returns a path from an artifact repository created by Publish-DBOPackageArtifact.

    Repository is structured as a simple folder with subfolders inside:

    (Optional)RootFolder
    - PackageName
      - Current
        - PackageName.zip
      - Versions
        - 1.0
          - PackageName.zip
        - 2.0
          - PackageName.zip
        ...
      
    
    .PARAMETER Name
    Name of the DBOps package

    Aliases: FileName, Package
    
    .PARAMETER Repository
    Path to the artifact repository - a folder or a network share

    Aliases: RepositoryPath

    .PARAMETER Version
    If specified, searches for a specific version of the package inside the repository
    
    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Returns path to the latest version of the package myPackage.zip from the repository \\data\repo
    Get-DBOPackageArtifact -Name myPackage.zip -Repository \\data\repo
    
    .EXAMPLE
    # Returns path to the specific version of the package myPackage.zip from the repository \\data\repo
    Get-DBOPackageArtifact -Name myPackage -Repository \\data\repo -Version 2.2.1
    
    .NOTES
    
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [Alias('RepositoryPath')]
        [object]$Repository,
        [Parameter(Mandatory = $true)]
        [Alias('FileName', 'Package')]
        [string]$Name,
        [Version]$Version
    )
    begin {
        $repo = Get-Item $Repository -ErrorAction Stop
    }
    process {
        $pkgName = $Name -replace '\.zip$', ''
        $pkgName = Split-Path $pkgName -Leaf
        if ((Test-Path (Join-Path $repo Current)) -and (Test-Path (Join-Path $repo Versions))) {
            Write-PSFMessage -Level Debug -Message "Valid folder structure found in $repo"
            $repoFolder = $repo
        }
        else {
            Write-PSFMessage -Level Debug -Message "Assuming $repo is a top-level repo folder"
            try {
                $repoFolder = Get-Item (Join-Path $repo $pkgName) -ErrorAction Stop
            }
            catch {
                Stop-PSFFunction -Message "File not found: incorrect structure of the repository, or empty repository" -ErrorRecord $_ -Category ObjectNotFound
                return
            }
        }
        try {
            $currentVersionFolder = Get-Item (Join-Path $repoFolder 'Current') -ErrorAction Stop
            $versionFolder = Get-Item (Join-Path $repoFolder 'Versions') -ErrorAction Stop
        }
        catch {
            Stop-PSFFunction -Message "File not found: incorrect structure of the repository, or empty repository" -ErrorRecord $_ -Category ObjectNotFound
            return
        }
        if ($Version) {
            try {
                $packageFolder = Get-Item (Join-Path $versionFolder $Version.ToString()) -ErrorAction Stop
            }
            catch {
                Stop-PSFFunction -Message "Version $Version not found or incorrect structure of the repository" -ErrorRecord $_ -Category ObjectNotFound
                return
            }
        }
        else {
            $packageFolder = $currentVersionFolder
        }
        #Adding extention back
        $zipPkgName = "$pkgName.zip"
        #Returing the file object
        try {
            Get-Item (Join-Path $packageFolder $zipPkgName) -ErrorAction Stop
        }
        catch {
            Stop-PSFFunction -Message "File $zipPkgName was not found in $packageFolder. Incorrect structure of the repository." -ErrorRecord $_ -Category ObjectNotFound
            return
        }
    }
    end {

    }
}