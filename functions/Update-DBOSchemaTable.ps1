function Update-DBOSchemaTable {
    <#
    .SYNOPSIS
        Adds extra columns the SchemaHistory table.

    .DESCRIPTION
        Upgrades an old version of the SchemaHistory table to a most recent version ensuring all the necessary columns are present.

    .PARAMETER SqlInstance
        Database server to use.
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
        A table that would be upgraded.

        Default: SchemaVersions

    .PARAMETER Silent
        Will supress all output from the command.

    .PARAMETER Variables
        Hashtable with variables that can be used inside the scripts and deployment parameters.
        Proper format of the variable tokens is #{MyVariableName}. Format can be changed using "Set-DBODefaultSetting -Name config.variabletoken"
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
        Use a specific schema (if supported by RDBMS)

    .PARAMETER Type
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle, PostgreSQL, MySQL

    .PARAMETER ConnectionAttribute
        Additional connection string attributes that should be added to the existing connection string, provided as a hashtable.
        For example to enable SYSDBA permissions in Oracle, use the following: -ConnectionAttribute @{ 'DBA Privilege' = 'SYSDBA' }

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        # Upgrades default SchemaVersion table.
        Upgrade-DBOSchemaTable -SqlInstance 'myserver\instance1'

    .EXAMPLE
        # Upgrades a custom SchemaVersion table: MySchemaHistory
        Upgrade-DBOSchemaTable -SqlInstance 'myserver\instance1' -SchemaVersionTable 'MySchemaHistory'

    .EXAMPLE
        # Upgrades a custom SchemaVersion table: MySchemaHistory. Uses variables to connect to the server.
        Upgrade-DBOSchemaTable -SqlInstance '#{server}' -SchemaVersionTable 'MySchemaHistory' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    param
    (

        [string]$SchemaVersionTable,
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
        [switch]$Silent,
        [Alias('ArgumentList')]
        [hashtable]$Variables,
        [string]$OutputFile,
        [switch]$Append,
        [Alias('Config')]
        [object]$Configuration,
        [string]$Schema,
        [AllowNull()]
        [string]$ConnectionString,
        [Alias('ConnectionType', 'ServerType')]
        [DBOps.ConnectionType]$Type = (Get-DBODefaultSetting -Name rdbms.type -Value),
        [hashtable]$ConnectionAttribute
    )
    process {
        # Merge package config into the current config
        $config = Merge-Config -BoundParameters $PSBoundParameters

        # Create DbUp connection object
        $csBuilder = Get-ConnectionString -Configuration $config -Type $Type -Raw
        $dbUpConnection = Get-ConnectionManager -ConnectionString $csBuilder.ToString() -Type $Type
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append)
        $dbUpLog.CallStack = (Get-PSCallStack)[0]

        # Define schema versioning (journalling)
        $dbUpTableJournal = Get-DbUpJournal -Connection { $dbUpConnection } -Log { $dbUpLog } -Schema $config.Schema -SchemaVersionTable $config.SchemaVersionTable -Type $Type

        if ($PSCmdlet.ShouldProcess($SchemaVersionTable, "Upgrading the schema version table")) {
            $managedConnection = $dbUpConnection.OperationStarting($dbUpLog, $null)
            try {
                $dbUpConnection.ExecuteCommandsWithManagedConnection( {
                    Param (
                        $dbCommandFactory
                    )
                    $dbUpTableJournal.UpgradeJournalTable($dbCommandFactory)
                })
            }
            catch {
                Stop-PSFFunction -EnableException $true -Message "Failed to upgrade schema version table $($config.SchemaVersionTable)" -ErrorRecord $_
            }
            finally {
                $managedConnection.Dispose()
            }
        }
    }
}