[CmdletBinding()]
Param (
	[string]$SqlInstance,
	[string]$Database,
	[ValidateSet('SingleTransaction', 'TransactionPerScript', 'NoTransaction')]
	[string]$DeploymentMethod = 'NoTransaction',
	[int]$ConnectionTimeout,
	[switch]$Encrypt,
	[pscredential]$Credential,
	[string]$UserName,
	[securestring]$Password,
	[string]$LogToTable,
	[switch]$Silent,
	[hashtable]$Variables
)

#Stop on error
#$ErrorActionPreference = 'Stop'

#Import module
If (Get-Module dbops) {
	Remove-Module dbops
}
Import-Module "$PSScriptRoot\Modules\dbops\dbops.psd1" -Force

#Invoke deployment using current parameters
$params = $PSBoundParameters
$params += @{ PackageFile = "$PSScriptRoot\dbops.package.json"}
Invoke-DBODeployment @params

