function Update-DBOPackage {
    <#
    .SYNOPSIS
    Updates DBOps package parameters

    .DESCRIPTION
    Overwrites package file inside the existing DBOps package with the new values provided by user

    .PARAMETER Path
    Path to the existing DBOpsPackage.
    Aliases: Name, FileName, Package

    .PARAMETER Slim
        Do not include accompanying modules into the package file.

    .PARAMETER PreScriptPath
        Path to the script(s) to be executed against the database before running the deployment. Pre-scripts are not journaled to the Schema Version table.

    .PARAMETER PostScriptPath
        Path to the Script(s) to be executed against the database after the deployment. Post-scripts are not journaled to the Schema Version table.

    .PARAMETER Version
        Set the version of the package - this, however, does not impact builds inside the package.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Reconfigure package to become module-less
    Update-DBOPackage Package.zip -Slim $true

    .EXAMPLE
    # Reconfigure Pre- and Post scripts
    Get-DBOPackage Package.zip | Update-DBOPackage -PreScriptPath .\prescripts -PostScriptPath (Get-ChildItem .\postscripts)

    .EXAMPLE
    # Update the internal version of the package without modifying builds or their order
    "Package.zip" | Update-DBOPackage -Version "2.0beta"

    #>
    [CmdletBinding(DefaultParameterSetName = 'Value',
        SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('FileName', 'Name', 'Package')]
        [string[]]$Path,
        [ValidateNotNullOrEmpty()]
        [bool]$Slim,
        [object[]]$PreScriptPath,
        [object[]]$PostScriptPath,
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )
    begin {

    }
    process {
        foreach ($p in $Path) {
            $package = Get-DBOPackage -Path $p
            if ($pscmdlet.ShouldProcess($package, "Updating the package file/object")) {
                if (Test-PSFParameterBinding -ParameterName Slim) {
                    Write-PSFMessage -Level Verbose -Message "Setting Slim to $Slim"
                    $package.Slim = $Slim
                }
                if (Test-PSFParameterBinding -ParameterName PreScriptPath) {
                    $preScriptCollection = Get-DbopsFile $PreScriptPath
                    Write-PSFMessage -Level Verbose -Message "Adding $($preScriptCollection.Count) pre-script(s) from $PreScriptPath"
                    $package.SetPreScripts($preScriptCollection)
                }
                if (Test-PSFParameterBinding -ParameterName PostScriptPath) {
                    $postScriptCollection = Get-DbopsFile $PostScriptPath
                    Write-PSFMessage -Level Verbose -Message "Adding $($postScriptCollection.Count) post-script(s) from $PostScriptPath"
                    $package.SetPostScripts($postScriptCollection)
                }
                if (Test-PSFParameterBinding -ParameterName Version) {
                    Write-PSFMessage -Level Verbose -Message "Setting Version to $Version"
                    $package.Version = $Version
                }
                $package.Alter()
            }
        }
    }
    end {

    }
}
