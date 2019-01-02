function Initialize-ExternalLibrary {
    #Load external libraries for a specific RDBMS
    Param (
        [Parameter(Mandatory)]
        [string]$Type
    )
    if (-Not (Test-DBOSupportedSystem -Type $Type)) {
        Write-PSFMessage -Level Warning -Message "Installing dependent libraries for $Type connections"
        # Install dependencies into the current user scope
        Install-DBOSupportLibrary -Type $Type -Scope CurrentUser
        # test again
        if (-Not (Test-DBOSupportedSystem -Type $Type)) {
            Write-PSFMessage -Level Warning -Message "Dependent libraries for $Type were not found. Run Install-DBOSupportLibrary -Type $Type"
            Stop-PSFFunction -EnableException $true -Message "$Type is not supported on this system - some of the external dependencies are missing."
            return
        }
    }
    $dependencies = Get-ExternalLibrary -Type $Type
    foreach ($dPackage in $dependencies) {
        $localPackage = Get-Package -Name $dPackage.Name -RequiredVersion $dPackage.Version -ProviderName nuget -ErrorAction Stop
        foreach ($dPath in $dPackage.Path) {
            Write-PSFMessage -Level Debug -Message "Loading library $dPath from $($localPackage.Source)"
            try {
                Add-Type -Path (Join-PSFPath -Normalize (Split-Path $localPackage.Source -Parent) $dPath) -ErrorAction Stop
            }
            catch {
                Stop-PSFFunction -EnableException $true -Message "Could not load $dPath from $localPackage" -Exception $_
            }
        }
    }
}