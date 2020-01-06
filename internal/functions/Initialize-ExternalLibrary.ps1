function Initialize-ExternalLibrary {
    #Load external libraries for a specific RDBMS
    Param (
        [Parameter(Mandatory)]
        [DBOps.ConnectionType]$Type
    )
    # try looking up already loaded assemblies
    $libs = [System.AppDomain]::CurrentDomain.GetAssemblies().GetName()
    $dependencies = Get-ExternalLibrary -Type $Type
    $isLoaded = $true
    foreach ($dPackage in $dependencies) {
        if ($lib = $libs | Where-Object Name -eq $dPackage.Name) {
            if ($minVersion = $dPackage.MinimumVersion -as [version]) {
                if ($minVersion -gt $lib.Version) {
                    $isLoaded = $false; break
                }
            }
            if ($maxVersion = $dPackage.MaximumVersion -as [version]) {
                if ($maxVersion -lt $lib.Version) {
                    $isLoaded = $false; break
                }
            }
            if ($reqVersion = $dPackage.RequiredVersion -as [version]) {
                if ($reqVersion -eq $lib.Version) {
                    $isLoaded = $false; break
                }
            }
            Write-PSFMessage -Level Verbose -Message "$($lib.Name) $($lib.Version) was found among the loaded libraries, assuming that the library is fully loaded"
        }
        else {
            $isLoaded = $false; break
        }
    }
    if ($isLoaded) {
        Write-PSFMessage -Level Debug -Message "All libraries for $Type were found among the loaded libraries"
        return
    }
    # get package from the local system
    if (-Not (Test-DBOSupportedSystem -Type $Type)) {
        Write-PSFMessage -Level Warning -Message "Installing dependent libraries for $Type connections"
        # Install dependencies into the current user scope
        $null = Install-DBOSupportLibrary -Type $Type -Scope CurrentUser
        # test again
        if (-Not (Test-DBOSupportedSystem -Type $Type)) {
            Write-PSFMessage -Level Warning -Message "Dependent libraries for $Type were not found. Run Install-DBOSupportLibrary -Type $Type"
            Stop-PSFFunction -EnableException $true -Message "$Type is not supported on this system - some of the external dependencies are missing."
            return
        }
    }
    $dependencies = Get-ExternalLibrary -Type $Type
    foreach ($package in $dependencies) {
        $packageSplat = @{
            Name            = $package.Name
            MinimumVersion  = $package.MinimumVersion
            MaximumVersion  = $package.MaximumVersion
            RequiredVersion = $package.RequiredVersion
            ProviderName    = "nuget"
        }
        $localPackage = Get-Package @packageSplat
        foreach ($dPath in $package.Path) {
            Write-PSFMessage -Level Debug -Message "Loading library $dPath from $($localPackage.Source)"
            try {
                $null = Add-Type -Path (Join-PSFPath -Normalize (Split-Path $localPackage.Source -Parent) $dPath) -ErrorAction SilentlyContinue
            }
            catch {
                Stop-PSFFunction -EnableException $true -Message "Could not load $dPath from $localPackage" -ErrorRecord $_
            }
        }
    }
}