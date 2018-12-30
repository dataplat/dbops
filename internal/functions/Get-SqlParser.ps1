function Get-SqlParser {
    # Returns a Sql parser object for a specific RDBMS
    Param (
        [Parameter(Mandatory)]
        [string]$Type
    )
    if ($Type -eq 'SqlServer') {
        return [DbUp.SqlServer.SqlServerObjectParser]::new()
    }
    elseif ($Type -eq 'Oracle') {
        return [DbUp.Oracle.OracleObjectParser]::new()
    }
}