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
                $p = Get-Package -name $package.Name -RequiredVersion $package.Version -ProviderName nuget -ErrorAction SilentlyContinue
                if (-Not $p -or $Force) { $packagesToUpdate += $package }
            }
        }
        if ($packagesToUpdate -and $PSCmdlet.ShouldProcess("Scope: $Scope", "Installing dependent package(s) $($packagesToUpdate.Name -join ', ') from nuget.org")) {
            # Install dependencies
            foreach ($package in $packagesToUpdate) {
                Write-PSFMessage -Level Verbose -Message "Installing package $($package.Name)($($package.Version))"
                $null = Install-NugetPackage -Name $package.Name -RequiredVersion $package.Version -Force:$Force -Scope $Scope
            }
        }
    }
    end { }
}
