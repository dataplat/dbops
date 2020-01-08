Function Test-DBOSupportedSystem {
    <#
    .SYNOPSIS
    Test if module is ready to work with certain RDBMS

    .DESCRIPTION
    Test if access to a certain RDBMS is currently supported by the module by checking if all the dependencies have been installed

    .PARAMETER Type
    RDBMS Type: Oracle, SQLServer

    .EXAMPLE
    #Tests if all dependencies for Oracle have been met
    Test-DBOSupportedSystem Oracle
    .NOTES

    #>
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('System', 'Database')]
        [DBOps.ConnectionType]$Type
    )
    begin { }
    process {
        $dependencies = Get-ExternalLibrary -Type $Type
        foreach ($package in $dependencies) {
            $packageSplat = @{
                Name            = $package.Name
                MinimumVersion  = $package.MinimumVersion
                MaximumVersion  = $package.MaximumVersion
                RequiredVersion = $package.RequiredVersion
                ProviderName    = "nuget"
            }
            $packageEntry = Get-Package @packageSplat -ErrorAction SilentlyContinue
            if (!$packageEntry) {
                return $false
            }
        }
        return $true
    }
    end { }
}
