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

    .PARAMETER SkipDependencies
    Skips dependencies of the package with the connectivity libraries, only downloading a single package.

    .PARAMETER SkipPreRelease
    Skip pre-release versions of the packages to be downloaded.

    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command


    .EXAMPLE
    #Installs all dependencies for Oracle
    Install-DBOSupportLibrary Oracle
    .NOTES

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('System', 'Database')]
        [DBOps.ConnectionType[]]$Type,
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'AllUsers',
        #[switch]$SkipDependencies, # disabling for now, dependencies are not supported anyways
        [switch]$SkipPreRelease,
        [switch]$Force
    )
    begin {

    }
    process {
        $dependencies = Get-ExternalLibrary
        $packagesToUpdate = @()
        foreach ($t in $Type) {
            # Check existance
            foreach ($package in $dependencies.$t) {
                $packageSplat = @{
                    Name            = $package.Name
                    MinimumVersion  = $package.MinimumVersion
                    MaximumVersion  = $package.MaximumVersion
                    RequiredVersion = $package.RequiredVersion
                }
                $p = Get-Package @packageSplat -ProviderName nuget -ErrorAction SilentlyContinue
                if (-Not $p -or $Force) { $packagesToUpdate += $packageSplat }
            }
        }
        if ($packagesToUpdate -and $PSCmdlet.ShouldProcess("Scope: $Scope", "Installing dependent package(s) $($packagesToUpdate.Name -join ', ') from nuget.org")) {
            # Install dependencies
            foreach ($packageSplat in $packagesToUpdate) {
                Write-PSFMessage -Level Verbose -Message "Installing package`: $($packageSplat | ConvertTo-Json -Compress)"
                $null = Install-NugetPackage @packageSplat -Force:$Force -Scope $Scope -SkipPreRelease:$SkipPreRelease
            }
        }
    }
    end { }
}
