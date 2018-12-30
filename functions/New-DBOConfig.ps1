function New-DBOConfig {
    <#
    .SYNOPSIS
    Returns a new DBOpsConfig object
    
    .DESCRIPTION
    Returns a newly created DBOpsConfig object with default values.
    Values can be checked and modified using Get/Set-DBODefaultSetting commands.
        
    .PARAMETER Configuration
    Overrides for the configuration values. Will replace default configuration values.

    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Returns new default configuration
    New-DBOConfig
    
    .EXAMPLE
    # Returns configuration overriding ConnectionTimeout
    New-DBOConfig -Configuration @{ ConnectionTimeout = 5 }

    .EXAMPLE
    # Saves empty configuration to a file
    New-DBOConfig | Export-DBOConfig c:\package\dbops.config.json

    #>
    [CmdletBinding()]
    param
    (
        [object]$Configuration
    )
    return [DBOpsConfig]::new() | Get-DBOConfig -Configuration $Configuration
}