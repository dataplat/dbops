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
    (New-DBOConfig).SaveToFile('c:\package\dbops.config.json')

    #>
    [CmdletBinding(SupportsShouldProcess = 'True')]
    param
    (
        [object]$Configuration
    )
    if ($pscmdlet.ShouldProcess("Generating blank configuration object")) {
        $config = [DBOpsConfig]::new()
        if ($Configuration) {
            if ($Configuration -is [DBOpsConfig] -or $Configuration -is [hashtable]) {
                Write-PSFMessage -Level Verbose -Message "Merging configuration"
                $config.Merge($Configuration)
            }
            else {
                Stop-PSFFunction -EnableException $true -Message "The following object type is not supported: $($InputObject.GetType().Name). The only supported types are DBOpsConfig and Hashtable."
            }
        }
        $config
    }
}