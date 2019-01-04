function Get-DbUpBuilder {
    # Returns a DbUp builder with a proper connection object
    Param (
        [Parameter(Mandatory)]
        [object]$Connection,
        [string]$Schema,
        [DBOps.ConnectionType]$Type
    )
    $dbUp = [DbUp.DeployChanges]::To
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        if ($Schema) {
            $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
        if ($Schema) {
            $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUp, $dbUpConnection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySql) {
        if ($Schema) {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection)
        }
    }
    else {
        Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
        return
    }
    return $dbUp
}