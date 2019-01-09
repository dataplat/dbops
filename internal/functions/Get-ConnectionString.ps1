function Get-ConnectionString {
    # Returns a connection string based on a config object
    Param (
        [Parameter(ParameterSetName = 'Configuration')]
        [DBOpsConfig]$Configuration,
        [Parameter(ParameterSetName = 'ConnString')]
        [string]$ConnectionString
        [DBOps.ConnectionType]$Type,
        [switch]$Raw
    )
    # find proper builder type
    $builderType = switch ($Type) {
        SqlServer { [System.Data.SqlClient.SqlConnectionStringBuilder] }
        PostgreSQL { [Npgsql.NpgsqlConnectionStringBuilder] }
        Oracle { [Oracle.ManagedDataAccess.Client.OracleConnectionStringBuilder] }
        MySQL { [MySql.Data.MySqlClient.MySqlConnectionStringBuilder] }
    }
    # Build connection string
    if ($Configuration -and -not $Configuration.ConnectionString) {
        $csBuilder = $builderType::new()
        # finding all the right connection string properties
        $conn = @{}
        foreach ($key in 'Server', 'Data Source') {
            if ($csBuilder.ContainsKey($key)) { $conn.Server = $key; break }
        }
        if (-not $conn.Server) {
            Stop-PSFFunction -Message "Failed to find a Server property in the connection string object" -EnableException $true
        }

        foreach ($key in 'Connection Timeout', 'Timeout') {
            if ($csBuilder.ContainsKey($key)) { $conn.ConnectionTimeout = $key; break }
        }
        if (-not $conn.ConnectionTimeout) {
            Stop-PSFFunction -Message "Failed to find a Timeout property in the connection string object" -EnableException $true
        }

        # support for servername:port and trimming
        if ($Configuration.SqlInstance -match '^\s*(.+)[:|,]\s*(\d+)\s*$') {
            $server = $Matches[1]
            $port = $Matches[2]
        }
        else {
            $server = $Configuration.SqlInstance
            $port = $null
        }
        $csBuilder[$conn.Server] = $server
        # check if port is an independent property and set it, otherwise add the port back to the connection string
        if ($port) {
            if ($csBuilder.ContainsKey('Port')) {
                $csBuilder.Port = $port
            }
            else {
                if ($Type -eq [DBOps.ConnectionType]::SqlServer) {
                    $csBuilder[$conn.Server] += ",$port"
                }
                else {
                    $csBuilder[$conn.Server] += ":$port"
                }
            }
        }

        if ($Configuration.Database -and $csBuilder.ContainsKey('Database')) { $csBuilder["Database"] = $Configuration.Database }
        if ($Configuration.Encrypt -and $csBuilder.ContainsKey('Encrypt')) { $csBuilder["Encrypt"] = $true }
        if ($Configuration.ApplicationName -and $csBuilder.ContainsKey('Application Name')) { $csBuilder["Application Name"] = $Configuration.ApplicationName }
        if ($Configuration.ExecutionTimeout -and $csBuilder.ContainsKey('Command Timeout')) { $csBuilder["Command Timeout"] = $Configuration.ExecutionTimeout }
        $csBuilder[$conn.ConnectionTimeout] = $Configuration.ConnectionTimeout
        # define authentication
        if ($Configuration.Credential) {
            $csBuilder["User ID"] = $Configuration.Credential.UserName
            $csBuilder["Password"] = $Configuration.Credential.GetNetworkCredential().Password
        }
        elseif ($Configuration.Username) {
            $csBuilder["User ID"] = $Configuration.UserName
            if ($Configuration.Password) {
                $currentCred = [pscredential]::new($Configuration.Username, $Configuration.Password)
                $csBuilder["Password"] = $currentCred.GetNetworkCredential().Password
            }
        }
        else {
            if ($csBuilder.ContainsKey('Integrated Security')) {
                $csBuilder["Integrated Security"] = $true
            }
        }
    }
    elseif ($Configuration) {
        $csBuilder = $builderType::new($Configuration.ConnectionString)
    }
    else {
        $csBuilder = $builderType::new($ConnectionString)
    }
    # generate the connection string
    if ($Raw) {
        return $csBuilder
    }
    else {
        $connString = $csBuilder.ToString()
        $maskedString = $builderType::new($connString)
        $maskedString.Password = '********'
        Write-PSFMessage -Level Debug -Message "Generated connection string $maskedString"
        return $connString
    }
}