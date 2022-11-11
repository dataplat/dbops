Describe "DBOpsPackageFile class tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        . "$PSScriptRoot\..\..\internal\classes\DBOpsHelper.class.ps1"
        . "$PSScriptRoot\..\..\internal\classes\DBOps.class.ps1"

        New-Workfolder -Force

        $script1, $script2, $script3 = Get-SourceScript -Version 1, 2, 3

        $fileObject1, $fileObject2, $fileObject3 = Get-SourceScript -Version 1, 2, 3 | Get-Item

    }
    AfterAll {
        Remove-Workfolder
    }
    Context "validate DBOpsPackageFile being loaded from file" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
            if (Test-Path "$etcFolder\LoadFromFile") { Remove-Item "$etcFolder\LoadFromFile" -Recurse -Force }
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
            $null = New-Item "$etcFolder\LoadFromFile" -ItemType Directory
            Expand-Archive $p.FullName "$etcFolder\LoadFromFile"
        }
        It "should load package from file" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$etcFolder\LoadFromFile\dbops.package.json"))
            $p.ScriptDirectory | Should -Be 'content'
            $p.DeployFile.ToString() | Should -Be 'Deploy.ps1'
            $p.DeployFile.GetContent() | Should -BeLike '*Install-DBOPackage @params*'
            $p.ConfigurationFile.ToString() | Should -Be 'dbops.config.json'
            ($p.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should -Be 'SchemaVersions'
            $p.Configuration.SchemaVersionTable | Should -Be 'SchemaVersions'
            $p.FileName | Should -Be (Join-PSFPath -Normalize "$etcFolder\LoadFromFile")
            $p.PackagePath | Should -Be (Join-PSFPath -Normalize "$etcFolder\LoadFromFile")
            $p.Version | Should -Be '2.0'
            $p.Builds.Build | Should -Be @('1.0', '2.0')
            $p.Builds.Scripts | Should -Be @(
                Join-PSFPath -Normalize 'success\1.sql'
                Join-PSFPath -Normalize 'success\2.sql'
            )
            $p.GetPreScripts().PackagePath | Should -Be '1.sql', '2.sql'
        }
        It "should override Save/Alter methods" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$etcFolder\LoadFromFile\dbops.package.json"))
            { $p.Save() } | Should -Throw
            { $p.Alter() } | Should -Throw
        }
        It "should still save the package using SaveToFile method" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$etcFolder\LoadFromFile\dbops.package.json"))
            $p.SaveToFile($packageName, $true)
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-PSFPath -Normalize 'Modules\dbops' $file.Path | Should -BeIn $testResults.Path
            }
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
            'Deploy.ps1' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\1.0\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\2.0\success\2.sql' | Should -BeIn $testResults.Path
        }
        It "Should test RefreshFileProperties method" {
            $p = [DBOpsPackageFile]::new((Join-PSFPath -Normalize "$etcFolder\LoadFromFile\dbops.package.json"))
            $p.RefreshFileProperties()
            $FileObject = Get-Item "$etcFolder\LoadFromFile"
            $p.PSPath | Should -Be $FileObject.PSPath.ToString()
            $p.PSParentPath | Should -Be $FileObject.PSParentPath.ToString()
            $p.PSChildName | Should -Be $FileObject.PSChildName.ToString()
            $p.PSDrive | Should -Be $FileObject.PSDrive.ToString()
            $p.PSIsContainer | Should -Be $FileObject.PSIsContainer
            $p.Mode | Should -Be $FileObject.Mode
            $p.BaseName | Should -Be $FileObject.BaseName
            $p.Name | Should -Be $FileObject.Name
            $p.Length | Should -Be $FileObject.Length
            $p.Exists | Should -Be $FileObject.Exists
            $p.FullName | Should -Be $FileObject.FullName
            $p.Extension | Should -Be $FileObject.Extension
            $p.CreationTime | Should -Be $FileObject.CreationTime
            $p.CreationTimeUtc | Should -Be $FileObject.CreationTimeUtc
            $p.LastAccessTime | Should -Be $FileObject.LastAccessTime
            $p.LastAccessTimeUtc | Should -Be $FileObject.LastAccessTimeUtc
            $p.LastWriteTime | Should -Be $FileObject.LastWriteTime
            $p.LastWriteTimeUtc | Should -Be $FileObject.LastWriteTimeUtc
            $p.Attributes | Should -Be $FileObject.Attributes
        }
    }
}