function Get-DbUpJournal {
    # Returns a DbUp builder with a proper connection object
    Param (
        [Parameter(Mandatory)]
        [scriptblock]$Connection,
        [scriptblock]$Log,
        [string]$Schema,
        [string]$SchemaVersionTable,
        [Parameter(Mandatory)]
        [DBOps.ConnectionType]$Type,
        [bool]$ChecksumValidation = $false
    )
    $journalMap = @{
        $false = @{
            [DBOps.ConnectionType]::SQLServer = [DBOps.SqlServer.SqlTableJournal]
            [DBOps.ConnectionType]::Oracle = [DBOps.Oracle.OracleTableJournal]
            [DBOps.ConnectionType]::MySQL = [DBOps.MySql.MySqlTableJournal]
            [DBOps.ConnectionType]::PostgreSQL = [DBOps.Postgresql.PostgresqlTableJournal]
        }
        $true = @{
            [DBOps.ConnectionType]::SQLServer = [DBOps.SqlServer.SqlChecksumValidatingJournal]
            [DBOps.ConnectionType]::Oracle = [DBOps.Oracle.OracleChecksumValidatingJournal]
            [DBOps.ConnectionType]::MySQL = [DBOps.MySql.MySqlChecksumValidatingJournal]
            [DBOps.ConnectionType]::PostgreSQL = [DBOps.Postgresql.PostgresqlChecksumValidatingJournal]
        }
    }
    if ($SchemaVersionTable) {
        # retrieve schema and table names
        $table = $SchemaVersionTable.Split('.')
        if ($table.Count -gt 2) {
            Stop-PSFFunction -EnableException $true -Message 'Incorrect table name - use the following syntax: schema.table'
            return
        }
        elseif ($table.Count -eq 2) {
            $tableName = $table[1]
            $schemaName = $table[0]
        }
        else {
            $tableName = $table[0]
            if ($Schema) {
                $schemaName = $Schema
            }
        }
        if ($Type -eq [DBOps.ConnectionType]::SQLServer) {
            if (!$schemaName) {
                $schemaName = 'dbo'
            }
        }
        $dbUpJournalType = $journalMap[$ChecksumValidation][$Type]
        if (-not $dbUpJournalType) {
            Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
            return
        }
        # return a journal object
        Write-PSFMessage -Level Debug -Message "Using journal $($dbUpJournalType.GetType().Name) for $Type with name $schemaName.$tableName"
        return $dbUpJournalType::new($Connection, $Log, $schemaName, $tableName)
    }
    else {
        # return a null journal to disable journalling
        return [DbUp.Helpers.NullJournal]::new()
    }
}