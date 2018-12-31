function Invoke-DBOQuery {
    <#
    .SYNOPSIS
        Runs a query against database

    .DESCRIPTION
        Runs a query against a selected database server and returns results

    .PARAMETER Query
        One or more queries to execute on the remote server

    .PARAMETER InputFile
        Path to one or more SQL sript files.
        Aliases: Name, FileName, ScriptPath, Path

    .PARAMETER InputObject
        Pipeline implementation of InputFile. Accepts output from Get-Item and Get-ChildItem, as well as simple strings and arrays.

    .PARAMETER SqlInstance
        Database server to connect to. SQL Server only for now.
        Aliases: Server, SQLServer, DBServer, Instance

    .PARAMETER Database
        Name of the database to execute the scripts in. Optional - will use default database if not specified.

    .PARAMETER ConnectionTimeout
        Database server connection timeout in seconds. Only affects connection attempts. Does not affect execution timeout.
        If 0, will wait for connection until the end of times.

        Default: 30

    .PARAMETER Encrypt
        Enables connection encryption.

    .PARAMETER Credential
        PSCredential object with username and password to login to the database server.

    .PARAMETER UserName
        An alternative to -Credential - specify username explicitly

    .PARAMETER Password
        An alternative to -Credential - specify password explicitly

    .PARAMETER Silent
        Will supress all output from the command.

    .PARAMETER Variables
        Hashtable with variables that can be used inside the scripts and deployment parameters.
        Proper format of the variable tokens is #{MyVariableName}
        Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
        Will augment and/or overwrite Variables defined inside the package.

    .PARAMETER OutputFile
        Put the execution log into the specified file.

    .PARAMETER Append
        Append output to the -OutputFile instead of overwriting it.

    .PARAMETER ConnectionString
        Custom connection string that will override other connection parameters.
        IMPORTANT: Will also ignore user/password/credential parameters, so make sure to include proper authentication credentials into the string.

    .PARAMETER Configuration
        A custom configuration that will be used during the execution.
        Can be a Hashtable, a DBOpsConfig object, or a path to a json file.

    .PARAMETER Schema
        Execute in a specific schema (if supported by RDBMS)

    .PARAMETER ConnectionType
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', and 'SingleValue'

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        # Runs all SQL scripts from the folder .\SqlCode in the target database
        Invoke-DBOQuery .\SqlCode\*.sql -SqlInstance 'myserver\instance1' -Database 'MyDb'

    .EXAMPLE
        # Runs script file using specific connection parameters
        Get-Item .\SqlCode\Script1.sql | Invoke-DBOQuery -SqlInstance 'Srv1' -Database 'MyDb' -ExecutionTimeout 3600

    .EXAMPLE
        # Runs all the scripts from the .\SqlCode folder using custom logging parameters and schema tracking table
        Get-ChildItem .\SqlCode\* | Invoke-DBOQuery -SqlInstance 'Srv1' -Database 'MyDb' -OutputFile .\out.log -Append

    .EXAMPLE
        # Runs two scripts from the current folder using custom configuration file
        Invoke-DBOQuery -InputFile .\Script1.sql,.\Script2.sql -ConfigurationFile .\localconfig.json

    .EXAMPLE
        # Runs two scripts from the current folder using variables instead of specifying values directly
        '.\Script1.sql','.\Script2.sql' | Invoke-DBOQuery -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'Srv1'; db = 'MyDb'}
