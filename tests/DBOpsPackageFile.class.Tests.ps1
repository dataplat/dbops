Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$packageName = Join-PSFPath -Normalize "$here\etc\$commandName.zip"
$script1 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$script2 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$script3 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\3.sql"
$fileObject1 = Get-Item $script1
$fileObject2 = Get-Item $script2
$fileObject3 = Get-Item $script3

Describe "DBOpsPackageFile class tests" -Tag $commandName, UnitTests, DBOpsPackage, DBOpsPackageFile {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "validate DBOpsPackageFile being loaded from file" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
            if (Test-Path "$here\etc\LoadFromFile") { Remove-Item "$here\etc\LoadFromFile" -Recurse -Force }
        }
        BeforeAll {
            $p = [DBOpsPackage]::new()
            $b1 = $p.NewBuild('1.0')
            $b1.AddScript([DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize 'success\1.sql'), $true))
            $b2 = $p.NewBuild('2.0')
            $b2.AddScript([DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize 'success\2.sql'), $true))
            $f = [DBOpsFile]::new($fileObject1, (Join-PSFPath -Normalize '1.sql'), $true)
            $f2 = [DBOpsFile]::new($fileObject2, (Join-PSFPath -Normalize '2.sql'), $true)
            $p.SetPreScripts(@($f, $f2))
            $p.SaveToFile($packageName)
            $null = New-Item "$here\etc\LoadFromFile" -ItemType Directory
            Expand-Archive $p.FullName "$here\etc\LoadFromFile"
        }
        It "should load package from file" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$here\etc\LoadFromFile\dbops.package.json"))
            $p.ScriptDirectory | Should Be 'content'
            $p.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $p.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $p.ConfigurationFile.ToString() | Should Be 'dbops.config.json'
            ($p.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'SchemaVersions'
            $p.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $p.FileName | Should Be (Join-PSFPath -Normalize "$here\etc\LoadFromFile")
            $p.PackagePath | Should Be (Join-PSFPath -Normalize "$here\etc\LoadFromFile")
            $p.Version | Should Be '2.0'
            $p.Builds.Build | Should Be @('1.0', '2.0')
            $p.Builds.Scripts | Should Be @(
                Join-PSFPath -Normalize 'success\1.sql'
                Join-PSFPath -Normalize 'success\2.sql'
            )
            $p.GetPreScripts().PackagePath | Should Be '1.sql', '2.sql'
        }
        It "should override Save/Alter methods" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$here\etc\LoadFromFile\dbops.package.json"))
            { $p.Save() } | Should Throw
            { $p.Alter() } | Should Throw
        }
        It "should still save the package using SaveToFile method" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$here\etc\LoadFromFile\dbops.package.json"))
            $p.SaveToFile($packageName, $true)
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should BeIn $testResults.Path
            }
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
            'Deploy.ps1' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should BeIn $testResults.Path
        }
        It "Should test RefreshFileProperties method" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$here\etc\LoadFromFile\dbops.package.json"))
            $p.RefreshFileProperties()
            $FileObject = Get-Item "$here\etc\LoadFromFile"
            $p.PSPath | Should Be $FileObject.PSPath.ToString()
            $p.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
            $p.PSChildName | Should Be $FileObject.PSChildName.ToString()
            $p.PSDrive | Should Be $FileObject.PSDrive.ToString()
            $p.PSIsContainer | Should Be $FileObject.PSIsContainer
            $p.Mode | Should Be $FileObject.Mode
            $p.BaseName | Should Be $FileObject.BaseName
            $p.Name | Should Be $FileObject.Name
            $p.Length | Should Be $FileObject.Length
            $p.Exists | Should Be $FileObject.Exists
            $p.FullName | Should Be $FileObject.FullName
            $p.Extension | Should Be $FileObject.Extension
            $p.CreationTime | Should Be $FileObject.CreationTime
            $p.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
            $p.LastAccessTime | Should Be $FileObject.LastAccessTime
            $p.LastAccessTimeUtc | Should Be $FileObject.LastAccessTimeUtc
            $p.LastWriteTime | Should Be $FileObject.LastWriteTime
            $p.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
            $p.Attributes | Should Be $FileObject.Attributes
        }
    }
}