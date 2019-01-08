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
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $ConnectionString, $Log, $Timeout)
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        $dbUp = [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $ConnectionString, $Log, $Timeout)
    }
    else {
        Stop-PSFFunction -Message "Creating databases in $Type is not supported" -EnableException $false
    }
    return $dbUp
}