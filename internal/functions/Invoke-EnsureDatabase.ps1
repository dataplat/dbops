function Invoke-EnsureDatabase {
    # Creates a database if missing based on the connection string
    Param (
        [Parameter(Mandatory)]
        [string]$ConnectionString,
        [DbUp.Engine.Output.IUpgradeLog]$Log,
        [int]$Timeout,
        [DBOps.ConnectionType]$Type
    )
    $dbUp = [DbUp.EnsureDatabase]::For
    $dbUp = switch ($Type) {
        SqlServer { [SqlServerExtensions]::SqlDatabase($dbUp, $ConnectionString, $Log, $Timeout) }
        MySQL { [DBOps.MySql.MySqlExtensions]::MySqlDatabase($dbUp, $ConnectionString, $Log) }
        PostgreSQL { [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $ConnectionString, $Log) }
        default { Stop-PSFFunction -Message "Creating databases in $Type is not supported" -EnableException $false }
    }
    return $dbUp
}