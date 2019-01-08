function Get-DatabaseConnection {
    # Returns a connection manager object
    Param (
        [Parameter(ParameterSetName = 'ConnString', Mandatory)]
        [string]$ConnectionString,
        [Parameter(ParameterSetName = 'Config', Mandatory)]
        [DBOpsConfig]$Configuration,
        [DBOps.ConnectionType]$Type
    )
    if ($Configuration) {
        $ConnectionString = Get-ConnectionString -Configuration $Configuration -Type $Type
    }
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        return [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
        return [Oracle.DataAccess.Client.OracleConnection]::new($ConnectionString)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        return [MySql.Data.MySqlClient.MySqlConnection]::new($ConnectionString)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        return [Npgsql.NpgsqlConnection]::new($ConnectionString)
    }
    else {
        Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
        return
    }
}