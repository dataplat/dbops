﻿function Invoke-Deployment {
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

    .PARAMETER ScriptFile
        A collection of script files to deploy to the server. Accepts Get-Item/Get-ChildItem objects and wildcards.
        Will recursively add all of the subfolders inside folders. See examples if you want only custom files to be added.
        During deployment, scripts will be following this deployment order:
         - Item order provided in the ScriptFile parameter
           - Files inside each child folder (both folders and files in alphabetical order)
             - Files inside the root folder (in alphabetical order)

        Aliases: SourcePath

    .PARAMETER Configuration
        A custom configuration that will be used during a deployment, overriding existing parameters inside the package.
        Can be a Hashtable, a DBOpsConfig object, or a path to a json file.

    .PARAMETER OutputFile
        Log output into specified file.

    .PARAMETER Type
        Defines the driver to use when connecting to the database server.
        Available options: SqlServer (default), Oracle, PostgreSQL, MySQL

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
        Invoke-Deployment

    .EXAMPLE
        # Start the deployment of the extracted package from the current folder using specific connection parameters
        Invoke-Deployment -SqlInstance 'myserver\instance1' -Database 'MyDb' -ExecutionTimeout 3600

    .EXAMPLE
        # Start the deployment of the extracted package using custom logging parameters and schema tracking table
        Invoke-Deployment .\Extracted\dbops.package.json -SchemaVersionTable dbo.SchemaHistory -OutputFile .\out.log -Append

    .EXAMPLE
        # Start the deployment of the extracted package in the current folder using variables instead of specifying values directly
        Invoke-Deployment -SqlInstance '#{server}' -Database '#{db}' -Configuration @{ Variables = @{server = 'myserver\instance1'; db = 'MyDb'} }
#>

    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'PackageFile')]
    Param (
        [parameter(ParameterSetName = 'PackageFile')]
        [string]$PackageFile = ".\dbops.package.json",
        [parameter(ParameterSetName = 'Script')]
        [Alias('SourcePath')]
        [object[]]$ScriptFile,
        [parameter(ParameterSetName = 'PackageObject')]
        [Alias('Package')]
        [object]$InputObject,
        [parameter(ParameterSetName = 'PackageObject')]
        [parameter(ParameterSetName = 'PackageFile')]
        [string[]]$Build,
        [string]$OutputFile,
        [switch]$Append,
        [Alias('ConnectionType', 'ServerType')]
        [DBOps.ConnectionType]$Type = (Get-DBODefaultSetting -Name rdbms.type -Value),
        [object]$Configuration,
        [switch]$RegisterOnly
    )
    begin {
        Function Get-DeploymentScript {
            Param (
                $Script,
                $Variables
            )
            $scriptDeploymentPath = $Script.GetDeploymentPath()
            Write-PSFMessage -Level Debug -Message "Adding script $scriptDeploymentPath"
            # Replace tokens in the scripts
            $scriptContent = Resolve-VariableToken -InputObject $Script.GetContent() -Runtime $Variables
            return [DBOps.SqlScript]::new($scriptDeploymentPath, $scriptContent)
        }
        Function Initialize-DbUpBuilder {
            Param (
                $Script,
                $Connection,
                $Log,
                $Config,
                $Type,
                $Status,
                $Journal
            )
            # Create DbUpBuilder based on the connection
            $dbUp = Get-DbUpBuilder -Connection $Connection -Type $Type -Script $Script -Config $Config
            # Assign logging
            $dbUp = [StandardExtensions]::LogTo($dbUp, $Log)
            $dbUp = [StandardExtensions]::LogScriptOutput($dbUp)
            # Assign a journal
            if (-Not $Journal) {
                $Journal = Get-DbUpJournal -Connection { $Connection } -Log { $Log } -SchemaVersionTable $null -Type $Type
            }
            $dbUp = [StandardExtensions]::JournalTo($dbUp, $Journal)
            return $dbUp
        }
        Function Invoke-DbUpDeployment {
            Param (
                $DbUp,
                $Status
            )
            $dbUpBuild = $DbUp.Build()
            $upgradeResult = $dbUpBuild.PerformUpgrade()
            $Status.Successful = $upgradeResult.Successful
            $Status.Error = $upgradeResult.Error
            $Status.Scripts += $upgradeResult.Scripts
            if (!$Status.Successful) {
                # Throw output error if unsuccessful
                if ($Status.Error) {
                    if ($upgradeResult.errorScript) {
                        $Status.ErrorScript = $upgradeResult.errorScript.Name
                    }
                    throw $Status.Error
                }
                else {
                    Stop-PSFFunction -EnableException $true -Message 'Deployment failed. Failed to retrieve error record'
                }
            }
        }
    }
    process {
        if ($PsCmdlet.ParameterSetName -eq 'PackageFile') {
            # Get package object from the json file
            $package = Get-DBOPackage $PackageFile -Unpacked
        }
        elseif ($PsCmdlet.ParameterSetName -eq 'PackageObject') {
            $package = Get-DBOPackage -InputObject $InputObject
        }
        # Merge package config into the current config
        $config = Merge-Config -BoundParameters @{Configuration = $Configuration } -Package $package -ProcessVariables

        # Initialize external libraries if needed
        Write-PSFMessage -Level Debug -Message "Initializing libraries for $Type"
        Initialize-ExternalLibrary -Type $Type

        $scriptCollection = @()
        $preScriptCollection = @()
        $postScriptCollection = @()
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
                    $scriptCollection += Get-DeploymentScript -Script $script -Variables $config.Variables
                }
            }
            foreach ($preScript in $package.GetPreScripts()) {
                $preScriptCollection += Get-DeploymentScript -Script $preScript -Variables $config.Variables
            }
            foreach ($postScript in $package.GetPostScripts()) {
                $postScriptCollection += Get-DeploymentScript -Script $postScript -Variables $config.Variables
            }
        }
        else {
            foreach ($scriptItem in $ScriptFile) {
                if ($scriptItem -and $scriptItem -isnot [DBOpsFile]) {
                    Stop-PSFFunction -Message "Expected DBOpsFile object, got [$($scriptItem.GetType().FullName)]." -EnableException $true
                    return
                }
                Write-PSFMessage -Level Debug -Message "Adding deployment script $($scriptItem.FullName) as $($scriptItem.PackagePath)"
                if (!$RegisterOnly) {
                    # Replace tokens in the scripts
                    $scriptContent = Resolve-VariableToken $scriptItem.GetContent() $config.Variables
                }
                else {
                    $scriptContent = ""
                }
                $scriptCollection += [DBOps.SqlScript]::new($scriptItem.PackagePath, $scriptContent)
            }
        }

        Write-PSFMessage -Level Debug -Message "Creating DbUp objects"
        # Create DbUp connection object
        $csBuilder = Get-ConnectionString -Configuration $config -Type $Type -Raw
        $connString = $csBuilder.ToString()
        $dbUpConnection = Get-ConnectionManager -ConnectionString $connString -Type $Type

        # Create an output object
        $status = [DBOpsDeploymentStatus]::new()
        $status.StartTime = [datetime]::Now
        $status.Configuration = $config
        if (!$config.ConnectionString) {
            $status.SqlInstance = $config.SqlInstance
            $status.Database = $config.Database
        }
        $status.ConnectionType = $Type
        if ($PsCmdlet.ParameterSetName -eq 'Script') {
            foreach ($p in $ScriptFile) {
                $status.SourcePath += Join-PSFPath -Normalize $p.FullName
            }
        }
        else {
            $status.SourcePath = $package.FileName
        }

        # Create a logging object using dbopsConsoleLog class implementing a logging Interface
        $dbUpLog = [DBOpsLog]::new($config.Silent, $OutputFile, $Append, $status)
        $dbUpLog.CallStack = (Get-PSCallStack)[1]

        # Define schema versioning (journalling)
        $dbUpTableJournal = Get-DbUpJournal -Connection { $dbUpConnection } -Log { $dbUpLog } -Schema $config.Schema -SchemaVersionTable $config.SchemaVersionTable -Type $Type

        # Initialize DbUp object with deployment parameters
        $dbUp = Initialize-DbUpBuilder -Script $scriptCollection -Config $config -Type $Type -Connection $dbUpConnection -Log $dbUpLog -Status $status -Journal $dbUpTableJournal

        # Create database if necessary for supported platforms
        if ($config.CreateDatabase) {
            if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Ensuring the target database exists")) {
                Write-PSFMessage -Level Debug -Message "Creating database if not exists"
                $null = Invoke-EnsureDatabase -ConnectionString $connString -Log $dbUpLog -Timeout $config.ExecutionTimeout -Type $Type
            }
        }
        # Register only
        if ($RegisterOnly) {
            # Cycle through already registered files and register the ones that are missing
            if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Registering scripts")) {
                $registeredScripts = @()
                $managedConnection = $dbUpConnection.OperationStarting($dbUpLog, $null)
                $deployedScripts = $dbUpTableJournal.GetExecutedScripts()
                try {
                    foreach ($script in $scriptCollection) {
                        if ($script.Name -notin $deployedScripts) {
                            Write-PSFMessage -Level Debug -Message "Registering script $($script.Name)"
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
            $status.EndTime = [datetime]::Now
            $status
            if (!$status.Successful) {
                # Throw output error if unsuccessful
                if ($status.Error) {
                    throw $status.Error
                }
                else {
                    Stop-PSFFunction -EnableException $true -Message 'Script registration failed. Failed to retrieve error record'
                }
            }
        }
        else {
            try {
                # Pre scripts
                if ($preScriptCollection) {
                    # create a new non-journalled connection
                    $dbUpPre = Initialize-DbUpBuilder -Script $preScriptCollection -Config $config -Type $Type -Connection $dbUpConnection -Log $dbUpLog -Status $status
                    if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Deploying pre-scripts")) {
                        Write-PSFMessage -Level Debug -Message "Deploying pre-scripts"
                        Invoke-DbUpDeployment -DbUp $dbUpPre -Status $status
                    }
                    else {
                        foreach ($script in $preScriptCollection) {
                            $status.Scripts += $script
                            $dbUpLog.WriteInformation("{0} would have been executed - WhatIf mode.", $script.Name)
                        }
                        $status.Successful = $true
                        $dbUpLog.WriteInformation("No pre-deployment performed - WhatIf mode.", $null)
                    }
                }
                # Build and Upgrade
                if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Deploying the scripts")) {
                    Write-PSFMessage -Level Debug -Message "Performing deployment"
                    Invoke-DbUpDeployment -DbUp $dbUp -Status $status
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
                    $status.Scripts += $missingScripts
                    $status.Successful = $true
                    $dbUpLog.WriteInformation("No deployment performed - WhatIf mode.", $null)
                }
                # Post scripts
                if ($postScriptCollection) {
                    # create a new non-journalled connection
                    $dbUpPost = Initialize-DbUpBuilder -Script $postScriptCollection -Config $config -Type $Type -Connection $dbUpConnection -Log $dbUpLog -Status $status
                    if ($PSCmdlet.ShouldProcess($config.SqlInstance, "Deploying post-scripts")) {
                        Write-PSFMessage -Level Debug -Message "Deploying post-scripts"
                        Invoke-DbUpDeployment -DbUp $dbUpPost -Status $status
                    }
                    else {
                        foreach ($script in $postScriptCollection) {
                            $status.Scripts += $script
                            $dbUpLog.WriteInformation("{0} would have been executed - WhatIf mode.", $script.Name)
                        }
                        $status.Successful = $true
                        $dbUpLog.WriteInformation("No post-deployment performed - WhatIf mode.", $null)
                    }
                }
            }
            catch {
                Write-Error $_
            }
            finally {
                $status.EndTime = [datetime]::Now
            }
            return $status
        }
    }
    end { }
}
