﻿Describe "Get-DBOPackage tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Unpacked -Force

        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
        $null = New-DBOPackage -ScriptPath (Get-SourceScript -Version 1) -Name $packageName -Build 1.0 -Force -ConfigurationFile $fullConfig
        $null = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 2) -Path $packageName -Build 2.0
        $null = Add-DBOBuild -ScriptPath (Get-SourceScript -Version 3) -Path $packageName -Build 3.0
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "Negative tests" {
        BeforeAll {
            Copy-Item $packageName "$packageName.Temp.zip"
            Remove-ArchiveItem -Path "$packageName.Temp.zip" -Item dbops.package.json
        }
        It "returns error when path does not exist" {
            { Get-DBOPackage -Path 'asduwheiruwnfelwefo\sdfpoijfdsf.zip' -ErrorAction Stop } | Should -Throw
        }
        It "returns error when path is an empty string" {
            { Get-DBOPackage -Path '' -ErrorAction Stop } | Should -Throw
        }
        It "returns error when null is pipelined" {
            { $null | Get-DBOPackage -ErrorAction Stop } | Should -Throw
        }
        It "returns error when unsupported object is pipelined" {
            { @{a = 1 } | Get-DBOPackage -ErrorAction Stop } | Should -Throw
        }
        It "returns error when package is in an incorrect format" {
            { $null = Get-DBOPackage -Path (Get-SourceScript -Version 1) } | Should -Throw
            { $null = Get-DBOPackage -Path "$packageName.Temp.zip" } | Should -Throw
        }
    }
    Context "Returns package properties" {
        It "returns existing builds" {
            $testResult = Get-DBOPackage -Path $packageName
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
        }
        It "should return package info" {
            $testResult = Get-DBOPackage -Path $packageName
            $testResult.Version | Should -Be '3.0'
            $testResult.ModuleVersion | Should -Be (Get-Module dbops).Version

            $FileObject = Get-Item $packageName
            $testResult.PSPath | Should -Be $FileObject.PSPath.ToString()
            $testResult.PSParentPath | Should -Be $FileObject.PSParentPath.ToString()
            $testResult.PSChildName | Should -Be $FileObject.PSChildName.ToString()
            $testResult.PSDrive | Should -Be $FileObject.PSDrive.ToString()
            $testResult.PSIsContainer | Should -Be $FileObject.PSIsContainer
            $testResult.Mode | Should -Be $FileObject.Mode
            $testResult.BaseName | Should -Be $FileObject.BaseName
            $testResult.Name | Should -Be $FileObject.Name
            $testResult.Length | Should -Be $FileObject.Length
            $testResult.DirectoryName | Should -Be $FileObject.DirectoryName
            $testResult.Directory | Should -Be $FileObject.Directory.ToString()
            $testResult.IsReadOnly | Should -Be $FileObject.IsReadOnly
            $testResult.Exists | Should -Be $FileObject.Exists
            $testResult.FullName | Should -Be $FileObject.FullName
            $testResult.Extension | Should -Be $FileObject.Extension
            $testResult.CreationTime | Should -Be $FileObject.CreationTime
            $testResult.CreationTimeUtc | Should -Be $FileObject.CreationTimeUtc
            $testResult.LastAccessTime | Should -Not -BeNullOrEmpty
            $testResult.LastAccessTimeUtc | Should -Not -BeNullOrEmpty
            $testResult.LastWriteTime | Should -Be $FileObject.LastWriteTime
            $testResult.LastWriteTimeUtc | Should -Be $FileObject.LastWriteTimeUtc
            $testResult.Attributes | Should -Be $FileObject.Attributes

        }
        It "should return package config" {
            $testResult = Get-DBOPackage -Path $packageName
            $testResult.Configuration | Should -Not -Be $null
            $testResult.Configuration.ApplicationName | Should -Be "MyTestApp"
            $testResult.Configuration.SqlInstance | Should -Be "TestServer"
            $testResult.Configuration.Database | Should -Be "MyTestDB"
            $testResult.Configuration.DeploymentMethod | Should -Be "SingleTransaction"
            $testResult.Configuration.ConnectionTimeout | Should -Be 40
            $testResult.Configuration.Encrypt | Should -Be $null
            $testResult.Configuration.Credential.UserName | Should -Be "CredentialUser"
            $testResult.Configuration.Credential.GetNetworkCredential().Password | Should -Be "TestPassword"
            $testResult.Configuration.Username | Should -Be "TestUser"
            [PSCredential]::new('test', $testResult.Configuration.Password).GetNetworkCredential().Password  | Should -Be "TestPassword"
            $testResult.Configuration.SchemaVersionTable | Should -Be "test.Table"
            $testResult.Configuration.Silent | Should -Be $true
            $testResult.Configuration.Variables.foo | Should -Be 'bar'
            $testResult.Configuration.Variables.boo | Should -Be 'far'
            $testResult.Configuration.Schema | Should -Be 'testschema'
        }
        It "properly returns pipelined package object" {
            $testResult = Get-DBOPackage -Path $packageName | Get-DBOPackage
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
        }
        It "properly returns pipelined filesystem object" {
            $testResult = Get-Item $packageName | Get-DBOPackage
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
        }
        It "properly returns pipelined filesystem child object" {
            $testResult = Get-ChildItem $packageName | Get-DBOPackage
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
        }
        It "properly returns pipelined string" {
            $testResult = $packageName | Get-DBOPackage
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
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
            $testResult = Get-DBOPackage -Path $unpackedFolder -Unpacked
            $testResult.Builds.Build | Should -Be @('1.0', '2.0', '3.0')
            $testResult.Builds.Scripts.Name | Should -Be @('1.sql', '2.sql', '3.sql')
            $testResult.Builds.Scripts.PackagePath | Should -Be @('1.sql', '2.sql', '3.sql')
        }
        It "should return package info" {
            $testResult = Get-DBOPackage -Path $unpackedFolder -Unpacked
            $testResult.Name | Should -Be 'Unpacked'
            $testResult.FullName | Should -Be $unpackedFolder
            $testResult.CreationTime | Should -Not -Be $null
            $testResult.Version | Should -Be '3.0'
            $testResult.ModuleVersion | Should -Be (Get-Module dbops).Version
        }
        It "should return package config" {
            $testResult = Get-DBOPackage -Path $unpackedFolder -Unpacked
            $testResult.Configuration | Should -Not -Be $null
            $testResult.Configuration.ApplicationName | Should -Be "MyTestApp"
            $testResult.Configuration.SqlInstance | Should -Be "TestServer"
            $testResult.Configuration.Database | Should -Be "MyTestDB"
            $testResult.Configuration.DeploymentMethod | Should -Be "SingleTransaction"
            $testResult.Configuration.ConnectionTimeout | Should -Be 40
            $testResult.Configuration.Encrypt | Should -Be $null
            $testResult.Configuration.Credential.UserName | Should -Be "CredentialUser"
            $testResult.Configuration.Credential.GetNetworkCredential().Password | Should -Be "TestPassword"
            $testResult.Configuration.Username | Should -Be "TestUser"
            [PSCredential]::new('test', $testResult.Configuration.Password).GetNetworkCredential().Password | Should -Be "TestPassword"
            $testResult.Configuration.SchemaVersionTable | Should -Be "test.Table"
            $testResult.Configuration.Silent | Should -Be $true
            $testResult.Configuration.Variables.foo | Should -Be 'bar'
            $testResult.Configuration.Variables.boo | Should -Be 'far'
            $testResult.Configuration.Schema | Should -Be 'testschema'
        }
    }
}
