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
    [ValidateSet('SqlServer', 'Oracle', 'MySQL', 'PostgreSQL')]
    [Alias('ConnectionType', 'ServerType')]
    [string]$Type = 'SQLServer'
)

#Import modules
foreach ($module in @('PSFramework', 'dbops')) {
    if (-not (Get-Module $module)) {
        Import-Module "$PSScriptRoot\Modules\$module"
    }
}

$config = Get-DBOConfig -Path "$PSScriptRoot\dbops.config.json" -Configuration $Configuration

#Merge custom parameters into a configuration
$newConfig = @{}
foreach ($key in ($PSBoundParameters.Keys)) {
    if ($key -in [DBOps.ConfigProperty].GetEnumNames()) {
        $newConfig.$key = $PSBoundParameters[$key]
    }
}
$config.Merge($newConfig)

#Prepare deployment function call parameters
$params = @{
    PackageFile   = "$PSScriptRoot\dbops.package.json"
    Configuration = $config
}
foreach ($key in ($PSBoundParameters.Keys)) {
    #If any custom properties were specified
    if ($key -in @('OutputFile', 'Append', 'Type', 'Build')) {
        $params += @{ $key = $PSBoundParameters[$key] }
    }
}

if ($PSCmdlet.ShouldProcess($params.PackageFile, "Initiating the deployment of the package")) {
    Invoke-DBODeployment @params
}
else {
    Invoke-DBODeployment @params -WhatIf
}

