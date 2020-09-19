function Get-DbUpBuilder {
    # Returns a DbUp builder with a proper connection object
    Param (
        [Parameter(Mandatory)]
        [object]$Connection,
        [string]$Schema,
        [object[]]$Script,
        [object]$Config,
        [DBOps.ConnectionType]$Type
    )
    $dbUp = [DbUp.DeployChanges]::To
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        if ($Schema) {
            $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection)
            $dbUp.Configure({ param($c); $c.ScriptExecutor = [DBOps.Extensions.SqlScriptExecutor]::new({ $c.ConnectionManager }, { $c.Log }, $Schema, { $c.VariablesEnabled }, $c.ScriptPreprocessors, { $c.Journal }) })
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
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        if ($Schema) {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        if ($Schema) {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [MySqlExtensions]::MySqlDatabase($dbUp, $dbUpConnection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        if ($Schema) {
            $dbUp = [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $dbUpConnection, $Schema)
        }
        else {
            $dbUp = [PostgresqlExtensions]::PostgresqlDatabase($dbUp, $dbUpConnection)
        }
    }
    else {
        Stop-PSFFunction -Message "Unknown type $Type" -EnableException $true
        return
    }
    # Add deployment scripts to the object
    $dbUp = [StandardExtensions]::WithScripts($dbUp, $Script)

    # Disable automatic sorting by using a custom comparer
    $comparer = [DBOpsScriptComparer]::new($Script.Name)
    $dbUp = [StandardExtensions]::WithScriptNameComparer($dbUp, $comparer)

    # Disable variable replacement
    $dbUp = [StandardExtensions]::WithVariablesDisabled($dbUp)

    # Transaction handling
    if ($Config.DeploymentMethod -eq 'SingleTransaction') {
        $dbUp = [StandardExtensions]::WithTransaction($dbUp)
    }
    elseif ($Config.DeploymentMethod -eq 'TransactionPerScript') {
        $dbUp = [StandardExtensions]::WithTransactionPerScript($dbUp)
    }
    # Adding execution timeout - defaults to unlimited execution
    $dbUp = [StandardExtensions]::WithExecutionTimeout($dbUp, [timespan]::FromSeconds($config.ExecutionTimeout))
    return $dbUp
}