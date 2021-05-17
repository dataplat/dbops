function Merge-Config {
    <#
    .SYNOPSIS
        Merges config from different sources together.
    #>
    param (
        [hashtable]$BoundParameters,
        $Package,
        [switch]$ProcessVariables
    )
    $config = New-DBOConfig
    # Merge package config into the current config
    if ($Package) {
        $config = $config | Get-DBOConfig -Configuration $package.Configuration
    }
    # Merge custom config into the current config
    if ('Configuration' -in $BoundParameters.Keys) {
        $config = $config | Get-DBOConfig -Configuration $BoundParameters.Configuration
    }

    #Merge custom parameters into a configuration
    $newConfig = @{ }
    foreach ($key in ($BoundParameters.Keys)) {
        if ($key -in [DBOpsConfig]::EnumProperties()) {
            $newConfig.$key = $BoundParameters[$key]
        }
    }
    $config.Merge($newConfig)

    if ($ProcessVariables) {
        # Replace tokens if any
        Write-PSFMessage -Level Debug -Message "Replacing variable tokens"
        foreach ($property in [DBOpsConfig]::EnumProperties() | Where-Object { $_ -ne 'Variables' }) {
            $config.SetValue($property, (Resolve-VariableToken $config.$property $config.Variables))
        }
    }

    return $config
}