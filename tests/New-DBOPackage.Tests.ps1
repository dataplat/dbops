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

$workFolder = Join-PSFPath -Normalize "$here\etc" "$commandName.Tests.dbops"
$unpackedFolder = Join-Path $workFolder 'unpacked'
$packageName = Join-PSFPath -Normalize "$workFolder\dbopsTest.zip"
$scriptFolder = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success"
$fullConfig = Join-PSFPath -Normalize "$here\etc\tmp_full_config.json"
$fullConfigSource = Join-PSFPath -Normalize "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$encryptedString = $testPassword | ConvertTo-SecureString -Force -AsPlainText | ConvertTo-EncryptedString
$script1 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\1.sql"
$script2 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\2.sql"
$script3 = Join-PSFPath -Normalize "$here\etc\sqlserver-tests\success\3.sql"

Describe "New-DBOPackage tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $encryptedString | Out-File $fullConfig -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
    }
    Context "testing package contents" {
        AfterAll {
            if ((Test-Path $workFolder\*) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder\* }
        }
        It "should create a package file" {
            $testResults = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
        It "should contain query files" {
            $testResults = Get-ArchiveItem $packageName
            'query1.sql' | Should BeIn $testResults.Name
        }
        It "should contain module files" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($file in Get-DBOModuleFileList) {
                Join-PSFPath -Normalize Modules\dbops $file.Path | Should BeIn $testResults.Path
            }
        }
        It "should contain external modules" {
            $testResults = Get-ArchiveItem $packageName
            foreach ($module in Get-Module dbops | Select-Object -ExpandProperty RequiredModules) {
                $mName = $module.Name
                Join-PSFPath -Normalize Modules "$mName\$mName.psd1" | Should BeIn $testResults.Path
            }
        }
        It "should contain config files" {
            $testResults = Get-ArchiveItem $packageName
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
        It "should contain deploy files" {
            $testResults = Get-ArchiveItem $packageName
            'Deploy.ps1' | Should BeIn $testResults.Path
        }
        It "should create a zip package based on name without extension" {
            $testResults = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name ($packageName -replace '\.zip$', '') -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
        It "should create proper package with abolute path" {
            $p = New-DBOPackage -Path $packageName -ScriptPath "$here\etc\query1.sql" -Force -Absolute -Build 1;
            $testResults = Get-ArchiveItem $p
            $path = $here.Replace(':', '') -replace '^/', ''
            Join-PSFPath content\1 $path etc\query1.sql -Normalize | Should -BeIn $testResults.Path
        }
    }
    Context "current folder tests" {
        BeforeAll {
            Push-Location $workFolder
        }
        AfterAll {
            Pop-Location
            if ((Test-Path $workFolder\*) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder\* }
        }
        It "should create a package file in the current folder" {
            $testResults = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name (Split-Path $packageName -Leaf)
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
    }
    Context "testing pre and post-scripts" {
        AfterAll {
            if ((Test-Path $workFolder\*) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder\* }
        }
        It "should create a package file" {
            $testResults = New-DBOPackage -ScriptPath $script1 -Name $packageName -PreScriptPath $script1, $script2 -PostScriptPath $script3
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
        It "should contain pre-script files" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\.dbops.prescripts\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\.dbops.prescripts\2.sql' | Should BeIn $testResults.Path
        }
        It "should contain post-script files" {
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\.dbops.postscripts\3.sql' | Should BeIn $testResults.Path
        }
    }
    Context "testing slim package contents" {
        AfterAll {
            if ((Test-Path $workFolder\*) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder\* }
        }
        It "should create a package file" {
            $testResults = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -Slim -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be $null
            Test-Path $packageName | Should Be $true
        }
        It "should contain query files" {
            $testResults = Get-ArchiveItem $packageName
            'query1.sql' | Should BeIn $testResults.Name
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
            'dbops.config.json' | Should BeIn $testResults.Path
            'dbops.package.json' | Should BeIn $testResults.Path
        }
        It "should contain deploy files" {
            $testResults = Get-ArchiveItem $packageName
            'Deploy.ps1' | Should BeIn $testResults.Path
        }
        It "should be saved with a slim property" {
            $testResults = Get-DBOPackage -Path $packageName
            $testResults.Slim | Should Be $true
        }
        It "should have slim property in the package file" {
            $archiveItem = Get-ArchiveItem $packageName -Item 'dbops.package.json'
            $content = [DBOpsHelper]::DecodeBinaryText($archiveItem.ByteArray) | ConvertFrom-Json
            $content.Slim | Should -Be $true
        }
    }
    Context "testing configurations" {
        BeforeEach {
        }
        AfterEach {
            if (Test-Path "$workFolder\dbops.config.json") { Remove-Item "$workFolder\dbops.config.json" -Recurse }
        }
        It "should be able to apply config file" {
            $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -ConfigurationFile $fullConfig -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should Be "MyTestApp"
            $config.SqlInstance | Should Be "TestServer"
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 40
            $config.Encrypt | Should Be $null
            $config.Credential.UserName | Should Be "CredentialUser"
            [PSCredential]::new('test', ($config.Credential.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $config.Username | Should Be "TestUser"
            [PSCredential]::new('test', ($config.Password | ConvertFrom-EncryptedString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $true
            $config.Variables.foo | Should -Be 'bar'
            $config.Variables.boo | Should -Be 'far'
            $config.Schema | Should Be 'testschema'
        }
        It "should be able to apply custom config" {
            $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -Configuration @{ApplicationName = "MyTestApp2"; ConnectionTimeout = 4; Database = $null } -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should Be "MyTestApp2"
            $config.SqlInstance | Should Be 'localhost'
            $config.Database | Should Be $null
            $config.DeploymentMethod | Should Be 'NoTransaction'
            $config.ConnectionTimeout | Should Be 4
            $config.ExecutionTimeout | Should Be 0
            $config.Encrypt | Should Be $false
            $config.Credential | Should Be $null
            $config.Username | Should Be $null
            $config.Password | Should Be $null
            $config.SchemaVersionTable | Should Be 'SchemaVersions'
            $config.Silent | Should Be $false
            $config.Variables | Should Be $null
        }
        It "should be able to store variables" {
            $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -Configuration @{ ApplicationName = 'FooBar' } -Variables @{ MyVar = 'foo'; MyBar = 1; MyNull = $null } -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should Be 'FooBar'
            $config.SqlInstance | Should Be 'localhost'
            $config.Database | Should Be $null
            $config.DeploymentMethod | Should Be 'NoTransaction'
            $config.ConnectionTimeout | Should Be 30
            $config.ExecutionTimeout | Should Be 0
            $config.Encrypt | Should Be $false
            $config.Credential | Should Be $null
            $config.Username | Should Be $null
            $config.Password | Should Be $null
            $config.SchemaVersionTable | Should Be 'SchemaVersions'
            $config.Silent | Should Be $false
            $config.Variables.MyVar | Should Be 'foo'
            $config.Variables.MyBar | Should Be 1
            $config.Variables.MyNull | Should Be $null
        }
    }
    Context "testing input scenarios" {
        BeforeAll {
            Push-Location -Path "$here\etc\sqlserver-tests"
        }
        AfterAll {
            Pop-Location
        }
        It "should accept wildcard input" {
            $testResults = New-DBOPackage -ScriptPath "$here\etc\sqlserver-tests\*" -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\Cleanup.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\3.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\verification\select.sql' | Should BeIn $testResults.Path
        }
        It "should accept Get-Item <files> pipeline input" {
            $testResults = Get-Item "$scriptFolder\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should BeIn $testResults.Path
        }
        It "should accept Get-Item <files and folders> pipeline input" {
            $testResults = Get-Item "$here\etc\sqlserver-tests\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\Cleanup.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\success\3.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\transactional-failure\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\verification\select.sql' | Should BeIn $testResults.Path
        }
        It "should accept Get-ChildItem pipeline input" {
            $testResults = Get-ChildItem "$scriptFolder" -File -Recurse | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should BeIn $testResults.Path
        }
        It "should accept relative paths" {
            $testResults = New-DBOPackage -ScriptPath ".\success\*" -Build 'abracadabra' -Name $packageName -Force
            $testResults | Should Not Be $null
            $testResults.Name | Should Be (Split-Path $packageName -Leaf)
            $testResults.FullName | Should Be (Get-Item $packageName).FullName
            $testResults.ModuleVersion | Should Be (Get-Module dbops).Version
            $testResults.Version | Should Be 'abracadabra'
            $testResults.Builds[0].Scripts.PackagePath | Should Be @(
                Join-PSFPath -Normalize '1.sql'
                Join-PSFPath -Normalize '2.sql'
                Join-PSFPath -Normalize '3.sql'
            )
            Test-Path $packageName | Should Be $true
            $testResults = Get-ArchiveItem $packageName
            Join-PSFPath -Normalize 'content\abracadabra\1.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\2.sql' | Should BeIn $testResults.Path
            Join-PSFPath -Normalize 'content\abracadabra\3.sql' | Should BeIn $testResults.Path
        }
    }
    Context "runs negative tests" {
        It "should throw error when scripts with the same relative path is being added" {
            $testResult = $null
            try {
                $testResult = New-DBOPackage -Name $packageName -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike 'File * already exists*'
            $testResult | Should Be $null
        }
        It "should throw error when package already exists" {
            $testResult = $null
            try {
                $testResult = New-DBOPackage -Name $packageName -ScriptPath "$scriptFolder\*"
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*The file * already exists*'
            $testResult | Should Be $null
        }
        It "returns error when path does not exist" {
            try {
                $null = New-DBOPackage -Name $packageName -ScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
        }
        It "returns error when config file does not exist" {
            try {
                $null = New-DBOPackage -Name $packageName -ScriptPath "$here\etc\query1.sql" -ConfigurationFile 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*Config file * not found. Aborting.*'
        }
        It "returns error when prescript path does not exist" {
            { New-DBOPackage -Name $packageName -ScriptPath "$here\etc\query1.sql" -PreScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should Throw 'The following path is not valid'
        }
        It "returns error when postscript path does not exist" {
            { New-DBOPackage -Name $packageName -ScriptPath "$here\etc\query1.sql" -PostScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps' } | Should Throw 'The following path is not valid'
        }
        It "should fail when the same script is added twice" {
            { New-DBOPackage -Name $packageName -ScriptPath $script1, $script1 } | Should Throw 'already exists'
        }
    }
}
