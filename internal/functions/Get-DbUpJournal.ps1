function Get-DbUpJournal {
    # Returns a DbUp builder with a proper connection object
    Param (
        [Parameter(Mandatory)]
        [scriptblock]$Connection,
        [scriptblock]$Log,
        [string]$Schema,
        [string]$SchemaVersionTable,
        [Parameter(Mandatory)]
        [DBOps.ConnectionType]$Type
    )
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
        # define journal type based on target connection type
        if ($Type -eq [DBOps.ConnectionType]::SQLServer) {
            if (!$schemaName) {
                $schemaName = 'dbo'
            }
            $dbUpJournalType = [DBOps.Extensions.SqlTableJournal]
        }
        elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
            $dbUpJournalType = [DbUp.Oracle.OracleTableJournal]
        }
        elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
            $dbUpJournalType = [DBOpsMySqlTableJournal]
        }
        elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
            $dbUpJournalType = [DBOps.Extensions.PostgresqlTableJournal]
        }
        else {
            Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
            return
        }
        # return a journal object
        Write-PSFMessage -Level Verbose -Message "Creating journal object for $Type in $schemaName.$tableName"
        return $dbUpJournalType::new($Connection, $Log, $schemaName, $tableName)
    }
    else {
        # return a null journal to disable journalling
        return [DbUp.Helpers.NullJournal]::new()
    }
}