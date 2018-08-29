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
        
    .PARAMETER ConnectionType
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle
        
    .PARAMETER ConnectionString
        Use a custom connection string to connect to the database server.
    
    .PARAMETER Schema
        Deploy into a specific schema (if supported by RDBMS)
        
    .PARAMETER Append
        Append output to the -OutputFile instead of overwriting it.

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
        [Alias('Server', 'SqlServer', 'DBServer', 'Instance')]
        [string]$SqlInstance,
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
        [string]$OutputFile,
        [switch]$Append,
        [hashtable]$Variables,
        [ValidateSet('SQLServer', 'Oracle')]
        [Alias('Type', 'ServerType')]
        [string]$ConnectionType = 'SQLServer',
        [string]$ConnectionString,
        [string]$Schema
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
            Stop-PSFFunction -EnableException $true -Message "Prerequisites have not been met to run the deployment."
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
    
        #Apply overrides if any
        foreach ($key in ($PSBoundParameters.Keys | Where-Object { $_ -notin 'Variables', 'Password' })) {
            if ($key -in [DBOpsConfig]::EnumProperties()) {
                $config.SetValue($key, (Resolve-VariableToken $PSBoundParameters[$key] $runtimeVariables))
            }
        }
    
        #Apply default values if not set
        # if (!$config.ApplicationName) { $config.SetValue('ApplicationName', 'dbops') }
        # if (!$config.SqlInstance) { $config.SetValue('SqlInstance', 'localhost') }
        # if ($config.ConnectionTimeout -eq $null) { $config.SetValue('ConnectionTimeout', 30) }
        # if ($config.ExecutionTimeout -eq $null) { $config.SetValue('ExecutionTimeout', 0) }
    
        #Build connection string
        if (!$ConnectionString) {
            $CSBuilder = New-Object -TypeName System.Data.SqlClient.SqlConnectionStringBuilder
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
            $connString = $ConnectionString
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
                # Replace tokens in the scripts
                $scriptContent = Resolve-VariableToken (Get-Content $scriptItem.FullName -Raw) $runtimeVariables
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

        # Enable logging using dbopsConsoleLog class implementing a logging Interface
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append)
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

        #Build and Upgrade
        if ($PSCmdlet.ShouldProcess($package, "Deploying the package")) {
            $build = $dbUp.Build()
            $upgradeResult = $build.PerformUpgrade()
            $upgradeResult
            if (!$upgradeResult.Successful) {
                #Throw output error if unsuccessful
                throw $upgradeResult.Error
            }
        }

    }
    end {}
}
