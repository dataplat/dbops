Describe "New-DBOPackage tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        $encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
        $script1, $script2, $script3 = Get-SourceScript -Version 1, 2, 3
    }
    AfterAll {
        Remove-Workfolder
    }
    Context "testing package contents" {
        BeforeAll {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name $packageName
        }
        AfterAll {
            Reset-Workfolder
        }
        It "should create a package file" {
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            Test-Path $packageName | Should -Be $true
        }
        It "should contain query files" {
            $testResults = Get-ArchiveItem $packageName
            Split-Path $script1 -Leaf | Should -BeIn $testResults.Name
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -BeIn $testResults.Path
            }
        }
        It "should contain external modules" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($module in Get-Module dbops | Select-Object -ExpandProperty RequiredModules) {
                $mName = $module.Name
                Join-PSFPath -Normalize Modules "$mName\$mName.psd1" | Should -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageName
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
        It "should contain deploy files" {
            $testResults = Get-ArchiveItem $packageName
            'Deploy.ps1' | Should -BeIn $testResults.Path
        }
    }
    Context "testing package path variations" {
        AfterEach {
            Reset-Workfolder
        }
        It "should create a zip package based on name without extension" {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name ($packageName -replace '\.zip$', '') -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            Test-Path $packageName | Should -Be $true
        }
        It "should create proper package with abolute path" {
            $p = New-DBOPackage -Path $packageName -ScriptPath $script1 -Force -Absolute -Build 1;
            $testResults = Get-ArchiveItem $p
            $path = $script1.Replace(':', '') -replace '^/', ''
            Join-PSFPath content\1 $path -Normalize | Should -BeIn $testResults.Path
        }
    }
    Context "current folder tests" {
        BeforeAll {
            Push-Location $workFolder
        }
        AfterAll {
            Pop-Location
            Reset-Workfolder
        }
        It "should create a package file in the current folder" {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name (Split-Path $packageName -Leaf)
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            Test-Path $packageName | Should -Be $true
        }
    }
    Context "testing pre and post-scripts" {
        AfterAll {
            Reset-Workfolder
        }
        It "should create a package file" {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name $packageName -PreScriptPath $script1, $script2 -PostScriptPath $script3
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            Test-Path $packageName | Should -Be $true
        }
        It "should contain pre-script files" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\.dbops.prescripts\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should -BeIn $testResults.Path
        }
        It "should contain post-script files" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\.dbops.postscripts\3.sql' | Should -BeIn $testResults.Path
        }
    }
    Context "testing slim package contents" {
        BeforeAll {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name $packageName -Slim -Force
        }
        AfterAll {
            Reset-Workfolder
        }
        It "should create a package file" {
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be $null
            Test-Path $packageName | Should -Be $true
        }
        It "should contain query files" {
            $testResults = Get-ArchiveItem $packageName
            Split-Path $script1 -Leaf | Should -BeIn $testResults.Name
        }
        It "should not contain module files" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should -Not -BeIn $testResults.Path
            }
        }
        It "should not contain external modules" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($module in Get-Module dbops | Select-Object -ExpandProperty RequiredModules) {
                $mName = $module.Name
                Join-PSFPath -Normalize Modules "$mName\$mName.psd1" | Should -Not -BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageName
            'dbops.config.json' | Should -BeIn $testResults.Path
            'dbops.package.json' | Should -BeIn $testResults.Path
        }
        It "should contain deploy files" {
            $testResults = Get-ArchiveItem $packageName
            'Deploy.ps1' | Should -BeIn $testResults.Path
        }
        It "should be saved with a slim property" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should -Be $true
        }
        It "should have slim property in the package file" {
            . "$PSScriptRoot\..\..\internal\classes\DBOpsHelper.class.ps1"
            $archiveItem = Get-ArchiveItem $packageName -Item 'dbops.package.json'
            $content = [DBOpsHelper]::DecodeBinaryText($archiveItem.ByteArray) | ConvertFrom-Json
            $content.Slim | Should -Be $true
        }
    }
    Context "testing configurations" {
        BeforeEach {
            (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
            $null = New-DBOPackage -ScriptPath $script1 -Name $packageName -ConfigurationFile $fullConfig -Force
        }
        AfterEach {
            Reset-Workfolder
        }
        It "should be able to apply config file" {
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should -Be "MyTestApp"
            $config.SqlInstance | Should -Be "TestServer"
            $config.Database | Should -Be "MyTestDB"
            $config.DeploymentMethod | Should -Be "SingleTransaction"
            $config.ConnectionTimeout | Should -Be 40
            $config.Encrypt | Should -Be $null
            $config.Credential.UserName | Should -Be "CredentialUser"
            [PSCredential]::new('test', ($config.Credential.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should -Be "TestPassword"
            $config.Username | Should -Be "TestUser"
            [PSCredential]::new('test', ($config.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should -Be "TestPassword"
            $config.SchemaVersionTable | Should -Be "test.Table"
            $config.Silent | Should -Be $true
            $config.Variables.foo | Should -Be 'bar'
            $config.Variables.boo | Should -Be 'far'
            $config.Schema | Should -Be 'testschema'
        }
        It "should be able to apply custom config" {
            $null = New-DBOPackage -ScriptPath $script1 -Name $packageName -Configuration @{ApplicationName = "MyTestApp2"; ConnectionTimeout = 4; Database = $null } -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should -Be "MyTestApp2"
            $config.SqlInstance | Should -Be 'localhost'
            $config.Database | Should -Be $null
            $config.DeploymentMethod | Should -Be 'NoTransaction'
            $config.ConnectionTimeout | Should -Be 4
            $config.ExecutionTimeout | Should -Be 0
            $config.Encrypt | Should -Be $false
            $config.Credential | Should -Be $null
            $config.Username | Should -Be $null
            $config.Password | Should -Be $null
            $config.SchemaVersionTable | Should -Be 'SchemaVersions'
            $config.Silent | Should -Be $false
            $config.Variables | Should -Be $null
        }
        It "should be able to store variables" {
            $null = New-DBOPackage -ScriptPath $script1 -Name $packageName -Configuration @{ ApplicationName = 'FooBar' } -Variables @{ MyVar = 'foo'; MyBar = 1; MyNull = $null } -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should -Be 'FooBar'
            $config.SqlInstance | Should -Be 'localhost'
            $config.Database | Should -Be $null
            $config.DeploymentMethod | Should -Be 'NoTransaction'
            $config.ConnectionTimeout | Should -Be 30
            $config.ExecutionTimeout | Should -Be 0
            $config.Encrypt | Should -Be $false
            $config.Credential | Should -Be $null
            $config.Username | Should -Be $null
            $config.Password | Should -Be $null
            $config.SchemaVersionTable | Should -Be 'SchemaVersions'
            $config.Silent | Should -Be $false
            $config.Variables.MyVar | Should -Be 'foo'
            $config.Variables.MyBar | Should -Be 1
            $config.Variables.MyNull | Should -Be $null
        }
    }
    Context "testing input scenarios" {
        BeforeAll {
            Push-Location -Path $etcScriptFolder
        }
        AfterAll {
            Pop-Location
        }
        It "should accept wildcard input" {
            $testResults = New-DBOPackage -ScriptPath "$etcScriptFolder\*" -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Version | Should -Be 'abracadabra'
            Test-Path $packageName | Should -Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\Cleanup.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\3.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\verification\select.sql' | Should -BeIn $testResults.Path
        }
        It "should accept Get-Item files pipeline input" {
            $testResults = Get-Item "$scriptFolder\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Version | Should -Be 'abracadabra'
            Test-Path $packageName | Should -Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should -BeIn $testResults.Path
        }
        It "should accept Get-Item files and folders pipeline input" {
            $testResults = Get-Item "$etcScriptFolder\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Version | Should -Be 'abracadabra'
            Test-Path $packageName | Should -Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\Cleanup.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\3.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\verification\select.sql' | Should -BeIn $testResults.Path
        }
        It "should accept Get-ChildItem pipeline input" {
            $testResults = Get-ChildItem "$scriptFolder" -File -Recurse | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Version | Should -Be 'abracadabra'
            Test-Path $packageName | Should -Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should -BeIn $testResults.Path
        }
        It "should accept relative paths" {
            $testResults = New-DBOPackage -ScriptPath ".\success\*" -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should -Not -Be $null
            $testResults.Name | Should -Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should -Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should -Be (Get-Module dbops).Version
            $testResults.Version | Should -Be 'abracadabra'
            $testResults.Builds[0].Scripts.PackagePath | Should -Be @(
                Join-PSFPath -Normalize '1.sql'
                Join-PSFPath -Normalize '2.sql'
                Join-PSFPath -Normalize '3.sql'
            )
            Test-Path $packageName | Should -Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should -BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should -BeIn $testResults.Path
        }
    }
    Context "runs negative tests" {
        AfterEach {
            Reset-Workfolder
        }
        It "should throw error when scripts with the same relative path is being added" {
            {
                New-DBOPackage -Name $packageName -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
            } | Should -Throw 'File * already exists*'
        }
        It "should throw error when package already exists" {
            New-Item $packageName
            {
                New-DBOPackage -Name $packageName -ScriptPath "$scriptFolder\*"
            } | Should -Throw '*The file * already exists*'
        }
        It "returns error when path does not exist" {
            {
                New-DBOPackage -Name $packageName -ScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            } | Should -Throw '*The following path is not valid*'
        }
        It "returns error when config file does not exist" {
            {
                New-DBOPackage -Name $packageName -ScriptPath $script1 -ConfigurationFile 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            } | Should -Throw '*Config file * not found. Aborting.*'
        }
        It "returns error when prescript path does not exist" {
            { New-DBOPackage -Name $packageName -ScriptPath $script1 -PreScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should -Throw 'The following path is not valid*'
        }
        It "returns error when postscript path does not exist" {
            { New-DBOPackage -Name $packageName -ScriptPath $script1 -PostScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should -Throw 'The following path is not valid*'
        }
        It "should fail when the same script is added twice" {
            { New-DBOPackage -Name $packageName -ScriptPath $script1, $script1 } | Should -Throw '*already exists*'
        }
    }
}
