Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. $PSScriptRoot\functions\Get-DBOModuleFileList.ps1
foreach ($bin in (Get-DBOModuleFileList -Type Libraries -Edition $PSVersionTable.PSEdition).FullName) {
    if ($PSVersionTable.Platform -eq 'Win32NT') {
        Unblock-File -Path $bin -ErrorAction SilentlyContinue
    }
    Add-Type -Path $bin
}

'Functions', 'Internal' | ForEach-Object {
    foreach ($function in (Get-DBOModuleFileList -Type $_).FullName) {
        . $function
    }
}

# defining validations

Register-PSFConfigValidation -Name "transaction" -ScriptBlock {
    Param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if (([string]$Value) -in @('SingleTransaction', 'TransactionPerScript', 'NoTransaction')) {
            $Result.Value = [string]$Value
        }
        else {
            $Result.Message = "Allowed values: SingleTransaction, TransactionPerScript, NoTransaction"
            $Result.Success = $False
        }
    }
    catch {
        $Result.Message = "Failed to convert value to string"
        $Result.Success = $False
    }

    return $Result
}

Register-PSFConfigValidation -Name "securestring" -ScriptBlock {
    Param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    if ($Value -is [securestring]) {
        $Result.Value = $Value
    }
    else {
        $Result.Message = 'Only [securestring] is accepted'
        $Result.Success = $False
    }
    return $Result
}

Register-PSFConfigValidation -Name "hashtable" -ScriptBlock {
    Param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if (([hashtable]$Value) -is [hashtable]) {
            $Result.Value = [hashtable]$Value
        }
        else {
            $Result.Message = "Only hashtables are allowed"
            $Result.Success = $False
        }
    }
    catch {
        $Result.Message = "Failed to convert value to hashtable. Only hashtables are allowed."
        $Result.Success = $False
    }
    return $Result
}

Register-PSFConfigValidation -Name "connectionType" -ScriptBlock {
    Param (
        $Value
    )
    $allowedTypes = [DBOps.ConnectionType].GetEnumNames()
    $failMessage = "Only the following values are allowed: $($allowedTypes -join ', ')"
    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if (([string]$Value) -is [string] -and [string]$Value -in $allowedTypes) {
            $Result.Value = [string]$Value
        }
        else {
            $Result.Message = $failMessage
            $Result.Success = $False
        }
    }
    catch {
        $Result.Message = "Failed to convert value to string. $failMessage"
        $Result.Success = $False
    }
    return $Result
}

Register-PSFConfigValidation -Name "tokenRegex" -ScriptBlock {
    Param (
        $Value
    )
    $failMessage = "Should contain capture group (token)"
    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if (([string]$Value) -is [string] -and [string]$Value -like '*(token)*') {
            $Result.Value = [string]$Value
        }
        else {
            $Result.Message = $failMessage
            $Result.Success = $False
        }
    }
    catch {
        $Result.Message = "Failed to convert value to string. $failMessage"
        $Result.Success = $False
    }
    return $Result
}

# defining defaults

Set-PSFConfig -FullName dbops.ApplicationName -Value "dbops" -Initialize -Description "Application name in the connection string"
Set-PSFConfig -FullName dbops.SqlInstance -Value "localhost" -Initialize -Description "Server to connect to"
Set-PSFConfig -FullName dbops.Database -Value $null -Initialize -Description "Name of the database for deployment"
Set-PSFConfig -FullName dbops.DeploymentMethod -Value 'NoTransaction' -Initialize -Validation transaction `
    -Description "Transactional behavior during deployment. Allowed values: SingleTransaction, TransactionPerScript, NoTransaction (default)"
Set-PSFConfig -FullName dbops.Username -Value $null -Initialize -Description "Connection username"
Set-PSFConfig -FullName dbops.Password -Value $null -Initialize -Validation securestring `
    -Description "Connection password. Only available to the same OS user, as it will be encrypted"
