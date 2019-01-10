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
    begin {}
    process {
        # try looking up already loaded assemblies
        $lookupClass = switch ($Type) {
            SqlServer { 'System.Data.SqlClient.SqlConnection' }
            Oracle { 'Oracle.DataAccess.Client.OracleConnection' }
            MySQL { 'MySql.Data.MySqlClient.MySqlConnection' }
            PostgreSQL { 'Npgsql.NpgsqlConnection' }
            default { Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true }
        }
        if ([System.AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType($lookupClass, 0) }) {
            return $true
        }
        # otherwise get package from the local system
        $dependencies = Get-ExternalLibrary -Type $Type
        foreach ($package in $dependencies) {
            $packageEntry = Get-Package $package.Name -RequiredVersion $package.Version -ProviderName nuget -ErrorAction SilentlyContinue
            if (!$packageEntry) {
                return $false
            }
        }
        return $true
    }
    end {}
}
