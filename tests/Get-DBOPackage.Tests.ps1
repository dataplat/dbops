Param (
	[switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
	# Is not a part of the global batch => import module
	#Explicitly import the module for testing
	Import-Module "$here\..\dbops.psd1" -Force
}
else {
	# Is a part of a batch, output some eye-catching happiness
	Write-Host "Running $commandName tests" -ForegroundColor Cyan
}



$workFolder = Join-Path "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'
$packageName = Join-Path $workFolder 'TempDeployment.zip'
$scriptFolder = Join-Path $here 'etc\install-tests\success'
$v1scripts = Join-Path $scriptFolder '1.sql'
$v2scripts = Join-Path $scriptFolder '2.sql'
$v3scripts = Join-Path $scriptFolder '3.sql'

Describe "Get-DBOPackage tests" -Tag $commandName, UnitTests {	
	
	BeforeAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
		$null = New-Item $workFolder -ItemType Directory -Force
		$null = New-Item $unpackedFolder -ItemType Directory -Force
		$null = New-DBOPackage -ScriptPath $v1scripts -Name $packageName -Build 1.0 -Force -ConfigurationFile "$here\etc\full_config.json"
		$null = Add-DBOBuild -ScriptPath $v2scripts -Path $packageName -Build 2.0
		$null = Add-DBOBuild -ScriptPath $v3scripts -Path $packageName -Build 3.0
	}
	AfterAll {
		if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
	}
	Context "Negative tests" {
		BeforeAll { 
			Copy-Item $packageName "$packageName.Temp.zip"
			Remove-ArchiveItem -Path "$packageName.Temp.zip" -Item dbops.package.json
		}
        It "returns error when path does not exist" {
            { Get-DBOPackage -Path 'asduwheiruwnfelwefo\sdfpoijfdsf.zip' -ErrorAction Stop} | Should Throw
        }
        It "returns error when path is an empty string" {
            { Get-DBOPackage -Path '' -ErrorAction Stop} | Should Throw
		}
        It "returns error when null is pipelined" {
            { $null | Get-DBOPackage -ErrorAction Stop } | Should Throw
        }
        It "returns error when unsupported object is pipelined" {
            { @{a=1} | Get-DBOPackage -ErrorAction Stop } | Should Throw
		}
		It "returns error when package is in an incorrect format" {
			{ $null = Get-DBOPackage -Path $v1scripts } | Should Throw
			{ $null = Get-DBOPackage -Path "$packageName.Temp.zip" } | Should Throw
		}
	}
	Context "Returns package properties" {
		It "returns existing builds" {
			$result = Get-DBOPackage -Path $packageName
			$result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
			$result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
			$result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
		}
		It "should return package info" {
			$result = Get-DBOPackage -Path $packageName
			$result.Version | Should Be '3.0'
			$result.ModuleVersion | Should Be (Get-Module dbops).Version

			$FileObject = Get-Item $packageName
			$result.PSPath | Should Be $FileObject.PSPath.ToString()
			$result.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
			$result.PSChildName | Should Be $FileObject.PSChildName.ToString()
			$result.PSDrive | Should Be $FileObject.PSDrive.ToString()
			$result.PSIsContainer | Should Be $FileObject.PSIsContainer
			$result.Mode | Should Be $FileObject.Mode
			$result.BaseName | Should Be $FileObject.BaseName
			$result.Name | Should Be $FileObject.Name
			$result.Length | Should Be $FileObject.Length
			$result.DirectoryName | Should Be $FileObject.DirectoryName
			$result.Directory | Should Be $FileObject.Directory.ToString()
			$result.IsReadOnly | Should Be $FileObject.IsReadOnly
			$result.Exists | Should Be $FileObject.Exists
			$result.FullName | Should Be $FileObject.FullName
			$result.Extension | Should Be $FileObject.Extension
			$result.CreationTime | Should Be $FileObject.CreationTime
			$result.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
			$result.LastAccessTime | Should Not BeNullOrEmpty
			$result.LastAccessTimeUtc | Should Not BeNullOrEmpty
			$result.LastWriteTime | Should Be $FileObject.LastWriteTime
			$result.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
			$result.Attributes | Should Be $FileObject.Attributes

		}
        It "should return package config" {
            $result = Get-DBOPackage -Path $packageName
            $result.Configuration | Should Not Be $null
            $result.Configuration.ApplicationName | Should Be "MyTestApp"
            $result.Configuration.SqlInstance | Should Be "TestServer"
            $result.Configuration.Database | Should Be "MyTestDB"
            $result.Configuration.DeploymentMethod | Should Be "SingleTransaction"
            $result.Configuration.ConnectionTimeout | Should Be 40
            $result.Configuration.Encrypt | Should Be $null
            $result.Configuration.Credential | Should Be $null
            $result.Configuration.Username | Should Be "TestUser"
            $result.Configuration.Password | Should Be "TestPassword"
            $result.Configuration.SchemaVersionTable | Should Be "test.Table"
            $result.Configuration.Silent | Should Be $true
            $result.Configuration.Variables | Should Be $null
            $result.Configuration.Schema | Should Be 'testschema'
        }
        It "properly returns pipelined package object" {
            $result = Get-DBOPackage -Path $packageName | Get-DBOPackage 
            $result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
            $result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
            $result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
        }
        It "properly returns pipelined filesystem object" {
            $result = Get-Item $packageName | Get-DBOPackage 
            $result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
            $result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
            $result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
        }
        It "properly returns pipelined filesystem child object" {
            $result = Get-ChildItem $packageName | Get-DBOPackage 
            $result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
            $result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
            $result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
        }
        It "properly returns pipelined string" {
            $result = $packageName | Get-DBOPackage 
            $result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
            $result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
            $result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
        }
	}
	Context "Returns unpacked package properties" {
		BeforeAll {
			$null = New-Item $unpackedFolder -ItemType Directory -Force
			Expand-Archive $packageName $unpackedFolder
		}
		AfterAll {
			Remove-Item -Path (Join-Path $unpackedFolder *) -Force -Recurse
		}
		It "returns existing builds" {
			$result = Get-DBOPackage -Path $unpackedFolder -Unpacked
			$result.Builds.Build | Should Be @('1.0', '2.0', '3.0')
			$result.Builds.Scripts.Name | Should Be @('1.sql', '2.sql', '3.sql')
			$result.Builds.Scripts.SourcePath | Should Be @((Get-Item $v1scripts).FullName, (Get-Item $v2scripts).FullName, (Get-Item $v3scripts).FullName)
		}
		It "should return package info" {
			$result = Get-DBOPackage -Path $unpackedFolder -Unpacked
			$result.Name | Should Be 'Unpacked'
			$result.FullName | Should Be $unpackedFolder
			$result.CreationTime | Should Not Be $null
			$result.Version | Should Be '3.0'
			$result.ModuleVersion | Should Be (Get-Module dbops).Version
		}
		It "should return package config" {
			$result = Get-DBOPackage -Path $unpackedFolder -Unpacked
			$result.Configuration | Should Not Be $null
			$result.Configuration.ApplicationName | Should Be "MyTestApp"
			$result.Configuration.SqlInstance | Should Be "TestServer"
			$result.Configuration.Database | Should Be "MyTestDB"
			$result.Configuration.DeploymentMethod | Should Be "SingleTransaction"
			$result.Configuration.ConnectionTimeout | Should Be 40
			$result.Configuration.Encrypt | Should Be $null
			$result.Configuration.Credential | Should Be $null
			$result.Configuration.Username | Should Be "TestUser"
			$result.Configuration.Password | Should Be "TestPassword"
			$result.Configuration.SchemaVersionTable | Should Be "test.Table"
			$result.Configuration.Silent | Should Be $true
            $result.Configuration.Variables | Should Be $null
            $result.Configuration.Schema | Should Be 'testschema'
		}
	}
}
