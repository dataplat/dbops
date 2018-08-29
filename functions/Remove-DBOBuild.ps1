Function Remove-DBOBuild {
    <#
    .SYNOPSIS
    Removes one or more builds from the DBOps package
    
    .DESCRIPTION
    Remove specific list of builds from the existing DBOps package keeping all other parts of the package intact
    
    .PARAMETER Path
    Path to the existing DBOpsPackage.
    Aliases: Name, FileName, Package
    
    .PARAMETER Build
    One or more builds to remove from the package.
    
    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Removes builds 1.1 and 1.2 from the package
    Remove-DBOBuild -Path c:\temp\myPackage.zip -Build 1.1, 1.2

    .EXAMPLE
    # Removes all 1.* builds from the package
    $builds = (Get-DBOPackage c:\temp\myPackage.zip).Builds
    $builds.Build | Where { $_ -like '1.*' } | Remove-DBOBuild -Path c:\temp\myPackage.zip
    
    .NOTES
    
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('FileName', 'Name', 'Package')]
        [string]$Path,
        [Parameter(Mandatory = $true,
            Position = 2)]
        [string[]]$Build
    )
    begin {
        
    }
    process {
        Write-PSFMessage -Level Verbose -Message "Loading package information from $Path"
        if ($package = Get-DBOPackage -Path $Path) {
            foreach ($currentBuild in $Build) {
                #Verify that build exists
                if ($currentBuild -notin $package.EnumBuilds()) {
                    Write-Warning "Build $currentBuild not found in the package, skipping."
                    continue
                }
            
                Write-PSFMessage -Level Verbose -Message "Removing $currentBuild from the package object"
                $package.RemoveBuild($currentBuild)

                if ($pscmdlet.ShouldProcess($package, "Saving changes to the package")) {
                    $package.Alter()
                }
            }
        }
    }
    end {
        
    }
}