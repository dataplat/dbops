# DBOps
![dbops](https://sqlcollaborative.github.io/dbops/img/dbops.jpg)
DBOps is a Powershell module that provides Continuous Integration/Continuous Deployment capabilities for SQL database deployments. In addition to easy-to-use deployment functions, it provides tracking functionality, ensuring that each script is deployed only once and in due order. It will also grant you with ability to organize scripts into builds and deploy them in a repeatable manner on top of any previously deployed version.

The deployment functionality of the module is provided by [DbUp](https://github.com/DbUp/DbUp) .Net library, which has proven its flexibility and reliability during deployments.

Currently supported RDBMS:
* SQL Server
* Oracle

## Features
The most notable features of the module:

* No scripting experience required - the module is designed around usability and functionality
* Introduces an option to aggregate source scripts from multiple sources into a single ready-to-deploy file
* CI/CD pipelining functionality: builds, artifact management, deployment
* Can detect new/changed files in your source code folder and generate a new deployment build based on those files
* Introduces optional internal build system: older builds are kept inside the deployment package ensuring smooth and errorless deployments
* Reliably deploys the scripts in a consistent manner - all the scripts are executed in alphabetical order one build at a time
* Can be deployed without the module installed in the system - module itself is integrated into the deployment package
* Transactionality of the deployments/migrations: every build can be deployed as a part of a single transaction, rolling back unsuccessful deployments
* Dynamically change your code based on custom variables - use `#{customVarName}` tokens to define variables inside the scripts or execution parameters
* Packages are fully compatible with Octopus Deploy deployments: all packages are in essence zip archives with Deploy.ps1 file that initiates deployment


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

## Examples
### Simple deployment
```powershell
# Quick deployment without tracking deployment history
Invoke-DBODeployment -ScriptPath C:\temp\myscripts -SqlInstance server1 -Database MyDB -SchemaVersionTable $null
```
### Package management
```powershell
# Deployment using packages & builds with keeping track of deployment history in the SchemaVersions table
New-DBOPackage Deploy.zip -ScriptPath C:\temp\myscripts | Install-DBOPackage -SqlInstance server1 -Database MyDB

# Create new deployment package with predefined configuration and deploy it replacing #{dbName} tokens with corresponding values
New-DBOPackage -Path MyPackage.zip -ScriptPath .\Scripts -Configuration @{ Database = '#{dbName}'; ConnectionTimeout = 5 }
Install-DBOPackage MyPackage.zip -Variables @{ dbName = 'myDB' }

# Adding builds to the package
Add-DBOBuild Deploy.zip -ScriptPath .\myscripts -Type Unique -Build 2.0
Get-ChildItem .\myscripts | Add-DBOBuild Deploy.zip -Type New,Modified -Build 3.0\

# Install package using internal script Deploy.ps1 - to use when module is not installed locally
Expand-Archive Deploy.zip '.\MyTempFolder'
.\MyTempFolder\Deploy.ps1 -SqlInstance server1 -Database MyDB
```
### Configurations and defaults
```powershell
# Setting deployment options within the package to be able to deploy it without specifying options
Update-DBOConfig Deploy.zip -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'localhost'; DatabaseName = 'MyDb2' }
Install-DBOPackage Deploy.zip

# Generating config files and using it later as a deployment template
(Get-DBOConfig -Configuration @{ DeploymentMethod = 'SingleTransaction'; SqlInstance = 'devInstance'; DatabaseName = 'MyDB' }).SaveToFile('.\dev.json')
(Get-DBOConfig -Path '.\dev.json' -Configuration @{ SqlInstance = 'prodInstance' }).SaveToFile('.\prod.json')
Install-DBOPackage Deploy.zip -ConfigurationFile .\dev.json

# Invoke package deployment using custom connection string
Install-DBOPackage -Path Deploy.zip -ConnectionString 'Server=myServerAddress;Database=myDataBase;Trusted_Connection=True;'

# Invoke package deployment to an Oracle database OracleDB
Install-DBOPackage -Path Deploy.zip -Server OracleDB -ConnectionType Oracle

# Get a list of all the default settings
Get-DBODefaultSetting

# Change the default SchemaVersionTable setting to null, disabling the deployment logging by default
Set-DBODefaultSetting -Name SchemaVersionTable -Value $null
```
### CI/CD features
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
* Linux support
* SQLCMD support
* Deployments to multiple databases at once
* Optional rollback scripts

## Contacts
Submitting issues - [GitHub issues](https://github.com/sqlcollaborative/dbops/issues)
SQLCommunity Slack: https://sqlcommunity.slack.com #devops or @nvarscar
