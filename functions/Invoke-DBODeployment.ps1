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
    
    .PARAMETER Variables
        Hashtable with variables that can be used inside the scripts and deployment parameters.
        Proper format of the variable tokens is #{MyVariableName}
        Can also be provided as a part of Configuration hashtable: -Configuration @{ Variables = @{ Var1 = ...; Var2 = ...}}
        Will augment and/or overwrite Variables defined inside the package.

    .PARAMETER OutputFile
        Log output into specified file.
        
    .PARAMETER ConnectionType
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle
        
    .PARAMETER Append
        Append output to the -OutputFile instead of overwriting it.

    .PARAMETER RegisterOnly
        Store deployment script records in the SchemaVersions table without deploying anything.
    
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
        Invoke-DBODeployment -SqlInstance '#{server}' -Database '#{db}' -Variables @{server = 'myserver\instance1'; db = 'MyDb'}
#>
    
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'PackageFile')]
    Param (
        [parameter(ParameterSetName = 'PackageFile')]
        [string]$PackageFile = ".\dbops.package.json",
        [parameter(ParameterSetName = 'Script')]
        [Alias('SourcePath')]
        [string[]]$ScriptPath,
        [parameter(ParameterSetName = 'Pipeline')]
        [Alias('Package')]
        [object]$InputObject,
        [string]$OutputFile,
        [switch]$Append,
        [ValidateSet('SQLServer', 'Oracle')]
        [Alias('Type', 'ServerType')]
        [string]$ConnectionType = 'SQLServer',
        [object]$Configuration,
        [hashtable]$Variables,
        [switch]$RegisterOnly
    )
    begin {}
    process {
        if ($PsCmdlet.ParameterSetName -eq 'PackageFile') {
            #Get package object from the json file
            $package = Get-DBOPackage $PackageFile -Unpacked
            $config = $package.Configuration
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'Script') {
            $config = Get-DBOConfig
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'Pipeline') {
            $package = Get-DBOPackage -InputObject $InputObject
            $config = $package.Configuration
        }

        if (Test-PSFParameterBinding -ParameterName Configuration -BoundParameters $PSBoundParameters) {
            if ($Configuration -is [DBOpsConfig] -or $Configuration -is [hashtable]) {
                Write-PSFMessage -Level Verbose -Message "Merging configuration from a $($Configuration.GetType().Name) object"
                $config.Merge($Configuration)
            }
            elseif ($Configuration -is [String] -or $Configuration -is [System.IO.FileInfo]) {
                $configFromFile = Get-DBOConfig -Path $Configuration
                Write-PSFMessage -Level Verbose -Message "Merging configuration from file $($Configuration)"
                $config.Merge($configFromFile)
            }
            elseif ($Configuration) {
                Stop-PSFFunction -EnableException $true -Message "The following object type is not supported: $($Configuration.GetType().Name). The only supported types are DBOpsConfig, Hashtable, FileInfo and String"
            }
            else {
                Stop-PSFFunction -EnableException $true -Message "No configuration provided, aborting"
            }
        }

        #Test if the selected Connection type is supported
        if (Test-DBOSupportedSystem -Type $ConnectionType) {
            #Load external libraries
            $dependencies = Get-ExternalLibrary -Type $ConnectionType
            foreach ($dPackage in $dependencies) {
                $localPackage = Get-Package -Name $dPackage.Name -MinimumVersion $dPackage.Version -ErrorAction Stop
                foreach ($dPath in $dPackage.Path) {
                    Add-Type -Path (Join-Path (Split-Path $localPackage.Source -Parent) $dPath)
                }
            }
        }
        else {
            Stop-PSFFunction -EnableException $true -Message "$ConnectionType is not supported on this system - some of the external dependencies are missing."
            return
        }

        #Join variables from config and parameters
        $runtimeVariables = @{ }
        if ($Variables) {
            $runtimeVariables += $Variables
        }
        if ($config.Variables) {
            foreach ($variable in $config.Variables.psobject.Properties.Name) {
                if ($variable -notin $runtimeVariables.Keys) {
                    $runtimeVariables += @{
                        $variable = $config.Variables.$variable
                    }
                }
            }
        }
    
        #Replace tokens if any
        foreach ($property in $config.psobject.Properties.Name | Where-Object { $_ -ne 'Variables' }) {
            $config.SetValue($property, (Resolve-VariableToken $config.$property $runtimeVariables))
        }
       
        #Build connection string
        if (!$config.ConnectionString) {
            $CSBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
            $CSBuilder["Server"] = $config.SqlInstance
            if ($config.Database) { $CSBuilder["Database"] = $config.Database }
            if ($config.Encrypt) { $CSBuilder["Encrypt"] = $true }
            $CSBuilder["Connection Timeout"] = $config.ConnectionTimeout
        
            if ($config.Credential) {
                $CSBuilder["User ID"] = $config.Credential.UserName
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($config.Credential.Password)
                $CSBuilder["Password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            elseif ($config.Username) {
                $CSBuilder["User ID"] = $config.UserName
                if ($Password) {
                    [SecureString]$currentPassword = $Password
                }
                else {
                    [SecureString]$currentPassword = $config.Password
                }
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($currentPassword)
                $CSBuilder["Password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            }
            else {
                $CSBuilder["Integrated Security"] = $true
            }
            if ($ConnectionType -eq 'SQLServer') {
                $CSBuilder["Application Name"] = $config.ApplicationName
            }
            $connString = $CSBuilder.ToString()
        }
        else {
            $connString = $config.ConnectionString
        }
    
        $scriptCollection = @()
        if ($PsCmdlet.ParameterSetName -ne 'Script') {
            # Get contents of the script files
            foreach ($build in $package.builds) {
                foreach ($script in $build.scripts) {
                    # Replace tokens in the scripts
                    $scriptPackagePath = ($script.GetPackagePath() -replace ('^' + [regex]::Escape($package.GetPackagePath())), '').TrimStart('\')
                    $scriptContent = Resolve-VariableToken $script.GetContent() $runtimeVariables
                    $scriptCollection += [DbUp.Engine.SqlScript]::new($scriptPackagePath, $scriptContent)
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

        #Build dbUp object
        $dbUp = [DbUp.DeployChanges]::To
        if ($ConnectionType -eq 'SqlServer') {
            $dbUpConnection = [DbUp.SqlServer.SqlConnectionManager]::new($connString)
            if ($config.Schema) {
                $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection, $config.Schema)
            }
            else {
                $dbUp = [SqlServerExtensions]::SqlDatabase($dbUp, $dbUpConnection)
            }
        }
        elseif ($ConnectionType -eq 'Oracle') {
            $dbUpConnection = [DbUp.Oracle.OracleConnectionManager]::new($connString)
            if ($config.Schema) {
                $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUpConnection, $config.Schema)
            }
            else {
                $dbUp = [DbUp.Oracle.OracleExtensions]::OracleDatabase($dbUpConnection)
            }
        }
        #Add deployment scripts to the object
        $dbUp = [StandardExtensions]::WithScripts($dbUp, $scriptCollection)

        #Disable automatic sorting by using a custom comparer
        $comparer = [DBOpsScriptComparer]::new($scriptCollection.Name)
        $dbUp = [StandardExtensions]::WithScriptNameComparer($dbUp, $comparer)

        if ($config.DeploymentMethod -eq 'SingleTransaction') {
            $dbUp = [StandardExtensions]::WithTransaction($dbUp)
        }
        elseif ($config.DeploymentMethod -eq 'TransactionPerScript') {
            $dbUp = [StandardExtensions]::WithTransactionPerScript($dbUp)
        }

        #Create an output object
        $status = [DBOpsDeploymentStatus]::new()
        $status.StartTime = [datetime]::Now
        $status.Configuration = $config
        if (!$ConnectionString) {
            $status.SqlInstance = $config.SqlInstance
            $status.Database = $config.Database
        }
        $status.ConnectionType = $ConnectionType
        if ($PsCmdlet.ParameterSetName -eq 'Script') {
            $status.SourcePath += $ScriptPath
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

        #Adding execution timeout - defaults to unlimited execution
        $dbUp = [StandardExtensions]::WithExecutionTimeout($dbUp, [timespan]::FromSeconds($config.ExecutionTimeout))

        #Create database if necessary for supported platforms
        if ($config.CreateDatabase) {
            if ($PSCmdlet.ShouldProcess("Ensuring the target database exists")) {
                switch ($ConnectionType) {
                    SqlServer { [SqlServerExtensions]::SqlDatabase([DbUp.EnsureDatabase]::For, $connString, $dbUpLog, $config.ExecutionTimeout) }
                }
            }
        }
        #Register only
        if ($RegisterOnly) {
            #Cycle through already registered files and register the ones that are missing
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
                            $dbUpLog.WriteInformation("{0} was registered in table {1}", @($script.Name,$config.SchemaVersionTable))
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
            #Build and Upgrade
            if ($PSCmdlet.ShouldProcess($package, "Deploying the package")) {
                $dbUpBuild = $dbUp.Build()
                $upgradeResult = $dbUpBuild.PerformUpgrade()
                $status.Successful = $upgradeResult.Successful
                $status.Error = $upgradeResult.Error
                $status.Scripts = $upgradeResult.Scripts
            }
            else {
                $status.Successful = $true
                $status.DeploymentLog += "Running in WhatIf mode - no deployment performed."
            }
        }
        $status.EndTime = [datetime]::Now
        $status
        if (!$status.Successful) {
            #Throw output error if unsuccessful
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
