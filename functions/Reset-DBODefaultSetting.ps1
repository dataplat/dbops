function Reset-DBODefaultSetting {
    <#
        .SYNOPSIS
            Resets configuration entries back to default values.
    
        .DESCRIPTION
            This function creates or changes configuration values.
            These can be used to provide dynamic configuration information outside the PowerShell variable system.
    
        .PARAMETER Name
            Name of the configuration entry.

        .PARAMETER All
            Specify if you want to reset all configuration values to their defaults.

        .PARAMETER Confirm
            Prompts to confirm certain actions

        .PARAMETER WhatIf
            Shows what would happen if the command would execute, but does not actually perform the command

        .EXAMPLE
            Reset-DBODefaultSetting -Name ConnectionTimeout
        
            Reset connection timeout setting back to default value.
        
        .EXAMPLE
            Reset-DBODefaultSetting -All
        
            Reset all settings.
    #>
    [CmdletBinding(DefaultParameterSetName = "Named", SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ParameterSetName = 'Named')]
        [string[]]$Name,
        [parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All
    )

    process {
        if ($Name) {
            foreach ($n in $Name) {
                if ($PSCmdlet.ShouldProcess($Name, "Resetting the setting back to its default value")) {
                    $config = Get-PSFConfig -FullName dbops.$n
                    if ($config) { $config.ResetValue() }
                    else {
                        Stop-PSFFunction -Message "Unable to find setting $n" -EnableException $true
                    }
                }
            }
        }
        elseif ($All) {
            foreach ($config in Get-PSFConfig -Module dbops ) {
                if ($PSCmdlet.ShouldProcess($config, "Resetting the setting back to its default value")) {
                    if ($config.Initialized) {
                        $config.ResetValue()
                    }
                    else {
                        Write-PSFMessage -Level Warning -Message "Setting $($config.fullName -replace '^dbops\.','')) was not initialized and has no default value as such"
                    }
                }
            }
        }
    }
}