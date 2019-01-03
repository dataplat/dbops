function Get-ConnectionManager {
    # Returns a connection manager object
    Param (
        [Parameter(ParameterSetName = 'ConnString', Mandatory)]
        [string]$ConnectionString,
        [Parameter(ParameterSetName = 'Config', Mandatory)]
        [DBOpsConfig]$Configuration,
        [DBOps.ConnectionType]$Type
    )
    if ($Configuration) {
        $ConnectionString = Get-ConnectionString -Configuration $Configuration -Type $Type
    }
    if ($Type -eq 'SqlServer') {
        return [DbUp.SqlServer.SqlConnectionManager]::new($ConnectionString)
    }
    elseif ($Type -eq 'Oracle') {
        return [DbUp.Oracle.OracleConnectionManager]::new($ConnectionString)
    }
}