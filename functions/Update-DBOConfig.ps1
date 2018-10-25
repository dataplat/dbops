function Update-DBOConfig {
    <#
    .SYNOPSIS
    Updates configuration file inside the existing DBOps package
    
    .DESCRIPTION
    Overwrites configuration file inside the existing DBOps package with the new values provided by user
    
    .PARAMETER Path
    Path to the existing DBOpsPackage.
    Aliases: Name, FileName, Package
    
    .PARAMETER ConfigurationFile
    A path to the custom configuration json file
    Alias: ConfigFile
    
    .PARAMETER Configuration
    Object containing several configuration items at once
    Alias: Config
    
    .PARAMETER ConfigName
    Name of the configuration item to update
    
    .PARAMETER Value
    Value of the parameter specified in -ConfigName

    .PARAMETER Variables
    Hashtable with variables that can be used inside the scripts and deployment parameters.
    Proper format of the variable tokens is #{MyVariableName}
    Can also be provided as a part of Configuration Object: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
    
    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Update a single parameter in the configuration file of the Package.zip package
    Update-DBOConfig Package.zip -ConfigName ApplicationName -Value 'MyApp'

    .EXAMPLE
    # Update several configuration parameters at once using a hashtable
    Update-DBOConfig Package.zip -Configuration @{'ApplicationName' = 'MyApp'; 'Database' = 'MyDB'}

    .EXAMPLE
    # Update parameters based on the contents of the json file myconfig.json
    Update-DBOConfig Package.zip -ConfigurationFile 'myconfig.json'
    
    .EXAMPLE
    # Specifically update values of the Variables parameter
    Update-DBOConfig Package.zip -Variables @{ foo = 'bar' }
    
    #>
    [CmdletBinding(DefaultParameterSetName = 'Value',
        SupportsShouldProcess = $true)]
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 1)]
        [Alias('FileName', 'Name', 'Package')]
        [string[]]$Path,
        [Parameter(ParameterSetName = 'Value',
            Mandatory = $true,
            Position = 2 )]
        [ValidateSet('ApplicationName', 'SqlInstance', 'Database', 'DeploymentMethod',
            'ConnectionTimeout', 'ExecutionTimeout', 'Encrypt', 'Credential', 'Username',
            'Password', 'SchemaVersionTable', 'Silent', 'Variables'
        )]
        [string]$ConfigName,
        [Parameter(ParameterSetName = 'Value',
            Mandatory = $true,
            Position = 3 )]
        [AllowNull()][object]$Value,
        [Parameter(ParameterSetName = 'Object',
            Mandatory = $true,
            Position = 2 )]
        [Alias('Config')]
        [object]$Configuration,
        [Parameter(ParameterSetName = 'File',
            Mandatory = $true,
            Position = 2 )]
        [Alias('ConfigFile')]
        [string]$ConfigurationFile,
        [Parameter(ParameterSetName = 'Variables',
            Mandatory = $true,
            Position = 2 )]
        [Parameter(ParameterSetName = 'Object')]
        [Parameter(ParameterSetName = 'File')]
        [AllowNull()][hashtable]$Variables
    )
    begin {

    }
    process {
        foreach ($p in $Path) {
            $package = Get-DBOPackage -Path $p
            #preparing an object for a merge
            $config = $package | Get-DBOConfig
            Write-PSFMessage -Level Verbose -Message "Assigning new values to the config"
            if ($PSCmdlet.ParameterSetName -eq 'Value') {
                $newConfig = New-DBOConfig -Configuration @{ $ConfigName = $Value }
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'Object') {
                $newConfig = New-DBOConfig -Configuration $Configuration
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'File') {
                $newConfig = Get-DBOConfig -Path $ConfigurationFile
            }
            if ($pscmdlet.ShouldProcess($package, "Updating the package file/object")) {
                if ($newConfig) {
                    $config.Merge($newConfig)
                }
                #Overriding Variables
                if ($Variables) {
                    $config.Variables = $Variables
                }
                $config.Alter()
            }
        }
    }
    end {

    }
}
