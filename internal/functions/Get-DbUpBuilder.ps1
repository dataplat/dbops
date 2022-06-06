function Get-DbUpBuilder {
    # Returns a DbUp builder with a proper connection object
    Param (
        [Parameter(Mandatory)]
        [object]$Connection,
        [string]$Schema,
        [object[]]$Script,
        [object]$Config,
        [DBOps.ConnectionType]$Type,
        [bool]$ChecksumValidation = $false
    )
    $dbUp = [DbUp.DeployChanges]::To
    if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
        if ($Schema) {
            $dbUp = [DBOps.SqlServer.SqlServerExtensions]::SqlDatabase($dbUp, $Connection, $Schema)
        }
        else {
            $dbUp = [DBOps.SqlServer.SqlServerExtensions]::SqlDatabase($dbUp, $Connection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::Oracle) {
        if ($Schema) {
            $dbUp = [DBOps.Oracle.OracleExtensions]::OracleDatabase($dbUp, $Connection, $Schema)
        }
        else {
            $dbUp = [DBOps.Oracle.OracleExtensions]::OracleDatabase($dbUp, $Connection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::MySQL) {
        if ($Schema) {
            $dbUp = [DBOps.MySql.MySqlExtensions]::MySqlDatabase($dbUp, $Connection, $Schema)
        }
        else {
            $dbUp = [DBOps.MySql.MySqlExtensions]::MySqlDatabase($dbUp, $Connection)
        }
    }
    elseif ($Type -eq [DBOps.ConnectionType]::PostgreSQL) {
        if ($Schema) {
            $dbUp = [DBOps.Postgresql.PostgresqlExtensions]::PostgresqlDatabase($dbUp, $Connection, $Schema)
        }
        else {
            $dbUp = [DBOps.Postgresql.PostgresqlExtensions]::PostgresqlDatabase($dbUp, $Connection)
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

    if ($ChecksumValidation) {
        # Enable checksum validation
        $dbUp.Configure({Param($c) $c.ScriptFilter = [DBOps.ChecksumValidatingScriptFilter]::new()})
    }
    return $dbUp
}