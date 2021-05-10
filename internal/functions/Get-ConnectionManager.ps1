function Get-ConnectionManager {
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
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        return [DbUp.SqlServer.SqlConnectionManager]::new($ConnectionString)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
        return [DbUp.Oracle.OracleConnectionManager]::new($ConnectionString, [DbUp.Oracle.OracleCommandSplitter]::new('/'))
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        return [DbUp.MySql.MySqlConnectionManager]::new($ConnectionString)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        return [DbUp.Postgresql.PostgresqlConnectionManager]::new($ConnectionString)
    }
    else {
        Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
        return
    }
}