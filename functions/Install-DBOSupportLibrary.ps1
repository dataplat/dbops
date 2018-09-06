Function Install-DBOSupportLibrary {
    <#
    .SYNOPSIS
    Installs external dependencies for a defined RDBMS
    
    .DESCRIPTION
    This command will download nuget packages from NuGet website in order to support deployments for certain RDBMS.
    
    .PARAMETER Type
    RDBMS Type: Oracle, SQLServer
    
    .PARAMETER Force
    Enforce installation
    
    .PARAMETER Scope
    Choose whether to install for CurrentUser or for AllUsers
    
    .EXAMPLE
    #Installs all dependencies for Oracle
    Install-DBOSupportLibrary Oracle
    .NOTES
    
    #>
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('System', 'Database')]
        [ValidateSet('SQLServer', 'Oracle')]
        [string[]]$Type,
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'AllUsers',
        [switch]$Force
    )
    begin {
        $nugetAPI = "http://www.nuget.org/api/v2"
        $packageSource = Get-PackageSource -Name nuget.org -ErrorAction SilentlyContinue
        # checking if nuget has an incorrect API url
        if ($packageSource.Location -like 'https://api.nuget.org/v3*') {
            Write-PSFMessage -Level Warning -Message "NuGet package source is registered using API v3, which prevents Install-Package to download nuget packages. Registering a new package source nuget.org.dbops to download packages."
            $packageSource = Register-PackageSource -Name nuget.org.dbops -Location $nugetAPI -ProviderName nuget -Force:$Force -ErrorAction Stop
        }
        if (!$packageSource) {
            Write-PSFMessage -Level Verbose -Message "Registering nuget.org package source $nugetAPI"
            $packageSource = Register-PackageSource -Name nuget.org -Location $nugetAPI -ProviderName nuget -Force:$Force -ErrorAction Stop
        }
    }
    process {
        $dependencies = Get-ExternalLibrary
        foreach ($t in $Type) {
            # Install dependencies
            foreach ($package in $dependencies.$t) {
                Write-PSFMessage -Level Verbose -Message "Installing package $($package.Name)($($package.Version))"
                Install-Package -Source $packageSource.Name -Name $package.Name -MinimumVersion $package.Version -Force:$Force -Scope:$Scope
            }
        }
    }
    end { }
}
