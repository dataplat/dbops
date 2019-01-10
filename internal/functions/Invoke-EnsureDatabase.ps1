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
            $csBuilder.Database = 'sys'
            $dbExistsQuery = "SELECT SCHEMA_NAME AS 'Database' FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$targetDB'"
            try {
                $dbExists = Invoke-DBOQuery -Type $Type -ConnectionString $csBuilder -Query $dbExistsQuery
            }
            catch {
                $Log.WriteError("Unable to check database existance on {0}: {1}", @($csBuilder.Server, $csBuilder.Database));
                throw $_
            }
            if (-not $dbExists.Database) {
                $query = 'CREATE DATABASE `{0}`' -f $targetDB
                try {
                    $null = Invoke-DBOQuery -Type $Type -ConnectionString $csBuilder -Query $query
                }
                catch {
                    $Log.WriteError("Unable to create database {0} on {1}", @($csBuilder.Database, $csBuilder.Server));
                    throw $_
                }
                $Log.WriteInformation("Created database {0}", $targetDB)
            }
        }
        PostgreSQL { [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $ConnectionString, $Log) }
        default { Stop-PSFFunction -Message "Creating databases in $Type is not supported" -EnableException $false }
    }
    return $dbUp
}