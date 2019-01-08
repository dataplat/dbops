[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
[CmdletBinding(SupportsShouldProcess)]
Param (
    [Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
    [string]$SqlInstance,
    [string]$Database,
    [ValidateSet('SingleTransaction', 'TransactionPerScript', 'NoTransaction')]
    [string]$DeploymentMethod = 'NoTransaction',
    [int]$ConnectionTimeout,
    [int]$ExecutionTimeout,
    [switch]$Encrypt,
    [pscredential]$Credential,
    [string]$UserName,
    [securestring]$Password,
    [AllowNull()]
    [string]$SchemaVersionTable,
    [switch]$Silent,
    [Alias('ArgumentList')]
    [hashtable]$Variables,
    [string]$OutputFile,
    [switch]$Append,
    [Alias('Config')]
    [object]$Configuration,
    [string[]]$Build,
    [string]$Schema,
    [switch]$CreateDatabase,
    [AllowNull()]
    [string]$ConnectionString,
    [ValidateSet('SQLServer', 'Oracle')]
    [Alias('Type', 'ServerType')]
    [string]$ConnectionType = 'SQLServer'
)

#Import module
If (-not (Get-Module dbops)) {
    Import-Module "$PSScriptRoot\Modules\dbops\dbops.psd1"
}
. "$PSScriptRoot\Modules\dbops\internal\classes\DBOps.enums.ps1"

$config = Get-DBOConfig -Path "$PSScriptRoot\dbops.config.json" -Configuration $Configuration

#Convert custom parameters into a package configuration, excluding variables
foreach ($key in ($PSBoundParameters.Keys)) {
    if ($key -in [DBOps.ConfigProperty].GetEnumNames() -and $key -ne 'Variables') {
        Write-PSFMessage -Level Debug -Message "Overriding parameter $key with $($PSBoundParameters[$key])"
        $config.SetValue($key, $PSBoundParameters[$key])
    }
}

#Prepare deployment function call parameters
$params = @{
    PackageFile = "$PSScriptRoot\dbops.package.json"
    Configuration = $config
}
foreach ($key in ($PSBoundParameters.Keys)) {
    #If any custom properties were specified
    if ($key -in @('OutputFile', 'Append', 'Variables', 'ConnectionType', 'Build')) {
        $params += @{ $key = $PSBoundParameters[$key] }
    }
}

if ($PSCmdlet.ShouldProcess($params.PackageFile, "Initiating the deployment of the package")) {
    Invoke-DBODeployment @params
}
else {
    Invoke-DBODeployment @params -WhatIf
}

