<#
	.SYNOPSIS
		Creates a new deployment package from a specified set of scripts
	
	.DESCRIPTION
		Creates a new zip package which would contain a set of deployment scripts.
		Deploy.ps1 inside the package will initiate the deployment of the extracted package.
		Can be created with predefined parameters, which would allow for deployments without specifying additional info.
	
	.PARAMETER ScriptPath
		A collection of script files to add to the build. Accepts Get-Item/Get-ChildItem objects and wildcards.
		Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
		During deployment, scripts will be following this deployment order:
		 - Item order provided in the ScriptPath parameter
		   - Files inside each child folder (both folders and files in alphabetical order)
			 - Files inside the root folder (in alphabetical order)
			 
		Aliases: SourcePath
	
	.PARAMETER Path
		Package file name. Will add '.zip' extention, if no extension is specified

		Aliases: Name, FileName, Package
	
	.PARAMETER Build
		A string that would be representing a build number of the first build in this package. 
		A single package can span multiple builds - see Add-DBOBuild.
		Optional - can be genarated automatically.
		Can only contain characters that will be valid on the filesystem.
	
	.PARAMETER Force
		Replaces the target file specified in -Path if it already exists.
	
	.PARAMETER ConfigurationFile
		A path to the custom configuration json file
	
	.PARAMETER Configuration
		Hashtable containing necessary configuration items. Will override parameters in ConfigurationFile

	.PARAMETER Variables
		Hashtable with variables that can be used inside the scripts and deployment parameters.
		Proper format of the variable tokens is #{MyVariableName}
		Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
	
	.PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
		# Creates new package using files from .\Scripts\2.0. Initial build version will be 2.0
		New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts\2.0 -Build 2.0

	.EXAMPLE
		# Creates new package using files from .\Scripts\2.0. Destination file will be overwritten.
		Get-ChildItem .\Scripts\2.0 | New-DBOPackage -Path MyPackage.zip -Build 1.0 -Force

	.EXAMPLE
		# Creates new package and applies custom configuration template to it
		New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts -ConfigurationFile .\config.json
	
	.EXAMPLE
		# Creates new package and uses predefined configuration parameters
		New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts -Configuration @{ Database = 'myDB'; ConnectionTimeout = 5 }
#>
function New-DBOPackage {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param
	(
		[Parameter(Mandatory = $false,
			Position = 1)]
		[Alias('FileName', 'Name', 'Package')]
		[string]$Path = (Split-Path (Get-Location) -Leaf),
		[Parameter(Mandatory = $true,
			ValueFromPipeline = $true,
			Position = 2)]
		[Alias('SourcePath')]
		[object[]]$ScriptPath,
		[string]$Build,
		[switch]$Force,
		[Alias('Config')]
		[hashtable]$Configuration,
		[Alias('ConfigFile')]
		[string]$ConfigurationFile,
		[hashtable]$Variables
	)
	
	begin {
		#Set package extension if there is none
		$packagePath = $Path
		$fileName = Split-Path $packagePath -Leaf
		if ($fileName.IndexOf('.') -eq -1) {
			$packagePath = "$packagePath.zip"
		}
		
		#Combine Variables and Configuration into a single object
		$configTable = $Configuration
		if ($Variables) { 
			if ($configTable) {
				$configTable.Remove('Variables')
			}
			$configTable += @{ Variables = $Variables } 
		}
		
		#Create a package object
		$package = [DBOpsPackage]::new()

		#Get configuration object according to current config options
		$package.SetConfiguration((Get-DBOConfig -Path $ConfigurationFile -Configuration $configTable))
		
		#Create new build
		if ($Build) {
			$buildNumber = $Build
		}
		else {
			$buildNumber = Get-NewBuildNumber
		}
		
		$scriptCollection = @()
	}
	process {
		$scriptCollection += $ScriptPath
	}
	end {
		#Create a new build
		$buildObject = $package.NewBuild($buildNumber)
		foreach ($scriptItem in $scriptCollection) {
			$null = $buildObject.NewScript((Get-ChildScriptItem $scriptItem))
		}

		if ($pscmdlet.ShouldProcess($package, "Generate a package file")) {
			
			#Save package file
			$package.SaveToFile($packagePath, $Force)

			#Output the package object
			$package
		}
		
	}
}
