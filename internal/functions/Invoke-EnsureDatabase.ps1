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
        MySQL {
            # not natively supported in DbUp just yet
            $csBuilder = Get-ConnectionString -ConnectionString $ConnectionString -Type $Type -Raw
            if (-not $csBuilder.Database) {
                Stop-PSFFunction -Message "Database name was not provided in order to support automatic database creation" -EnableException $false
                return
            }
            $query = "CREATE DATABASE IF NOT EXISTS $($csBuilder.Database)"
            $null = Invoke-DBOQuery -Type $Type -ConnectionString $ConnectionString -Query $query
        }
        PostgreSQL { [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $ConnectionString, $Log)
        default { Stop-PSFFunction -Message "Creating databases in $Type is not supported" -EnableException $false }
    }
    return $dbUp
}