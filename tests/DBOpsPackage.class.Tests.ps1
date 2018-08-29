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
$script:pkg = $null
$script:build = $null
$script:file = $null
$script1 = "$here\etc\install-tests\success\1.sql"
$script2 = "$here\etc\install-tests\success\2.sql"
$script3 = "$here\etc\install-tests\success\3.sql"

Describe "DBOpsPackage class tests" -Tag $commandName, UnitTests, DBOpsPackage {
    AfterAll {
        if (Test-Path $packageName) { Remove-Item $packageName }
    }
    Context "validating DBOpsPackage creation" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "Should create new DBOpsPackage object" {
            $script:pkg = [DBOpsPackage]::new()
            $script:pkg.ScriptDirectory | Should Be 'content'
            $script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $script:pkg.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $script:pkg.FileName | Should BeNullOrEmpty
            $script:pkg.Version | Should BeNullOrEmpty
        }
        It "should save package to file" {
            { $script:pkg.SaveToFile($packageName, $true) } | Should Not Throw
        }
        $results = Get-ArchiveItem $packageName
        It "should contain module files" {
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
        }
        It "should contain config files" {
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
        }
        It "should contain deploy file" {
            'Deploy.ps1' | Should BeIn $results.Path
        }
    }
    Context "validate DBOpsPackage being loaded from file" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeAll {
            $script:pkg = [DBOpsPackage]::new()
            $script:pkg.SaveToFile($packageName)
        }
        It "should load package from file" {
            $script:pkg = [DBOpsPackage]::new($packageName)
            $script:pkg.ScriptDirectory | Should Be 'content'
            $script:pkg.DeployFile.ToString() | Should Be 'Deploy.ps1'
            $script:pkg.DeployFile.GetContent() | Should BeLike '*Invoke-DBODeployment @params*'
            $script:pkg.ConfigurationFile.ToString() | Should Be 'dbops.config.json'
            ($script:pkg.ConfigurationFile.GetContent() | ConvertFrom-Json).SchemaVersionTable | Should Be 'SchemaVersions'
            $script:pkg.Configuration.SchemaVersionTable | Should Be 'SchemaVersions'
            $script:pkg.FileName | Should Be $packageName
            $script:pkg.Version | Should BeNullOrEmpty
            $script:pkg.PackagePath | Should BeNullOrEmpty
        }
    }
    Context "should validate DBOpsPackage methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        BeforeAll {
            $script:pkg = [DBOpsPackage]::new()
            $script:pkg.SaveToFile($packageName)
        }
        It "Should test GetBuilds method" {
            $script:pkg.GetBuilds() | Should Be $null
        }
        It "Should test NewBuild method" {
            $b = $script:pkg.NewBuild('1.0')
            $b.Build | Should Be '1.0'
            $b.PackagePath | Should Be '1.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
            $script:pkg.Version | Should Be '1.0'
        }
        It "Should test GetBuild method" {
            $b = $script:pkg.GetBuild('1.0')
            $b.Build | Should Be '1.0'
            $b.PackagePath | Should Be '1.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
        }
        It "Should test AddBuild method" {
            $script:pkg.AddBuild('2.0')
            $b = $script:pkg.GetBuild('2.0')
            $b.Build | Should Be '2.0'
            $b.PackagePath | Should Be '2.0'
            $b.Parent.GetType().Name | Should Be 'DBOpsPackage'
            $b.Scripts | Should BeNullOrEmpty
            ([datetime]$b.CreatedDate).Date | Should Be ([datetime]::Now).Date
            $script:pkg.Version | Should Be '2.0'
        }
        It "Should test EnumBuilds method" {
            $script:pkg.EnumBuilds() | Should Be @('1.0', '2.0')
        }
        It "Should test GetVersion method" {
            $script:pkg.GetVersion() | Should Be '2.0'
        }
        It "Should test RemoveBuild method" {
            $script:pkg.RemoveBuild('2.0')
            '2.0' | Should Not BeIn $script:pkg.EnumBuilds()
            $script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
            $script:pkg.Version | Should Be '1.0'
            #Testing overloads
            $b = $script:pkg.NewBuild('2.0')
            '2.0' | Should BeIn $script:pkg.EnumBuilds()
            $script:pkg.Version | Should Be '2.0'
            $script:pkg.RemoveBuild($b)
            '2.0' | Should Not BeIn $script:pkg.EnumBuilds()
            $script:pkg.GetBuild('2.0') | Should BeNullOrEmpty
            $script:pkg.Version | Should Be '1.0'
        }
        It "should test ScriptExists method" {
            $b = $script:pkg.GetBuild('1.0')
            $s = "$here\etc\install-tests\success\1.sql"
            $f = [DBOpsScriptFile]::new(@{SourcePath = $s; PackagePath = 'success\1.sql'})
            $f.SetContent([DBOpsHelper]::GetBinaryFile($s))
            $b.AddFile($f, 'Scripts')
            $script:pkg.ScriptExists($s) | Should Be $true
            $script:pkg.ScriptExists("$here\etc\install-tests\transactional-failure\1.sql") | Should Be $false
            { $script:pkg.ScriptExists("Nonexisting\path") } | Should Throw
        }
        It "should test ScriptModified method" {
            $s1 = "$here\etc\install-tests\success\1.sql"
            $s2 = "$here\etc\install-tests\success\2.sql"
            $script:pkg.ScriptModified($s2, $s1) | Should Be $true
            $script:pkg.ScriptModified($s1, $s1) | Should Be $false
        }
        It "should test SourcePathExists method" {
            $s1 = "$here\etc\install-tests\success\1.sql"
            $s2 = "$here\etc\install-tests\success\2.sql"
            $script:pkg.SourcePathExists($s1) | Should Be $true
            $script:pkg.SourcePathExists($s2) | Should Be $false
        }
        It "should test ExportToJson method" {
            $j = $script:pkg.ExportToJson() | ConvertFrom-Json
            $j.Builds | Should Not BeNullOrEmpty
            $j.ConfigurationFile | Should Not BeNullOrEmpty
            $j.DeployFile | Should Not BeNullOrEmpty
            $j.ScriptDirectory | Should Not BeNullOrEmpty
        }
        It "Should test GetPackagePath method" {
            $script:pkg.GetPackagePath() | Should Be 'content'
        }
        It "Should test RefreshModuleVersion method" {
            $script:pkg.RefreshModuleVersion()
            $script:pkg.ModuleVersion | Should Be (Get-Module dbops).Version
        }
        It "Should test RefreshFileProperties method" {
            $script:pkg.RefreshFileProperties()
            $FileObject = Get-Item $packageName
            $script:pkg.PSPath | Should Be $FileObject.PSPath.ToString()
            $script:pkg.PSParentPath | Should Be $FileObject.PSParentPath.ToString()
            $script:pkg.PSChildName | Should Be $FileObject.PSChildName.ToString()
            $script:pkg.PSDrive | Should Be $FileObject.PSDrive.ToString()
            $script:pkg.PSIsContainer | Should Be $FileObject.PSIsContainer
            $script:pkg.Mode | Should Be $FileObject.Mode
            $script:pkg.BaseName | Should Be $FileObject.BaseName
            $script:pkg.Name | Should Be $FileObject.Name
            $script:pkg.Length | Should Be $FileObject.Length
            $script:pkg.DirectoryName | Should Be $FileObject.DirectoryName
            $script:pkg.Directory | Should Be $FileObject.Directory.ToString()
            $script:pkg.IsReadOnly | Should Be $FileObject.IsReadOnly
            $script:pkg.Exists | Should Be $FileObject.Exists
            $script:pkg.FullName | Should Be $FileObject.FullName
            $script:pkg.Extension | Should Be $FileObject.Extension
            $script:pkg.CreationTime | Should Be $FileObject.CreationTime
            $script:pkg.CreationTimeUtc | Should Be $FileObject.CreationTimeUtc
            $script:pkg.LastAccessTime | Should Not BeNullOrEmpty
            $script:pkg.LastAccessTimeUtc | Should Not BeNullOrEmpty
            $script:pkg.LastWriteTime | Should Be $FileObject.LastWriteTime
            $script:pkg.LastWriteTimeUtc | Should Be $FileObject.LastWriteTimeUtc
            $script:pkg.Attributes | Should Be $FileObject.Attributes
        }

        It "Should test SetConfiguration method" {
            $config = @{ SchemaVersionTable = 'dbo.NewTable' } | ConvertTo-Json -Depth 1
            { $script:pkg.SetConfiguration([DBOpsConfig]::new($config)) } | Should Not Throw
            $script:pkg.Configuration.SchemaVersionTable | Should Be 'dbo.NewTable'
        }
        $oldResults = Get-ArchiveItem $packageName
        #Sleep 1 second to ensure that modification date is changed
        Start-Sleep -Seconds 2
        It "should test Save*/Alter methods" {
            { $script:pkg.SaveToFile($packageName) } | Should Throw #File already exists
            { $script:pkg.Alter() } | Should Not Throw
            $results = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
            'content\1.0\success\1.sql' | Should BeIn $results.Path
        }
        # Testing file contents to be updated by the Save method
        $results = Get-ArchiveItem $packageName
        $saveTestsErrors = 0
        foreach ($result in $oldResults) {
            if ($result.LastWriteTime -ge ($results | Where-Object Path -eq $result.Path).LastWriteTime) {
                It "Should have updated Modified date for file $($result.Path)" {
                    $result.LastWriteTime -lt ($results | Where-Object Path -eq $result.Path).LastWriteTime | Should Be $true
                }
                $saveTestsErrors++
            }
        }
        if ($saveTestsErrors -eq 0) {
            It "Ran silently $($oldResults.Length) file modification tests" {
                $saveTestsErrors | Should be 0
            }
        }
    }
}