function Export-DBOConfig {
    <#
    .SYNOPSIS
    Exports configuration file from existing DBOps package or DBOps config
    
    .DESCRIPTION
    Exports configuration file from existing DBOps package or DBOps config to a json file.
    
    .PARAMETER Path
    Path to the target json file.

    .PARAMETER InputObject
    Object to get the configuration from.

    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Export package configuration to a json file
    Get-DBOPackage Package.zip | Export-DBOConfig .\config.json

    .EXAMPLE
    # Export blank configuration to a json file
    New-DBOConfig | Export-DBOConfig .\config.json

    .EXAMPLE
    # Export configuration from a package file to a json file
    Get-Item 'mypackage.zip'| Export-DBOConfig .\config.json
    
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [Parameter(Mandatory, Position = 1)]
        [string]$Path
    )
    begin {

    }
    process {
        $config = Get-DBOConfig -InputObject $InputObject

        if ($pscmdlet.ShouldProcess($config, "Saving the config file")) {
            $config.SaveToFile($Path)
        }
    }
    end {

    }
}
