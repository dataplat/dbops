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
    begin {}
    process {
        $dependencies = Get-ExternalLibrary
        # Installing Oracle dependencies
        $packageSource = Get-PackageSource -Name nuget.org -ErrorAction SilentlyContinue
        if (!$packageSource) {
            $null = Register-PackageSource -Name nuget.org -Location http://www.nuget.org/api/v2 -ProviderName nuget -Force:$Force -ErrorAction Stop
        }
        foreach ($t in $Type) {
            # Install dependencies
            foreach ($package in $dependencies.$t) {
                Install-Package -Name $package.Name -MinimumVersion $package.Version -Force:$Force -Scope:$Scope
            }
        }
    }
    end {}
}
