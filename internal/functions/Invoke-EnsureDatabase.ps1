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
            $targetDB = $csBuilder.Database
            $csBuilder.Database = 'mysql'
            $dbExistsQuery = "SELECT SCHEMA_NAME AS 'Database' FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$targetDB'"
            $dbExists = Invoke-DBOQuery -Type $Type -ConnectionString $csBuilder -Query $dbExistsQuery
            if (-not $dbExists.Database) {
                $query = 'CREATE DATABASE `{0}`' -f $targetDB
                $null = Invoke-DBOQuery -Type $Type -ConnectionString $csBuilder -Query $query
                $Log.WriteInformation("Created database {0}", $targetDB)
            }
        }
        PostgreSQL { [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $ConnectionString, $Log) }
        default { Stop-PSFFunction -Message "Creating databases in $Type is not supported" -EnableException $false }
    }
    return $dbUp
}