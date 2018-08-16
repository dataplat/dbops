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
        [ValidateSet('SQLServer', 'Oracle')]
        [string]$Type
    )
    begin {}
    process {
        $dependencies = Get-ExternalLibrary -Type $Type
        foreach ($package in $dependencies) {
            $packageFound = [bool](Get-Package $package.Name -MinimumVersion $package.Version -ErrorAction SilentlyContinue)
            if (!$packageFound) {
                Write-Warning -Message "Dependent packages for $Type were not found. Run Install-DBOSupportLibrary -Type $Type"
                return $false
            }
        }
        return $true
    }
    end {}
}
