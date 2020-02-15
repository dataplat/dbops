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
#Open package from the current folder
$package = Get-DBOPackage -Path $PSScriptRoot -Unpacked
#Merge configuration if provided
if ($Configuration) {
    $package.Configuration.Merge($Configuration)
}

#Merge custom parameters into a configuration
$newConfig = @{ }
foreach ($key in ($PSBoundParameters.Keys)) {
    if ($key -in [DBOps.ConfigProperty].GetEnumNames()) {
        $newConfig.$key = $PSBoundParameters[$key]
    }
}
$package.Configuration.Merge($newConfig)

#Prepare deployment function call parameters
$params = @{
    InputObject = $package
}
foreach ($key in ($PSBoundParameters.Keys)) {
    #If any custom properties were specified
    if ($key -in @('OutputFile', 'Append', 'Type', 'Build')) {
        $params += @{ $key = $PSBoundParameters[$key] }
    }
}

if ($PSCmdlet.ShouldProcess($params.PackageFile, "Initiating the deployment of the package")) {
    Install-DBOPackage @params
}
else {
    Install-DBOPackage @params -WhatIf
}

