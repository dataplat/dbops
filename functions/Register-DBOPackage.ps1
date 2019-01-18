function Register-DBOPackage {
    <#
    .SYNOPSIS
        Registers scripts of the existing DBOps package as 'already deployed' in the target database without executing them

    .DESCRIPTION
        Registers scripts of the existing DBOps package in a schema verion table with optional parameters.

    .PARAMETER Path
        Path to the existing DBOpsPackage.
        Aliases: Name, FileName, Package

    .PARAMETER InputObject
        Pipeline implementation of Path. Can also contain a DBOpsPackage object.

    .PARAMETER SqlInstance
        Database server to connect to. SQL Server only for now.
        Aliases: Server, SQLServer, DBServer, Instance

    .PARAMETER Database
        Name of the database to execute the scripts in. Optional - will use default database if not specified.

    .PARAMETER ConnectionTimeout
        Database server connection timeout in seconds. Only affects connection attempts. Does not affect execution timeout.
        If 0, will wait for connection until the end of times.

        Default: 30

    .PARAMETER ExecutionTimeout
        Script execution timeout. The script will be aborted if the execution takes more than specified number of seconds.
        If 0, the script is allowed to run until the end of times.

        Default: 0

    .PARAMETER Encrypt
        Enables connection encryption.

    .PARAMETER Credential
        PSCredential object with username and password to login to the database server.

    .PARAMETER UserName
        An alternative to -Credential - specify username explicitly

    .PARAMETER Password
        An alternative to -Credential - specify password explicitly

    .PARAMETER SchemaVersionTable
        A table that will hold the history of script execution. This table is used to choose what scripts are going to be
        run during the deployment, preventing the scripts from being execured twice.
        If set to $null, the deployment will not be tracked in the database. That will also mean that all the scripts
        and all the builds from the package are going to be deployed regardless of any previous deployment history.

        Default: SchemaVersions

    .PARAMETER Silent
        Will supress all output from the command.

    .PARAMETER Variables
        Hashtable with variables that can be used inside the scripts and deployment parameters.
        Proper format of the variable tokens is #{MyVariableName}
        Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
        Will augment and/or overwrite Variables defined inside the package.

    .PARAMETER OutputFile
        Log output into specified file.

    .PARAMETER Append
        Append output to the -OutputFile instead of overwriting it.

    .PARAMETER ConnectionString
        Custom connection string that will override other connection parameters.
        IMPORTANT: Will also ignore user/password/credential parameters, so make sure to include proper authentication credentials into the string.

    .PARAMETER Configuration
        A custom configuration that will be used during a deployment, overriding existing parameters inside the package.
        Can be a Hashtable, a DBOpsConfig object, or a path to a json file.

    .PARAMETER Schema
        Deploy into a specific schema (if supported by RDBMS)

    .PARAMETER CreateDatabase
        Will create an empty database if missing on supported RDMBS

    .PARAMETER Type
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle

    .PARAMETER Build
        Only register certain builds from the package.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        # Register package scripts in a target database with predefined configuration inside the package
        Register-DBOPackage .\MyPackage.zip

    .EXAMPLE
        # Register package scripts in a target database using specific connection parameters
        .\MyPackage.zip | Register-DBOPackage -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600

    .EXAMPLE
        # Register package scripts in a target database using custom logging parameters and schema tracking table
        .\MyPackage.zip | Register-DBOPackage -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append

    .EXAMPLE
        # Register package scripts in a target database using custom configuration file
        .\MyPackage.zip | Register-DBOPackage -ConfigurationFile .\localconfig.json

    .EXAMPLE
        # Register package scripts in a target database using variables instead of specifying values directly
        .\MyPackage.zip | Register-DBOPackage -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSShouldProcess", "")]
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    param
    (
        [Parameter(Mandatory = $true,
            Position = 1,
            ParameterSetName = 'Default')]
        [Alias('Name', 'Package', 'Filename')]
        [string]$Path,
        [Parameter(Mandatory = $true,
            Position = 1,
            ValueFromPipeline = $true,
            ParameterSetName = 'Pipeline')]
        [object]$InputObject,
        [string[]]$Build,
        [Parameter(Position = 2)]
        [Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
        [string]$SqlInstance,
        [Parameter(Position = 3)]
        [string]$Database,
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
        [string]$Schema,
        [switch]$CreateDatabase,
        [AllowNull()]
        [string]$ConnectionString,
        [Alias('ConnectionType', 'ServerType')]
        [DBOps.ConnectionType]$Type = (Get-DBODefaultSetting -Name rdbms.type -Value)
    )

    begin {
    }
    process {
        if ($PsCmdlet.ParameterSetName -eq 'Default') {
            $package = Get-DBOPackage -Path $Path
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'Pipeline') {
            $package = Get-DBOPackage -InputObject $InputObject
        }
        #Getting new config with package defaults
        $config = New-DBOConfig -Configuration $package.Configuration

        #Merging the custom configuration provided
        $config = $config | Get-DBOConfig -Configuration $Configuration

        #Merge custom parameters into a configuration
        $newConfig = @{}
        foreach ($key in ($PSBoundParameters.Keys)) {
            if ($key -in [DBOpsConfig]::EnumProperties()) {
                $newConfig.$key = $PSBoundParameters[$key]
            }
        }
        $config.Merge($newConfig)

        #Prepare deployment function call parameters
        $params = @{
            InputObject   = $package
            Configuration = $config
            RegisterOnly  = $true
        }
        foreach ($key in ($PSBoundParameters.Keys)) {
            #If any custom properties were specified
            if ($key -in @('OutputFile', 'Append', 'Type', 'Build')) {
                $params += @{ $key = $PSBoundParameters[$key] }
            }
        }
        Write-PSFMessage -Level Verbose -Message "Preparing to register the package $($package.FileName)"
        Invoke-DBODeployment @params
    }
    end {

    }
}
