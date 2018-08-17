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
$packageName = "$workFolder\dbopsTest.zip"
$scriptFolder = "$here\etc\install-tests\success"

Describe "New-DBOPackage tests" -Tag $commandName, UnitTests {
    BeforeAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
        $null = New-Item $workFolder -ItemType Directory -Force
        $null = New-Item $unpackedFolder -ItemType Directory -Force
    }
    AfterAll {
        if ((Test-Path $workFolder) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder -Recurse }
    }
    Context "testing package contents" {
        AfterAll {
            if ((Test-Path $workFolder\*) -and $workFolder -like '*.Tests.dbops') { Remove-Item $workFolder\* }
        }
        It "should create a package file" {
            $results = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
        It "should contain query files" {
            $results = Get-ArchiveItem $packageName
            'query1.sql' | Should BeIn $results.Name
        }
        It "should contain module files" {
            $results = Get-ArchiveItem $packageName
            'Modules\dbops\dbops.psd1' | Should BeIn $results.Path
            'Modules\dbops\bin\dbup-sqlserver.dll' | Should BeIn $results.Path
        }
        It "should contain config files" {
            $results = Get-ArchiveItem $packageName
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
        }
        It "should contain deploy files" {
            $results = Get-ArchiveItem $packageName
            'Deploy.ps1' | Should BeIn $results.Path
        }
        It "should create a zip package based on name without extension" {
            $results = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name ($packageName -replace '\.zip$','') -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
    }
    Context "current folder tests" {
        BeforeAll {
            Push-Location $workFolder
        }
        AfterAll {
            Pop-Location
        }
        It "should create a package file in the current folder" {
            $results = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name (Split-Path $packageName -Leaf)
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            Test-Path $packageName | Should Be $true
        }
    }
    Context "testing configurations" {
        BeforeEach {
        }
        AfterEach {
            if (Test-Path "$workFolder\dbops.config.json") { Remove-Item "$workFolder\dbops.config.json" -Recurse }
        }
        It "should be able to apply config file" {
            $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -ConfigurationFile "$here\etc\full_config.json" -Force
            $null = Expand-ArchiveItem -Path $packageName -DestinationPath $workFolder -Item 'dbops.config.json'
            $config = Get-Content "$workFolder\dbops.config.json" | ConvertFrom-Json
            $config.ApplicationName | Should Be "MyTestApp"
            $config.SqlInstance | Should Be "TestServer"
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 40
            $config.Encrypt | Should Be $null
            $config.Credential | Should Be $null
            $config.Username | Should Be "TestUser"
            $config.Password | Should Be "TestPassword"
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $true
            $config.Variables | Should Be $null
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
            $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -Name $packageName -Configuration @{ ApplicationName = 'FooBar' } -Variables @{ MyVar = 'foo'; MyBar = 1; MyNull = $null} -Force
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
            Push-Location -Path "$here\etc\install-tests"
        }
        AfterAll {
            Pop-Location
        }
        It "should accept wildcard input" {
            $results = New-DBOPackage -ScriptPath "$here\etc\install-tests\*" -Build 'abracadabra' -Name $packageName -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            $results.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $results = Get-ArchiveItem $packageName
            'content\abracadabra\Cleanup.sql' | Should BeIn $results.Path
            'content\abracadabra\success\1.sql' | Should BeIn $results.Path
            'content\abracadabra\success\2.sql' | Should BeIn $results.Path
            'content\abracadabra\success\3.sql' | Should BeIn $results.Path
            'content\abracadabra\transactional-failure\1.sql' | Should BeIn $results.Path
            'content\abracadabra\transactional-failure\2.sql' | Should BeIn $results.Path
            'content\abracadabra\verification\select.sql' | Should BeIn $results.Path
        }
        It "should accept Get-Item <files> pipeline input" {
            $results = Get-Item "$scriptFolder\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            $results.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $results = Get-ArchiveItem $packageName
            'content\abracadabra\1.sql' | Should BeIn $results.Path
            'content\abracadabra\2.sql' | Should BeIn $results.Path
            'content\abracadabra\3.sql' | Should BeIn $results.Path
        }
        It "should accept Get-Item <files and folders> pipeline input" {
            $results = Get-Item "$here\etc\install-tests\*" | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            $results.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $results = Get-ArchiveItem $packageName
            'content\abracadabra\Cleanup.sql' | Should BeIn $results.Path
            'content\abracadabra\success\1.sql' | Should BeIn $results.Path
            'content\abracadabra\success\2.sql' | Should BeIn $results.Path
            'content\abracadabra\success\3.sql' | Should BeIn $results.Path
            'content\abracadabra\transactional-failure\1.sql' | Should BeIn $results.Path
            'content\abracadabra\transactional-failure\2.sql' | Should BeIn $results.Path
            'content\abracadabra\verification\select.sql' | Should BeIn $results.Path
        }
        It "should accept Get-ChildItem pipeline input" {
            $results = Get-ChildItem "$scriptFolder" -File -Recurse | New-DBOPackage -Build 'abracadabra' -Name $packageName -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            $results.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $results = Get-ArchiveItem $packageName
            'content\abracadabra\1.sql' | Should BeIn $results.Path
            'content\abracadabra\2.sql' | Should BeIn $results.Path
            'content\abracadabra\3.sql' | Should BeIn $results.Path
        }
        It "should accept relative paths" {
            $results = New-DBOPackage -ScriptPath ".\success\*" -Build 'abracadabra' -Name $packageName -Force
            $results | Should Not Be $null
            $results.Name | Should Be (Split-Path $packageName -Leaf)
            $results.FullName | Should Be (Get-Item $packageName).FullName
            $results.ModuleVersion | Should Be (Get-Module dbops).Version
            $results.Version | Should Be 'abracadabra'
            Test-Path $packageName | Should Be $true
            $results = Get-ArchiveItem $packageName
            'content\abracadabra\1.sql' | Should BeIn $results.Path
            'content\abracadabra\2.sql' | Should BeIn $results.Path
            'content\abracadabra\3.sql' | Should BeIn $results.Path
        }
    }
    Context "runs negative tests" {
        It "should throw error when scripts with the same relative path is being added" {
            try {
                $null = New-DBOPackage -Name $packageName -ScriptPath "$scriptFolder\*", "$scriptFolder\..\transactional-failure\*"
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*File * already exists in*'
        }
        It "returns error when path does not exist" {
            try {
                $null = New-DBOPackage -ScriptPath 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*The following path is not valid*'
        }
        It "returns error when config file does not exist" {
            try {
                $null = New-DBOPackage -ScriptPath "$here\etc\query1.sql" -ConfigurationFile 'asduwheiruwnfelwefo\sdfpoijfdsf.sps'
            }
            catch {
                $errorResult = $_
            }
            $errorResult.Exception.Message -join ';' | Should BeLike '*Config file * not found. Aborting.*'
        }
    }
}
