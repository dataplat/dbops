function Get-DBOConfig {
    <#
    .SYNOPSIS
    Returns a DBOpsConfig object
    
    .DESCRIPTION
    Returns a DBOpsConfig object from an existing json file. If file was not specified, returns a blank DBOpsConfig object.
    Values of the config can be overwritten by the hashtable parameter -Configuration.
    
    .PARAMETER Path
    Path to the JSON config file.
        
    .PARAMETER Configuration
    Overrides for the configuration values. Will replace existing configuration values.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Returns empty configuration
    Get-DBOConfig
    
    .EXAMPLE
    # Returns configuration from existing file
    Get-DBOConfig c:\package\dbops.config.json

    .EXAMPLE
    # Saves empty configuration to a file
    (Get-DBOConfig).SaveToFile('c:\package\dbops.config.json')

    #>
    [CmdletBinding()]
    param
    (
        [string]$Path,
        [object]$Configuration
    )
    if (Test-PSFParameterBinding -ParameterName Path -BoundParameters $PSBoundParameters) {
        Write-PSFMessage -Level Verbose -Message "Reading configuration from $Path"
        $config = [DBOpsConfig]::FromFile($Path)
    }
    else {
        Write-PSFMessage -Level Verbose -Message "Generating blank configuration object"
        $config = [DBOpsConfig]::new()
    }
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