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

        .PARAMETER Temporary
            The setting is not persisted outside the current session.
            By default, settings will be remembered across all powershell sessions.

        .PARAMETER Scope
            Choose if the setting should be stored in current user's registry or will be shared between all users.
            Allowed values: CurrentUser, AllUsers.
            AllUsers will require administrative access to the computer (elevated session).

            Default: CurrentUser.

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
        [switch]$All,
        [switch]$Temporary,
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    process {
        if ($Name) {
            $settings = @()
            foreach ($n in $Name) {
                $config = Get-PSFConfig -FullName dbops.$n
                if ($config) { $settings += $config }
                else { Stop-PSFFunction -Message "Unable to find setting $n" -EnableException $true }
            }
        }
        elseif ($All) { $settings = Get-PSFConfig -Module dbops }
        $newScope = switch ($Scope) {
            'CurrentUser' { 'UserDefault' }
            'AllUsers' { 'SystemDefault' }
        }
        foreach ($config in $settings) {
            $sName = $config.fullName -replace '^dbops\.', ''
            if ($PSCmdlet.ShouldProcess($config, "Resetting the setting $sName back to its default value")) {
                if ($config.Initialized) {
                    $config.ResetValue()
                }
                else {
                    Write-PSFMessage -Level Warning -Message "Setting $sName was not initialized and has no default value as such"
                }
                if (!$Temporary) {
                    if ($PSCmdlet.ShouldProcess($Name, "Unregistering $sName in the $newScope scope")) {
                        $config | Unregister-PSFConfig -Scope $newScope
                    }
                }
            }
        }
    }
}