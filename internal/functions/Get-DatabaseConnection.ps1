function Get-DatabaseConnection {
    # Returns a connection manager object
    Param (
        [Parameter(ParameterSetName = 'ConnString')]
        [string]$ConnectionString,
        [Parameter(ParameterSetName = 'Config', Mandatory)]
        [DBOpsConfig]$Configuration,
        [DBOps.ConnectionType]$Type
    )
    if ($Configuration) {
        $ConnectionString = Get-ConnectionString -Configuration $Configuration -Type $Type
    }
    $connection = switch ($Type) {
        SqlServer { [System.Data.SqlClient.SqlConnection]::new($ConnectionString) }
        Oracle { [Oracle.DataAccess.Client.OracleConnection]::new($ConnectionString) }
        MySQL { [MySql.Data.MySqlClient.MySqlConnection]::new($ConnectionString) }
        PostgreSQL { [Npgsql.NpgsqlConnection]::new($ConnectionString) }
        default { Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true }
    }
    return $connection
}