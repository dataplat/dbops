function Install-DBOPackage {
    <#
    .SYNOPSIS
        Deploys an existing DBOps package

    .DESCRIPTION
        Deploys an existing DBOps package with optional parameters.
        Uses a table specified in SchemaVersionTable parameter to determine scripts to run.
        Will deploy all the builds from the package that previously have not been deployed.

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

    .PARAMETER DeploymentMethod
        Choose one of the following deployment methods:
        - SingleTransaction: wrap all the deployment scripts into a single transaction and rollback whole deployment on error
        - TransactionPerScript: wrap each script into a separate transaction; rollback single script deployment in case of error
        - NoTransaction: deploy as is

        Default: NoTransaction

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

    .PARAMETER Build
        Only deploy certain builds from the package.

    .PARAMETER CreateDatabase
        Will create an empty database if missing on supported RDMBS

    .PARAMETER Type
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle

    .PARAMETER ConnectionAttribute
        Additional connection string attributes that should be added to the existing connection string, provided as a hashtable.
        For example to enable SYSDBA permissions in Oracle, use the following: -ConnectionAttribute @{ 'DBA Privilege' = 'SYSDBA' }

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        # Installs package with predefined configuration inside the package
        Install-DBOPackage .\MyPackage.zip

    .EXAMPLE
        # Installs package using specific connection parameters
        '.\MyPackage.zip' | Install-DBOPackage -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600

    .EXAMPLE
        # Installs package using custom logging parameters and schema tracking table
        '.\MyPackage.zip' | Install-DBOPackage -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append

    .EXAMPLE
        # Installs package using custom configuration file
        '.\MyPackage.zip' | Install-DBOPackage -ConfigurationFile .\localconfig.json

    .EXAMPLE
        # Installs package using variables instead of specifying values directly
        '.\MyPackage.zip' | Install-DBOPackage -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
    # ShouldProcess is handled in the underlying command
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
        [string]$Schema,
        [switch]$CreateDatabase,
        [AllowNull()]
        [string]$ConnectionString,
        [Alias('ConnectionType', 'ServerType')]
        [DBOps.ConnectionType]$Type = (Get-DBODefaultSetting -Name rdbms.type -Value),
        [hashtable]$ConnectionAttribute
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
        }
        foreach ($key in ($PSBoundParameters.Keys)) {
            #If any custom properties were specified
            if ($key -in @('OutputFile', 'Append', 'Type', 'Build')) {
                $params += @{ $key = $PSBoundParameters[$key] }
            }
        }
        Write-PSFMessage -Level Verbose -Message "Preparing to start the deployment of package $($package.FileName)"
        Invoke-DBODeployment @params
    }
    end {

    }
}
