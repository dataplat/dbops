function Invoke-DBODeployment {
    <#
    .SYNOPSIS
        Deploys extracted dbops package from the specified location

    .DESCRIPTION
        Deploys an extracted dbops package or plain text scripts with optional parameters.
        Uses a table specified in SchemaVersionTable parameter to determine scripts to run.
        Will deploy all the builds from the package that previously have not been deployed.

    .PARAMETER PackageFile
        Path to the dbops package file (usually, dbops.package.json).

    .PARAMETER InputObject
        DBOpsPackage object to deploy. Supports pipelining.

    .PARAMETER ScriptPath
        A collection of script files to deploy to the server. Accepts Get-Item/Get-ChildItem objects and wildcards.
        Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
        During deployment, scripts will be following this deployment order:
         - Item order provided in the ScriptPath parameter
           - Files inside each child folder (both folders and files in alphabetical order)
             - Files inside the root folder (in alphabetical order)

        Aliases: SourcePath

    .PARAMETER Configuration
        A custom configuration that will be used during a deployment, overriding existing parameters inside the package.
        Can be a Hashtable, a DBOpsConfig object, or a path to a json file.

    .PARAMETER OutputFile
        Log output into specified file.

    .PARAMETER ConnectionType
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle

    .PARAMETER Append
        Append output to the -OutputFile instead of overwriting it.

    .PARAMETER RegisterOnly
        Store deployment script records in the SchemaVersions table without deploying anything.

    .PARAMETER Build
        Only deploy certain builds from the package.

    .PARAMETER Confirm
        Prompts to confirm certain actions

    .PARAMETER WhatIf
        Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
        # Start the deployment of the extracted package from the current folder
        Invoke-DBODeployment

    .EXAMPLE
        # Start the deployment of the extracted package from the current folder using specific connection parameters
        Invoke-DBODeployment -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600

    .EXAMPLE
        # Start the deployment of the extracted package using custom logging parameters and schema tracking table
        Invoke-DBODeployment .\Extracted\dbops.package.json -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append

    .EXAMPLE
        # Start the deployment of the extracted package in the current folder using variables instead of specifying values directly
        Invoke-DBODeployment -SqlInstance '#{server}' -Database '#{db}' -Configuration @{ Variables = @{server = 'myserver\instance1'; db = 'MyDb'} }
#>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'PackageFile')]
    Param (
        [parameter(ParameterSetName = 'PackageFile')]
        [string]$PackageFile = ".\dbops.package.json",
        [parameter(ParameterSetName = 'Script')]
        [Alias('SourcePath')]
        [string[]]$ScriptPath,
        [parameter(ParameterSetName = 'PackageObject')]
        [Alias('Package')]
        [object]$InputObject,
        [parameter(ParameterSetName = 'PackageObject')]
        [parameter(ParameterSetName = 'PackageFile')]
        [string[]]$Build,
        [string]$OutputFile,
        [switch]$Append,
        [ValidateSet('SQLServer', 'Oracle')]
        [Alias('Type', 'ServerType')]
        [string]$ConnectionType = 'SQLServer',
        [object]$Configuration,
        [switch]$RegisterOnly
    )
    begin {}
    process {
        $config = New-DBOConfig
        if ($PsCmdlet.ParameterSetName -eq 'PackageFile') {
            # Get package object from the json file
            $package = Get-DBOPackage $PackageFile -Unpacked
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'PackageObject') {
            $package = Get-DBOPackage -InputObject $InputObject
        }
        # Merge package config into the current config
        if ($package) {
            $config = $config | Get-DBOConfig -Configuration $package.Configuration
        }
        # Merge custom config into the current config
        if (Test-PSFParameterBinding -ParameterName Configuration) {
            $config = $config | Get-DBOConfig -Configuration $Configuration
        }

        # Initialize external libraries if needed
        Initialize-ExternalLibrary -Type $ConnectionType

        # Replace tokens if any
        foreach ($property in [DBOpsConfig]::EnumProperties() | Where-Object { $_ -ne 'Variables' }) {
            $config.SetValue($property, (Resolve-VariableToken $config.$property $config.Variables))
        }

        # Build connection string
        $connString = Get-ConnectionString -Configuration $config -Type $ConnectionType

        $scriptCollection = @()
        if ($PsCmdlet.ParameterSetName -ne 'Script') {
            # Get contents of the script files
            if ($Build) {
                $buildCollection = $package.GetBuild($Build)
            }
            else {
                $buildCollection = $package.GetBuilds()
            }
            if (!$buildCollection) {
                Stop-PSFFunction -Message "No builds selected for deployment, no deployment will be performed." -EnableException $false
                return
            }
            foreach ($buildItem in $buildCollection) {
                foreach ($script in $buildItem.scripts) {
                    # Replace tokens in the scripts
                    $scriptContent = Resolve-VariableToken $script.GetContent() $runtimeVariables
                    $scriptCollection += [DbUp.Engine.SqlScript]::new($script.GetDeploymentPath(), $scriptContent)
                }
            }
        }
        else {
            foreach ($scriptItem in (Get-ChildScriptItem $ScriptPath)) {
                if (!$RegisterOnly) {
                    # Replace tokens in the scripts
                    $scriptContent = Resolve-VariableToken (Get-Content $scriptItem.FullName -Raw) $runtimeVariables
                }
                else {
                    $scriptContent = ""
                }
                $scriptCollection += [DbUp.Engine.SqlScript]::new($scriptItem.SourcePath, $scriptContent)
            }
        }

        # Build dbUp object
        $dbUp = [DbUp.DeployChanges]::To
        $dbUpConnection = Get-ConnectionManager -ConnectionString $connString -Type $ConnectionType
        if ($ConnectionType -eq 'SqlServer') {
            if ($config.Schema) {
                $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection, $config.Schema)
            }
            else {
                $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection)
            }
        }
        elseif ($ConnectionType -eq 'Oracle') {
            if ($config.Schema) {
                $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUpConnection, $config.Schema)
            }
            else {
                $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUpConnection)
            }
        }
        # Add deployment scripts to the object
        $dbUp = [StandardExtensions]::WithScripts($dbUp, $scriptCollection)

        # Disable automatic sorting by using a custom comparer
        $comparer = [DBOpsScriptComparer]::new($scriptCollection.Name)
        $dbUp = [StandardExtensions]::WithScriptNameComparer($dbUp, $comparer)

        if ($config.DeploymentMethod -eq 'SingleTransaction') {
            $dbUp = [StandardExtensions]::WithTransaction($dbUp)
        }
        elseif ($config.DeploymentMethod -eq 'TransactionPerScript') {
            $dbUp = [StandardExtensions]::WithTransactionPerScript($dbUp)
        }

        # Create an output object
        $status = [DBOpsDeploymentStatus]::new()
        $status.StartTime = [datetime]::Now
        $status.Configuration = $config
        if (!$ConnectionString) {
            $status.SqlInstance = $config.SqlInstance
            $status.Database = $config.Database
        }
        $status.ConnectionType = $ConnectionType
        if ($PsCmdlet.ParameterSetName -eq 'Script') {
            foreach ($p in $ScriptPath) {
                $status.SourcePath += Join-PSFPath -Normalize $p
            }
        }
        else {
            $status.SourcePath = $package.FileName
        }

        # Enable logging using dbopsConsoleLog class implementing a logging Interface
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append, $status)
        $dbUpLog.CallStack = (Get-PSCallStack)[1]
        $dbUp = [StandardExtensions]::LogTo($dbUp, $dbUpLog)
        $dbUp = [StandardExtensions]::LogScriptOutput($dbUp)

        # Configure schema versioning
        if (!$config.SchemaVersionTable) {
            $dbUpTableJournal = [DbUp.Helpers.NullJournal]::new()
        }
        elseif ($config.SchemaVersionTable) {
            $table = $config.SchemaVersionTable.Split('.')
            if (($table | Measure-Object).Count -gt 2) {
                Stop-PSFFunction -EnableException $true -Message 'Incorrect table name - use the following syntax: schema.table'
                return
            }
            elseif (($table | Measure-Object).Count -eq 2) {
                $tableName = $table[1]
                $schemaName = $table[0]
            }
            elseif (($table | Measure-Object).Count -eq 1) {
                $tableName = $table[0]
                if ($config.Schema) {
                    $schemaName = $config.Schema
                }
                else {}
            }
            else {
                Stop-PSFFunction -EnableException $true -Message 'No table name specified'
                return
            }
            # Set default schema for known DB Types
            if (!$schemaName) {
                if ($ConnectionType -eq 'SqlServer') { $schemaName = 'dbo' }
            }
            #Enable schema versioning
            if ($ConnectionType -eq 'SqlServer') { $dbUpJournalType = [DbUp.SqlServer.SqlTableJournal] }
            elseif ($ConnectionType -eq 'Oracle') { $dbUpJournalType = [DbUp.Oracle.OracleTableJournal] }

            $dbUpTableJournal = $dbUpJournalType::new( { $dbUpConnection }, { $dbUpLog }, $schemaName, $tableName)

            #$dbUp = [SqlServerExtensions]::JournalToSqlTable($dbUp, $schemaName, $tableName)
        }
        $dbUp = [StandardExtensions]::JournalTo($dbUp, $dbUpTableJournal)

        # Adding execution timeout - defaults to unlimited execution
        $dbUp = [StandardExtensions]::WithExecutionTimeout($dbUp, [timespan]::FromSeconds($config.ExecutionTimeout))

        # Create database if necessary for supported platforms
        if ($config.CreateDatabase) {
            if ($PSCmdlet.ShouldProcess("Ensuring the target database exists")) {
                switch ($ConnectionType) {
                    SqlServer { [SqlServerExtensions]::SqlDatabase([DbUp.EnsureDatabase]::For, $connString, $dbUpLog, $config.ExecutionTimeout) }
                }
            }
        }
        # Register only
        if ($RegisterOnly) {
            # Cycle through already registered files and register the ones that are missing
            if ($PSCmdlet.ShouldProcess($package, "Registering the package")) {
                $registeredScripts = @()
                $managedConnection = $dbUpConnection.OperationStarting($dbUpLog, $null)
                $deployedScripts = $dbUpTableJournal.GetExecutedScripts()
                try {
                    foreach ($script in $scriptCollection) {
                        if ($script.Name -notin $deployedScripts) {
                            $dbUpConnection.ExecuteCommandsWithManagedConnection( {
                                    Param (
                                        $dbCommandFactory
                                    )
                                    $dbUpTableJournal.StoreExecutedScript($script, $dbCommandFactory)
                                })
                            $registeredScripts += $script
                            $dbUpLog.WriteInformation("{0} was registered in table {1}", @($script.Name, $config.SchemaVersionTable))
                        }
                    }
                    $status.Successful = $true
                }
                catch {
                    $status.Successful = $false
                    Stop-PSFFunction -EnableException $true -Message "Failed to register the script $($script.Name)" -ErrorRecord $_
                }
                finally {
                    $managedConnection.Dispose()
                    $status.Scripts = $registeredScripts
                }
            }
            else {
                $status.Successful = $true
                $status.DeploymentLog += "Running in WhatIf mode - no registration performed."
            }
        }
        else {
            # Build and Upgrade
            if ($PSCmdlet.ShouldProcess($package, "Deploying the package")) {
                $dbUpBuild = $dbUp.Build()
                $upgradeResult = $dbUpBuild.PerformUpgrade()
                $status.Successful = $upgradeResult.Successful
                $status.Error = $upgradeResult.Error
                $status.Scripts = $upgradeResult.Scripts
            }
            else {
                $missingScripts = @()
                $managedConnection = $dbUpConnection.OperationStarting($dbUpLog, $null)
                $deployedScripts = $dbUpTableJournal.GetExecutedScripts()
                foreach ($script in $scriptCollection) {
                    if ($script.Name -notin $deployedScripts) {
                        $missingScripts += $script
                        $dbUpLog.WriteInformation("{0} would have been executed - WhatIf mode.", $script.Name)
                    }
                }
                $managedConnection.Dispose()
                $status.Scripts = $missingScripts
                $status.Successful = $true
                $dbUpLog.WriteInformation("No deployment performed - WhatIf mode.", $null)
            }
        }
        $status.EndTime = [datetime]::Now
        $status
        if (!$status.Successful) {
            # Throw output error if unsuccessful
            if ($status.Error) {
                throw $status.Error
            }
            else {
                Stop-PSFFunction -EnableException $true -Message 'Deployment failed. Failed to retrieve error record'
            }
        }

    }
    end {}
}