Set-PSFConfig -FullName dbops.SchemaVersionTable -Value 'SchemaVersions' -Initialize -Description "Name of the table where the schema deployment history will be stored"
Set-PSFConfig -FullName dbops.Schema -Value $null -Initialize -Description "Schema name to use by default. Not applicable to some RDBMS."
Set-PSFConfig -FullName dbops.ConnectionTimeout -Value 30 -Initialize -Validation integerpositive -Description "Connection attempt timeout in seconds. 0 to wait indefinitely."
Set-PSFConfig -FullName dbops.ExecutionTimeout -Value 0 -Initialize -Validation integerpositive -Description "Script execution timeout in seconds. 0 to wait indefinitely."
Set-PSFConfig -FullName dbops.Encrypt -Value $false -Initialize -Validation bool -Description "Encrypt connection if supported by the driver."
Set-PSFConfig -FullName dbops.Silent -Value $false -Initialize -Validation bool -Description "Silent execution with no output to the console."
Set-PSFConfig -FullName dbops.Credential -Value $null -Initialize -Description "Database credentials to authenticate with."
Set-PSFConfig -FullName dbops.Variables -Value $null -Initialize -Validation hashtable -Description "A hashtable with key/value pairs representing #{variables} that will be swapped during execution."
Set-PSFConfig -FullName dbops.ConnectionString -Value $null -Initialize -Description "Connection string to the target database. If specified, overrides SqlInstance and Database parameters."
Set-PSFConfig -FullName dbops.ConnectionAttribute -Value $null -Validation hashtable -Initialize -Description "Additional connection string parameters. Existing connection string will be augmented."
Set-PSFConfig -FullName dbops.CreateDatabase -Value $false -Validation bool -Initialize -Description "Determines whether to create an empty database upon deployment if it haven't been created yet."
Set-PSFConfig -FullName dbops.mail.Template -Value "bin\mail_template.htm" -Initialize -Description "Relative or absolute path to the email template file."
Set-PSFConfig -FullName dbops.mail.SmtpServer -Value "" -Initialize -Description "Smtp server address."
Set-PSFConfig -FullName dbops.mail.From -Value "" -Initialize -Description "'From' field in the outgoing emails."
Set-PSFConfig -FullName dbops.mail.To -Value "" -Initialize -Description "'To' field in the outgoing emails."
Set-PSFConfig -FullName dbops.mail.Subject -Value "DBOps deployment status" -Initialize -Description "'Subject' field in the outgoing emails."
Set-PSFConfig -FullName dbops.security.encryptionkey -Value "~/.dbops.key" -Initialize -Description "Path to a custom encryption key used to encrypt/decrypt passwords. The key should be a binary file with a length of 128, 192 or 256 bits. Key will be generated automatically if not exists."
Set-PSFConfig -FullName dbops.security.usecustomencryptionkey -Value ($PSVersionTable.Platform -eq 'Unix') -Validation bool -Initialize -Description "Determines whether to use a custom encryption key for storing passwords. Enabled by default only on Unix platforms."
Set-PSFConfig -FullName dbops.rdbms.type -Value 'SqlServer' -Validation connectionType -Initialize -Description "Assumes a certain RDBMS as a default one for each command. SQLServer by default"
Set-PSFConfig -FullName dbops.package.slim -Value $false -Validation bool -Initialize -Description "Decides whether to make the packages 'slim' and omit module files when creating the package. Default: `$false"
Set-PSFConfig -FullName dbops.config.variabletoken -Value "\#\{(token)\}" -Validation tokenRegex -Initialize -Description "Variable replacement token. Regex string that will be replaced with values from -Variables parameters. Default: \#\{(token)\}"

# extensions for SMO
$typeData = Get-TypeData -TypeName 'Microsoft.SqlServer.Management.Smo.Database'
if ($typeData) {
    if (!$typeData.Members.ContainsKey('Deploy')) {
        Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Deploy -MemberType ScriptMethod -Value {
            param (
                $Package
            )
            $cS = $this.ExecutionManager.ConnectionContext.ConnectionString.Split(';') | Where-Object { $_.Split('=')[0] -ne 'Database' }
            $cS += "Database=$($this.Name)"
            $connectionString = $cS -join ';'
            Install-DBOPackage -InputObject $Package -ConnectionString $connectionString
        } -ErrorAction Ignore
    }
    if (!$typeData.Members.ContainsKey('DeployScript')) {
        Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName DeployScript -MemberType ScriptMethod -Value {
            param (
                $Path
            )
            $cS = $this.ExecutionManager.ConnectionContext.ConnectionString.Split(';') | Where-Object { $_.Split('=')[0] -ne 'Database' }
            $cS += "Database=$($this.Name)"
            $connectionString = $cS -join ';'
            Install-DBOSqlScript -ScriptPath $Path -ConnectionString $connectionString
        } -ErrorAction Ignore
    }
}

# Aliases

$aliases = @(
    @{
        "AliasName"  = "Install-DBOSqlScript"
        "Definition" = "Install-DBOScript"
    }
)
$aliases | ForEach-Object {
    if (-not (Test-Path Alias:$($_.AliasName))) { Set-Alias -Scope Global -Name $($_.AliasName) -Value $($_.Definition) }
}