#>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Query')]
    param
    (
        [Parameter(Mandatory = $true,
            Position = 1,
            ParameterSetName = 'Script')]
        [Alias('Name', 'ScriptPath', 'Filename', 'Path')]
        [string[]]$InputFile,
        [Parameter(Mandatory = $true,
            Position = 1,
            ParameterSetName = 'Query')]
        [string[]]$Query,
        [Parameter(Mandatory = $true,
            Position = 1,
            ValueFromPipeline = $true,
            ParameterSetName = 'Pipeline')]
        [object]$InputObject,
        [Parameter(Position = 2)]
        [Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
        [string]$SqlInstance,
        [Parameter(Position = 3)]
        [string]$Database,
        [int]$ConnectionTimeout,
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
        [ValidateSet('SQLServer', 'Oracle')]
        [Alias('Type', 'ServerType')]
        [string]$ConnectionType = 'SQLServer',
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]
        $As = "DataRow"
    )

    begin {
    }
    process {
        $config = New-DBOConfig -Configuration $Configuration
        #Merge custom parameters into a configuration
        $newConfig = @{}
        foreach ($key in ($PSBoundParameters.Keys)) {
            if ($key -in [DBOpsConfig]::EnumProperties()) {
                Write-PSFMessage -Level Debug -Message "Overriding parameter $key with $($PSBoundParameters[$key])"
                $newConfig.$key = $PSBoundParameters[$key]
            }
        }
        $config.Merge($newConfig)

        #Test if the selected Connection type is supported and initialize libraries if required
        if (Test-DBOSupportedSystem -Type $ConnectionType) {
            Initialize-ExternalLibrary -Type $ConnectionType
        }
        else {
            Stop-PSFFunction -EnableException $true -Message "$ConnectionType is not supported on this system - some of the external dependencies are missing."
            return
        }

        #Replace tokens if any
        foreach ($property in [DBOpsConfig]::EnumProperties() | Where-Object { $_ -ne 'Variables' }) {
            $config.SetValue($property, (Resolve-VariableToken $config.$property $config.Variables))
        }

        #Build connection string
        #$connString = Get-ConnectionString -Configuration $config -Type $ConnectionType
        #$dbUpConnection = Get-ConnectionManager -ConnectionString $connString -Type $ConnectionType
        $dbUpConnection = Get-ConnectionManager -Configuration $config -Type $ConnectionType
        $dbUpSqlParser = Get-SqlParser -Type $ConnectionType
        $status = [DBOpsDeploymentStatus]::new()
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append, $status)
        $dbUpLog.CallStack = (Get-PSCallStack)[0]
        if (-Not $config.Silent) {
            $dbUpConnection.IsScriptOutputLogged = $true
        }
        $managedConnection = $dbUpConnection.OperationStarting($dbUpLog, $null)
        if ($Query) {
            $queryText = $Query
        }
        else {
            $fileObjects = @()
            try {
                if ($InputFile) {
                    $fileObjects += $InputFile | Get-Item -ErrorAction Stop
                }
                if ($InputObject) {
                    $fileObjects += $InputObject | Get-Item -ErrorAction Stop
                }
            }
            catch {
                Stop-PSFFunction -Message 'File not found' -Exception $_ -EnableException $true
            }
            $queryText = $fileObjects | Get-Content -Raw
        }

        #Replace tokens in the sql code if any
        $queryList = @()
        foreach ($qText in $queryText) {
            $queryList += Resolve-VariableToken $qText $config.Variables
        }
        try {
            $ds = [System.Data.DataSet]::new()
            $qCount = 0
            foreach ($queryItem in $queryList) {
                $qCount++
                if ($PSCmdlet.ShouldProcess("Executing query $qCount", $config.SqlInstance)) {
                    foreach ($splitQuery in $dbUpConnection.SplitScriptIntoCommands($queryItem)) {
                        $dt = [System.Data.DataTable]::new()
                        $rows = $dbUpConnection.ExecuteCommandsWithManagedConnection( [Func[Func[Data.IDbCommand],[pscustomobject]]]{
                            Param (
                                $dbCommandFactory
                            )
                            $sqlRunner = [DbUp.Helpers.AdHocSqlRunner]::new($dbCommandFactory, $dbUpSqlParser, $config.Schema)
                            return $sqlRunner.ExecuteReader($splitQuery)
                        })
                        $rowCount = ($rows | Measure-Object).Count
                        if ($rowCount -gt 0) {
                            $keys = switch ($rowCount) {
                                1 { $rows.Keys }
                                default { $rows[0].Keys }
                            }
                            foreach ($column in $keys) {
                                $null = $dt.Columns.Add($column)
                            }
                            foreach($row in $rows) {
                                $dr = $dt.NewRow()
                                foreach ($col in $row.Keys) {
                                    $dr[$col] = $row[$col]
                                }
                                $null = $dt.Rows.Add($dr);
                            }
                        }
                        $null = $ds.Tables.Add($dt);
                    }
                }
            }
        }
        catch {
            Stop-PSFFunction -EnableException $true -Message "Failed to run the query" -ErrorRecord $_
        }
        finally {
            $managedConnection.Dispose()
        }
        switch ($As) {
            'DataSet' {
                $ds
            }
            'DataTable' {
                $ds.Tables
            }
            'DataRow' {
                if ($ds.Tables.Count -gt 0) {
                    $ds.Tables[0]
                }
            }
            'PSObject' {
                if ($ds.Tables.Count -gt 0) {
                    foreach ($row in $ds.Tables[0].Rows) {
                        [DBOpsHelper]::DataRowToPSObject($row)
                    }
                }
            }
            'SingleValue' {
                if ($ds.Tables.Count -ne 0) {
                    $ds.Tables[0] | Select-Object -ExpandProperty $ds.Tables[0].Columns[0].ColumnName
                }
            }
        }
    }
    end {

    }
}