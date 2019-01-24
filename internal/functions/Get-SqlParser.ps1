function Get-SqlParser {
    # Returns a Sql parser object for a specific RDBMS
    Param (
        [Parameter(Mandatory)]
        [DBOps.ConnectionType]$Type
    )
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        return [DbUp.SqlServer.SqlServerObjectParser]::new()
    }
    elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
        return [DbUp.Oracle.OracleObjectParser]::new()
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        return [DbUp.MySql.MySqlObjectParser]::new()
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        return [DbUp.Postgresql.PostgresqlObjectParser]::new()
    }
    else {
        Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
        return
    }
}