function Get-ConnectionString {
    # Returns a connection string based on a config object
    Param (
        [DBOpsConfig]$Configuration,
        [DBOps.ConnectionType]$Type
    )
    #Build connection string
    if (!$Configuration.ConnectionString) {
        $CSBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
        $CSBuilder["Server"] = $Configuration.SqlInstance
        if ($Configuration.Database) { $CSBuilder["Database"] = $Configuration.Database }
        if ($Configuration.Encrypt) { $CSBuilder["Encrypt"] = $true }
        $CSBuilder["Connection Timeout"] = $Configuration.ConnectionTimeout

        if ($Configuration.Credential) {
            $CSBuilder["User ID"] = $Configuration.Credential.UserName
            $CSBuilder["Password"] = $Configuration.Credential.GetNetworkCredential().Password
        }
        elseif ($Configuration.Username) {
            if ($Password) {
                $currentCred = [pscredential]::new($Configuration.Username, $Password)
            }
            else {
                $currentCred = [pscredential]::new($Configuration.Username, $Configuration.Password)
            }
            $CSBuilder["User ID"] = $currentCred.UserName
            $CSBuilder["Password"] = $currentCred.GetNetworkCredential().Password
        }
        else {
            $CSBuilder["Integrated Security"] = $true
        }
        if ($Type -eq 'SQLServer') {
            $CSBuilder["Application Name"] = $Configuration.ApplicationName
        }
        return $CSBuilder.ToString()
    }
    else {
        return $Configuration.ConnectionString
    }
}