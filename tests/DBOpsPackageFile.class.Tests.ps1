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

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. "$here\..\internal\classes\DBOpsHelper.class.ps1"
. "$here\..\internal\classes\DBOps.class.ps1"

$packageName = "$here\etc\$commandName.zip"
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"
$script3 = "$here\etc\install-tests\success\3.sql"

Describe "DBOpsPackageFile class tests" -Tag $commandName, UnitTests, DBOpsPackage, DBOpsPackageFile {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "validate DBOpsPackageFile being loaded from file" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
            if (Test-Path "$here\etc\LoadFromFile") { Remove-Item "$here\etc\LoadFromFile" -Recurse}
        }
        BeforeAll {
            $p = [DBOpsPackage]::new()
            $b1 = $p.NewBuild('1.0')
            $s1 = $b1.NewScript($script1, 1)
            $b2 = $p.NewBuild('2.0')
            $s1 = $b2.NewScript($script2, 1)
            $p.SaveToFile($packageName)
            $null = New-Item "$here\etc\LoadFromFile" -ItemType Directory
            Expand-Archive $p.FullName "$here\etc\LoadFromFile"
        }
        It "should load package from file" {
            $p = [DBOpsPackageFile]::new("$here\etc\LoadFromFile\dbops.package.json")
            $p.ScriptDirectory | Should Be 'content'
            $p.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $p.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $p.ConfigurationFile.ToString() | Should Be 'dbops.config.json'
            ($p.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'SchemaVersions'
            $p.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $p.FileName | Should Be "$here\etc\LoadFromFile"
            $p.PackagePath | Should Be "$here\etc\LoadFromFile"
            $p.Version | Should Be '2.0'
            $p.Builds.Build | Should Be @('1.0', '2.0')
            $p.Builds.Scripts | Should Be @('success\1.sql', 'success\2.sql')
        }
        It "should override Save/Alter methods" {
            $p = [DBOpsPackageFile]::new("$here\etc\LoadFromFile\dbops.package.json")
            { $p.Save() } | Should Throw
            { $p.Alter() } | Should Throw
        }
        It "should still save the package using SaveToFile method" {
            $p = [DBOpsPackageFile]::new("$here\etc\LoadFromFile\dbops.package.json")
            $p.SaveToFile($packageName, $true)
            $results = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
            'content\1.0\success\1.sql' | Should BeIn $results.Path
            'content\2.0\success\2.sql' | Should BeIn $results.Path
        }
        It "Should test RefreshFileProperties method" {
            $p = [DBOpsPackageFile]::new("$here\etc\LoadFromFile\dbops.package.json")
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