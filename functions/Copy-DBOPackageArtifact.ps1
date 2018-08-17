Function Copy-DBOPackageArtifact {
    <#
    .SYNOPSIS
    Copies a DBOps package file stored in the specific artifact repository to the specified location.
    
    .DESCRIPTION
    Copies a DBOps package file from an artifact repository created by Publish-DBOPackageArtifact to the specified location.
   
    .PARAMETER Name
    Name of the DBOps package

    Aliases: FileName, Package
    
    .PARAMETER Repository
    Path to the artifact repository - a folder or a network share

    Aliases: RepositoryPath

    .PARAMETER Destination
    Target path where to copy the package

    .PARAMETER Version
    If specified, searches for a specific version of the package inside the repository

    .PARAMETER Passthru
    Returns a filesystem object after excecution
    
    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Copies the latest version of the package myPackage.zip from the repository \\data\repo to the local folder .\
    Copy-DBOPackageArtifact -Name myPackage.zip -Repository \\data\repo -Destination .
    
    .EXAMPLE
    # Copies a specific version of the package myPackage.zip from the repository \\data\repo to the folder c:\workspace
    Copy-DBOPackageArtifact -Name myPackage -Repository \\data\repo -Version 2.2.1 -Destination c:\workspace
    
    .NOTES
    
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [Alias('RepositoryPath')]
        [object]$Repository,
        [Parameter(Mandatory = $true)]
        [Alias('FileName', 'Package')]
        [string]$Name,
        [string]$Destination,
        [Version]$Version,
        [Switch]$Passthru
    )
    begin {
        $src = Get-DBOPackageArtifact -Repository $Repository -Name $Name -Version $Version
    }
    process {
        if ($PSCmdlet.ShouldProcess($src, "Copying file to the destination $Destination")) {
            Copy-Item -Path $src -Destination $Destination -Passthru:$Passthru -ErrorAction Stop
        }
    }
    end {

    }
}