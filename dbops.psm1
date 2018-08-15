Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$moduleCatalog = Get-Content "$PSScriptRoot\internal\json\dbops.json" -Raw | ConvertFrom-Json
foreach ($bin in $moduleCatalog.Libraries) {
	Unblock-File -Path "$PSScriptRoot\$bin" -ErrorAction SilentlyContinue
	Add-Type -Path "$PSScriptRoot\$bin"
}

foreach ($function in $moduleCatalog.Functions) {
	. "$PSScriptRoot\$function"
}

foreach ($function in $moduleCatalog.Internal) {
	. "$PSScriptRoot\$function"
}

# defining validations

Register-PSFConfigValidation -Name "transaction" -ScriptBlock {
    Param (
        $Value
    )
	
    $Result = New-Object PSOBject -Property @{
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
	
    $Result = New-Object PSOBject -Property @{
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
	
    $Result = New-Object PSOBject -Property @{
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

# defining aliases

New-Alias -Name Write-Message -Value Write-PSFMessage
New-Alias -Name Stop-Function -Value Stop-PSFFunction