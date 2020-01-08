# DBOps
![dbops](https://sqlcollaborative.github.io/dbops/img/dbops.jpg)
DBOps is a Powershell module that provides Continuous Integration/Continuous Deployment capabilities for SQL database deployments. In addition to easy-to-use deployment functions, it provides tracking functionality, ensuring that each script is deployed only once and in due order. It will also grant you with ability to organize scripts into builds and deploy them in a repeatable manner on top of any previously deployed version.

The deployment functionality of the module is provided by [DbUp](https://github.com/DbUp/DbUp) .Net library, which has proven its flexibility and reliability during deployments.

Currently supported RDBMS:
* SQL Server
* Oracle
* PostgreSQL
* MySQL

## Features
The most notable features of the module:

* Reliably deploy your scripts in a consistent and repeatable manner
* Perform ad-hoc deployments with highly customizable deployment parameters
* Run ad-hoc queries to any supported RDBMS on both Windows and Linux
* Create ready-to-deploy versioned packages in a single command
* Brings along all features of CI/CD pipelining functionality: builds, artifact management, deployment
* Roll back the script (or a whole deployment!) in case of errors
* Dynamically change your code based on custom variables using `#{customVarName}` tokens


## System requirements

* Powershell 5.0 or higher

## Installation
### Using git
```powershell
git clone https://github.com/sqlcollaborative/dbops.git dbops
Import-Module .\dbops
```
Make sure to have the following modules installed as well:
- [PSFramework](https://github.com/PowershellFrameworkCollective/psframework)
- [ZipHelper](https://www.powershellgallery.com/packages/ziphelper) - only if you intend to run module tests

### Using PSGallery (Powershell 5+)
```powershell
Install-Module dbops
```

## Usage scenarios

* Ad-hoc deployments of any scale without manual code execution
* Delivering new version of the database schema in a consistent manner to multiple environments
* Build/Test/Deploy scenarios inside the Continuous Integration/Continuous Delivery pipeline
* Dynamic deployment based on modified files in the source folder
* Versioned package deployment (e.g. Octopus Deployment)

## Examples

### Simple deployments and ad-hoc queries

Perform plain-text script deployments using a single command:

[![Invoke-DBODeployment](https://img.youtube.com/vi/PdMCk0Wa-FA/0.jpg)](http://www.youtube.com/watch?v=PdMCk0Wa-FA)<br/>
<small>(click to open the video)</small>

Example code:

```powershell
# Ad-hoc deployment of the scripts from a folder myscripts
Install-DBOScript -ScriptPath C:\temp\myscripts -SqlInstance server1 -Database MyDB

# Execute a list of files as an Ad-hoc query
Get-ChildItem C:\temp\myscripts | Invoke-DBOQuery -SqlInstance server1 -Database MyDB
```
### Package management

<img src="https://sqlcollaborative.github.io/dbops/img/dbops-package.jpg" alt="dbops packages" width="800"/>

Each package consists of multiple builds and can be easily deployed to the database, ensuring that each build is deployed in proper order and only once.

[![Add-DBOBuild](https://img.youtube.com/vi/SasXV9Sz7gs/0.jpg)](http://www.youtube.com/watch?v=SasXV9Sz7gs)<br/>
<small>(click to open the video)</small>

Example code:

```powershell
# Deployment using packaging system
New-DBOPackage Deploy.zip -ScriptPath C:\temp\myscripts | Install-DBOPackage -SqlInstance server1 -Database MyDB

# Create new deployment package with predefined configuration and deploy it replacing #{dbName} tokens with corresponding values
New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts -Configuration @{ Database = '#{dbName}'; ConnectionTimeout = 5 }
Install-DBOPackage MyPackage.zip -Variables @{ dbName = 'myDB' }

# Adding builds to the package
Add-DBOBuild Deploy.zip -ScriptPath .\myscripts -Type Unique -Build 2.0
Get-ChildItem .\myscripts | Add-DBOBuild Deploy.zip -Type New,Modified -Build 3.0

# Install package using internal script Deploy.ps1 - to use when module is not installed locally
Expand-Archive Deploy.zip '.\MyTempFolder'
.\MyTempFolder\Deploy.ps1 -SqlInstance server1 -Database MyDB
```
### Configurations and defaults

There are multiple configuration options available, including:
* Configuring default settings
* Specifying runtime parameters
* Using configuration files

[![Get-DBOConfig](https://img.youtube.com/vi/JRwNyiMyyes/0.jpg)](http://www.youtube.com/watch?v=JRwNyiMyyes)<br/>
<small>(click to open the video)</small>

Example code:

```powershell
# Setting deployment options within the package to be able to deploy it without specifying options
Update-DBOConfig Deploy.zip -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'localhost'; Database = 'MyDb2' }
Install-DBOPackage Deploy.zip

# Generating config files and using it later as a deployment template
New-DBOConfig -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'devInstance'; Database = 'MyDB' } | Export-DBOConfig '.\dev.json'
Get-DBOConfig -Path '.\dev.json' -Configuration @{ SqlInstance = 'prodInstance' } | Export-DBOConfig '.\prod.json'
Install-DBOPackage Deploy.zip -ConfigurationFile .\dev.json

# Invoke package deployment using custom connection string
Install-DBOPackage -Path Deploy.zip -ConnectionString 'Server=myServerAddress;Database=myDataBase;Trusted_Connection=True;'

# Invoke package deployment to an Oracle database OracleDB
Install-DBOPackage -Path Deploy.zip -Server OracleDB -ConnectionType Oracle

# Get a list of all the default settings
Get-DBODefaultSetting

# Change the default SchemaVersionTable setting to null, disabling the deployment journalling by default
Set-DBODefaultSetting -Name SchemaVersionTable -Value $null

# Reset SchemaVersionTable setting back to its default value
Reset-DBODefaultSetting -Name SchemaVersionTable
```
### CI/CD features

dbops CI/CD flow assumes that each package version is built only once and deployed onto every single environment. The successfull builds should make their way as artifacts into the artifact storage, from which they would be pulled again to add new builds into the package during the next iteration.

<img src="https://sqlcollaborative.github.io/dbops/img/ci-cd-flow.jpg" alt="CI-CD flow" width="800"/>

CI/CD capabilities of the module enable user to integrate SQL scripts into a package file using a single command and to store packages in a versioned package repository.

[![Invoke-DBOPackageCI](https://img.youtube.com/vi/A6EwiHM9wE8/0.jpg)](http://www.youtube.com/watch?v=A6EwiHM9wE8)<br/>
<small>(click to open the video)</small>

Example code:

```powershell
# Invoke CI/CD build of the package MyPackage.zip using scripts from the source folder .\Scripts
# Each execution of the command will only pick up new files from the ScriptPath folder
Invoke-DBOPackageCI -Path MyPackage.zip -ScriptPath .\Scripts -Version 1.0

# Store the package in a DBOps package repository in a folder \\data\repo
Publish-DBOPackageArtifact -Path myPackage.zip -Repository \\data\repo

# Retrieve the latest package version from the repository and install it
Get-DBOPackageArtifact -Path myPackage.zip -Repository \\data\repo | Install-DBOPackage -Server MyDBServer -Database MyDB
```

## Planned for future releases

* Code analysis: know what kind of code makes its way into the package. Will find hidden sysadmin grants, USE statements and other undesired statements
* Support for other RDBMS (eventually, everything that DbUp libraries can talk with)
* Integration with unit tests (tSQLt/Pester/...?)
* Module for Ansible (right now can still be used as a powershell task)
* SQLCMD support
* Deployments to multiple databases at once
* Optional rollback scripts

## Contacts
Submitting issues - [GitHub issues](https://github.com/sqlcollaborative/dbops/issues)

SQL Community Slack: https://sqlcommunity.slack.com

   - #dbops channel
   - @nvarscar
