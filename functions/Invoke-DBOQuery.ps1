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

    .PARAMETER Type
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle

    .PARAMETER As
        Specifies output type. Valid options for this parameter are 'DataSet', 'DataTable', 'DataRow', 'PSObject', and 'SingleValue'

    .PARAMETER Parameter
        Uses values in specified hashtable as parameters inside the SQL query.
        For example, <Invoke-DBOQuery -Query 'SELECT @p1' -Parameter @{ p1 = 1 }> would return "1" on SQL Server.

    .PARAMETER ConnectionAttribute
        Additional connection string attributes that should be added to the existing connection string, provided as a hashtable.
        For example to enable SYSDBA permissions in Oracle, use the following: -ConnectionAttribute @{ 'DBA Privilege' = 'SYSDBA' }

    .PARAMETER Interactive
        Opens connection to the server and launches interactive session to query the server directly from the command line

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
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
        [Alias('ConnectionType', 'ServerType')]
        [DBOps.ConnectionType]$Type = (Get-DBODefaultSetting -Name rdbms.type -Value),
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "SingleValue")]
        [string]
        $As = "DataRow",
        [Alias('SqlParameters', 'SqlParameter', 'Parameters')]
        [System.Collections.IDictionary]$Parameter,
        [hashtable]$ConnectionAttribute,
        [Parameter(Mandatory = $true,
            Position = 1,
            ParameterSetName = 'Interactive')]
        [Alias('i')]
        [switch]$Interactive
    )

    begin {
        # description for different delimiters in different DBMS
        $delimiter = switch ($Type) {
            SqlServer { '''GO'' on a new line' }
            PostgreSQL { 'semicolon (;) on a new line' }
            Oracle { 'semicolon (;)' }
            MySQL { 'semicolon (;)' }
        }
        function Write-HostTable {
            Param (
                $Table
            )
            $format = ""
            $totalLength = 0
            if ($Table) {
                for ($i = 0; $i -lt $Table.Columns.Count; $i++) {
                    $maxLength = 0
                    if ($Table.Rows.Count -gt 0) {
                        $Table.Rows | Foreach-Object {
                            $itemLength = ([string]$_.ItemArray[$i]).Length
                            $maxLength = [Math]::Max($itemLength, $maxLength)
                        }
                        $maxLength += 2
                    }
                    if ($Table.Columns[$i].ColumnName.Length -gt $maxLength) { $maxLength = $Table.Columns[$i].ColumnName.Length }
                    $format += " {$i, $maxLength} |"
                    $totalLength += ($maxLength + 3)
                }
                if ($totalLength -gt 0) {
                    $format = "|$format"
                    $totalLength += 1

                    Write-Host ([string]::new('-', $totalLength))
                    Write-Host ($format -f $Table.Columns.ColumnName)
                    Write-Host ([string]::new('-', $totalLength))
                    foreach ($row in $Table.Rows) {
                        # we don't need no newlines
                        $replacedValue = "$($format -f $row.ItemArray)".Replace("`r", " ").Replace("`n", " ")
                        Write-Host $replacedValue
                    }
                    Write-Host ([string]::new('-', $totalLength))
                    # totals
                    Write-Host ("{0, $totalLength}" -f "($($Table.Rows.Count) rows)")
                }
            }
        }
    }
    process {
        $config = New-DBOConfig -Configuration $Configuration
        #Merge custom parameters into a configuration
        $newConfig = @{}
        foreach ($key in ($PSBoundParameters.Keys)) {
            if ($key -in [DBOpsConfig]::EnumProperties()) {
                $newConfig.$key = $PSBoundParameters[$key]
            }
        }
        $config.Merge($newConfig)

        # Initialize external libraries if needed
        Initialize-ExternalLibrary -Type $Type

        #Replace tokens if any
        foreach ($property in [DBOpsConfig]::EnumProperties() | Where-Object { $_ -ne 'Variables' }) {
            $config.SetValue($property, (Resolve-VariableToken $config.$property $config.Variables))
        }

        #Build connection string
        Write-PSFMessage -Level Debug -Message "Getting the connection object"
        $dbUpConnection = Get-ConnectionManager -ConnectionString $null -Type $Type # only needed for query parsing for now, connection string is pointless
        $dataConnection = Get-DatabaseConnection -Configuration $config -Type $Type # the 'real' connection
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append)
        $dbUpLog.CallStack = (Get-PSCallStack)[0]

        # Define the queries
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
                Stop-PSFFunction -Message 'File not found' -ErrorRecord $_ -EnableException $true
            }
            $queryText = $fileObjects | Get-Content -Raw
        }

        #Replace tokens in the sql code if any
        $queryList = @()
        foreach ($qText in $queryText) {
            $queryList += Resolve-VariableToken $qText $config.Variables
        }

        # open the connection
        Write-PSFMessage -Level Verbose -Message "Establishing connection with $Type $($config.SqlInstance)"
        try {
            $dataConnection.Open()
        }
        catch {
            Stop-PSFFunction -EnableException $true -Message "Failed to connect to the server" -ErrorRecord $_
            return
        }
        if ($Interactive) {
            Write-PSFMessage -Level Host -Message "Running in interactive mode. Finish the query with a $delimiter to execute it immediately. \q, exit, or quit to exit."
        }
        else {
            Write-PSFMessage -Level Debug -Message "Preparing to run $($queryList.Count) queries"
        }
        # wrapping everything in a big try {} to support graceful disconnect
        try {
            do {
                if ($Interactive) {
                    # prompt for a query
                    Write-Host ">"
                    $interactiveQuery = @()
                    # read until user finishes with a ;
                    while ($true) {
                        $inputLine = Read-Host
                        # exit on \q
                        if ($inputLine -in '\q', 'exit', 'quit') {
                            $dataConnection.Dispose()
                            return
                        }
                        $interactiveQuery += $inputLine
                        $fullQuery = ($interactiveQuery -join "`n").Trim()
                        $queryList = $dbUpConnection.SplitScriptIntoCommands($fullQuery)
                        if ($queryList[0] -and $queryList[0] -ne $fullQuery) { break }
                    }
                    $queryList = $queryList[0]
                }
                $ds = [System.Data.DataSet]::new()
                $qCount = 0
                foreach ($queryItem in $queryList) {
                    $qCount++
                    if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Executing query $queryItem")) {
                        # split commands using DbUp parser
                        foreach ($splitQuery in $dbUpConnection.SplitScriptIntoCommands($queryItem)) {
                            try {
                                Write-PSFMessage -Level Verbose -Message "Executing sub-query $splitQuery"
                                # only Sql Server supports messaging right now
                                if ($Type -eq 'SqlServer') {
                                    # Add message events
                                    Unregister-Event -SourceIdentifier "DBOpsMessaging" -ErrorAction SilentlyContinue
                                    $eventOutput = Register-ObjectEvent -InputObject $dataConnection -EventName "InfoMessage" -SourceIdentifier "DBOpsMessaging" -Action { $EventArgs.Message }
                                }
                                # create a new command object and define text/parameters
                                $command = $dataConnection.CreateCommand()
                                $command.CommandText = $splitQuery
                                foreach ($key in $Parameter.Keys) {
                                    $null = switch ($Type) {
                                        Oracle {
                                            $command.BindByName = $true
                                            $command.Parameters.Add($key, $Parameter[$key])
                                        }
                                        default { $command.Parameters.AddWithValue($key, $Parameter[$key]) }
                                    }
                                }
                                # create an async reader and wait for output receiving logs in the process
                                $readerTask = $command.ExecuteReaderAsync()
                                if ($Type -eq 'SqlServer') {
                                    $logScript = {
                                        # receive events we got so far and put them in the log
                                        $events = $eventOutput | Receive-Job
                                        foreach ($logEntry in $events) {
                                            $dbUpLog.WriteInformation($logEntry, $null)
                                        }
                                    }
                                    while (-not $readerTask.IsCompleted) {
                                        $logScript.Invoke()
                                        Start-Sleep -Milliseconds 50
                                    }
                                    # once completed, receive the final part and unregister the ivent
                                    $logScript.Invoke()
                                    # lastly, unregister the event
                                    Unregister-Event -SourceIdentifier "DBOpsMessaging"
                                }
                                $reader = $readerTask.GetAwaiter().GetResult()
                                $setCounter = 0
                                do {
                                    $setCounter++
                                    $table = [System.Data.DataTable]::new()
                                    $definition = $reader.GetSchemaTable()
                                    foreach ($column in $definition) {
                                        $name = $column.ColumnName
                                        $datatype = $column.DataType
                                        for ($j = 1; -not $name; $j++) {
                                            if ($table.Columns.ColumnName -notcontains "Column$j") { $name = "Column$j" }
                                        }
                                        if ($datatype.FullName -eq 'System.DBNull') {
                                            $datatype = [string]
                                        }
                                        $null = $table.Columns.Add($name, $datatype)
                                    }
                                    # read rows async and assign values
                                    $rowCount = 0
                                    while ($reader.ReadAsync().GetAwaiter().GetResult()) {
                                        $rowCount++
                                        $row = $table.NewRow()
                                        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                                            $row[$table.Columns[$i].ColumnName] = $reader.GetValue($i);
                                        }
                                        $table.Rows.Add($row)
                                    }
                                    Write-PSFMessage -Level Debug -Message "Received $rowCount rows from resultset $setCounter"
                                    $ds.Tables.Add($table)
                                } while ($reader.NextResult())
                                $reader.Close()
                                $reader.Dispose()
                                $command.Dispose()
                            }
                            catch {
                                $dbUpLog.WriteError($_.Exception.InnerException.Message, $null)
                                if ($Type -eq 'SqlServer') {
                                    Unregister-Event -SourceIdentifier "DBOpsMessaging" -ErrorAction SilentlyContinue
                                }
                                if (-not $Interactive) {
                                    Stop-PSFFunction -EnableException $true -Message "Failed to run the query" -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
                if ($Interactive) {
                    # output right to the screen
                    Write-HostTable -Table $ds.Tables[0]
                }
                else {
                    # output as object
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
            } while ($Interactive)
        }
        catch {
            # don't really need anything else here
            throw $_
        }
        finally {
            # close the connection even when interrupted by Ctrl+C
            $dataConnection.Dispose()
        }
    }
    end {

    }
}