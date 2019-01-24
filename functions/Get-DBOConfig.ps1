function Get-DBOConfig {
    <#
    .SYNOPSIS
    Returns a DBOpsConfig object
    
    .DESCRIPTION
    Returns a DBOpsConfig object from an existing json file. If file was not specified, returns a blank DBOpsConfig object.
    Values of the config can be overwritten by the hashtable parameter -Configuration.
    
    .PARAMETER Path
    Path to the JSON config file.

    .PARAMETER InputObject
    Object to get the configuration from.
        
    .PARAMETER Configuration
    Overrides for the configuration values. Will replace existing configuration values.

    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Returns configuration from existing file
    Get-DBOConfig c:\package\dbops.config.json

    .EXAMPLE
    # Returns configuration overriding ConnectionTimeout
    Get-DBOConfig c:\package\dbops.config.json -Configuration @{ ConnectionTimeout = 5 }

    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param
    (
        [parameter(Mandatory, ParameterSetName = 'Path', Position = 1)]
        [string]$Path,
        [parameter(Mandatory, ParameterSetName = 'Pipeline', ValueFromPipeline)]
        $InputObject,
        [object]$Configuration
    )
    if ($PsCmdlet.ParameterSetName -eq 'Path') {
        $config = [DBOpsConfig]::FromFile($Path)
    }
    elseif ($PsCmdlet.ParameterSetName -eq 'Pipeline') {
        if ($InputObject -is [DBOpsConfig]) {
            $config = $InputObject
        }
        else {
            # assuming it's a package - file or else
            $package = Get-DBOPackage -InputObject $InputObject
            $config = $package.Configuration
        }
    }
    if (Test-PSFParameterBinding -ParameterName Configuration) {
        if ($Configuration -is [DBOpsConfig] -or $Configuration -is [hashtable]) {
            Write-PSFMessage -Level Verbose -Message "Merging configuration from a $($Configuration.GetType().Name) object"
            $config.Merge($Configuration)
        }
        elseif ($Configuration -is [String] -or $Configuration -is [System.IO.FileInfo]) {
            $configFromFile = Get-DBOConfig -Path $Configuration
            Write-PSFMessage -Level Verbose -Message "Merging configuration from file $($Configuration)"
            $config.Merge($configFromFile)
        }
        elseif ($Configuration) {
            Stop-PSFFunction -EnableException $true -Message "The following object type is not supported: $($Configuration.GetType().Name). The only supported types are DBOpsConfig, Hashtable, FileInfo and String"
        }
    }
    return $config
}