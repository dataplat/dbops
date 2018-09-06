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
$outConfig = "$here\etc\out_full_config.json"
$fullConfig = "$here\etc\tmp_full_config.json"
$fullConfigSource = "$here\etc\full_config.json"
$testPassword = 'TestPassword'
$securePassword = $testPassword | ConvertTo-SecureString -Force -AsPlainText
$fromSecureString = $securePassword|  ConvertFrom-SecureString

Describe "DBOpsConfig class tests" -Tag $commandName, UnitTests, DBOpsConfig {
    BeforeAll {
        (Get-Content $fullConfigSource -Raw) -replace 'replaceMe', $fromSecureString | Out-File $fullConfig -Force
    }
    AfterAll {
        if (Test-Path $fullConfig) { Remove-Item $fullConfig }
        if (Test-Path $outConfig) { Remove-Item $outConfig }
    }
    Context "tests DBOpsConfig constructors" {
        It "Should return an empty config by default" {
            $result = [DBOpsConfig]::new()
            foreach ($prop in $result.psobject.properties.name) {
                $result.$prop | Should Be (Get-PSFConfigValue -FullName dbops.$prop)
            }
        }
        It "Should return empty configuration from empty config file" {
            $result = [DBOpsConfig]::new((Get-Content "$here\etc\empty_config.json" -Raw))
            $result.ApplicationName | Should Be $null
            $result.SqlInstance | Should Be $null
            $result.Database | Should Be $null
            $result.DeploymentMethod | Should Be $null
            $result.ConnectionTimeout | Should Be $null
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential | Should Be $null
            $result.Username | Should Be $null
            $result.Password | Should Be $null
            $result.SchemaVersionTable | Should Be $null
            $result.Silent | Should Be $null
            $result.Variables | Should Be $null
            $result.Schema | Should BeNullOrEmpty
        }
        It "Should return all configurations from the config file" {
            $result = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            $result.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
        }
    }
    Context "tests other methods of DBOpsConfig" {
        It "should test AsHashtable method" {
            $result = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).AsHashtable()
            $result.GetType().Name | Should Be 'hashtable'
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            $result.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
        }
        It "should test SetValue method" {
            $config = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            #String property
            $config.SetValue('ApplicationName', 'MyApp2')
            $config.ApplicationName | Should Be 'MyApp2'
            $config.SetValue('ApplicationName', $null)
            $config.ApplicationName | Should Be $null
            $config.SetValue('ApplicationName', 123)
            $config.ApplicationName | Should Be '123'
            #Int property
            $config.SetValue('ConnectionTimeout', 11)
            $config.ConnectionTimeout | Should Be 11
            $config.SetValue('ConnectionTimeout', $null)
            $config.ConnectionTimeout | Should Be $null
            $config.SetValue('ConnectionTimeout', '123')
            $config.ConnectionTimeout | Should Be 123
            { $config.SetValue('ConnectionTimeout', 'string') } | Should Throw
            #Bool property
            $config.SetValue('Silent', $false)
            $config.Silent | Should Be $false
            $config.SetValue('Silent', $null)
            $config.Silent | Should Be $null
            $config.SetValue('Silent', 2)
            $config.Silent | Should Be $true
            $config.SetValue('Silent', 0)
            $config.Silent | Should Be $false
            $config.SetValue('Silent', 'string')
            $config.Silent | Should Be $true
            #SecureString property
            $config.SetValue('Password', $fromSecureString)
            [PSCredential]::new('test', $config.Password).GetNetworkCredential().Password | Should Be $testPassword
            $config.SetValue('Password', $null)
            $config.Password | Should Be $null
            #PSCredential property
            $config.SetValue('Credential', ([pscredential]::new('CredentialUser', $securePassword)))
            $config.Credential.UserName | Should Be 'CredentialUser'
            $config.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $config.SetValue('Credential', $null)
            $config.Credential | Should Be $null
            #Negatives
            { $config.SetValue('AppplicationName', 'MyApp3') } | Should Throw
        }
        It "should test ExportToJson method" {
            $result = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).ExportToJson() | ConvertFrom-Json -ErrorAction Stop
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            [PSCredential]::new('test', ($result.Credential.Password | ConvertTo-SecureString)).GetNetworkCredential().Password | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', ($result.Password | ConvertTo-SecureString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
        }
        It "should test Merge method into full config" {
            $config = [DBOpsConfig]::new((Get-Content $fullConfig -Raw))
            $hashtable = @{
                ApplicationName   = 'MyTestApp2'
                ConnectionTimeout = 0
                SqlInstance       = $null
                Silent            = $false
                ExecutionTimeout  = 20
                Schema            = "test3"
                Password          = $null
                Credential        = $null
            }
            $config.Merge($hashtable)
            $config.ApplicationName | Should Be "MyTestApp2"
            $config.SqlInstance | Should Be $null
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 0
            $config.ExecutionTimeout | Should Be 20
            $config.Encrypt | Should Be $null
            $config.Credential | Should Be $null
            $config.Username | Should Be "TestUser"
            $config.Password | Should Be $null
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $false
            $config.Variables | Should Be $null
            $config.Schema | Should Be "test3"
            #negative
            { $config.Merge(@{foo = 'bar'}) } | Should Throw
            { $config.Merge($null) } | Should Throw
        }
        It "should test Merge method into empty config" {
            $config = [DBOpsConfig]::new()
            $hashtable = [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).AsHashtable()
            $config.Merge($hashtable)
            $config.ApplicationName | Should Be "MyTestApp"
            $config.SqlInstance | Should Be "TestServer"
            $config.Database | Should Be "MyTestDB"
            $config.DeploymentMethod | Should Be "SingleTransaction"
            $config.ConnectionTimeout | Should Be 40
            $config.ExecutionTimeout | Should Be 0
            $config.Encrypt | Should Be $null
            $config.Credential.UserName | Should Be 'CredentialUser'
            $config.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $config.Username | Should Be "TestUser"
            [PSCredential]::new('test', $config.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $config.SchemaVersionTable | Should Be "test.Table"
            $config.Silent | Should Be $true
            $config.Variables | Should Be $null
            $config.Schema | Should Be "testschema"
            #negative
            { $config.Merge(@{foo = 'bar'}) } | Should Throw
            { $config.Merge($null) } | Should Throw
        }
    }
    Context "tests Save/Alter methods" {
        AfterAll {
            if (Test-Path $packageName) { Remove-Item $packageName }
        }
        It "should test Save method" {
            #Generate new package file
            $pkg = [DBOpsPackage]::new()
            $pkg.Configuration.ApplicationName = 'TestApp2'
            $pkg.SaveToFile($packageName)

            #Open zip file stream
            $writeMode = [System.IO.FileMode]::Open
            $stream = [FileStream]::new($packageName, $writeMode)
            try {
                #Open zip file
                $zip = [ZipArchive]::new($stream, [ZipArchiveMode]::Update)
                try {
                    #Initiate saving
                    $pkg.Configuration.Save($zip)
                }
                catch {
                    throw $_
                }
                finally {
                    #Close archive
                    $zip.Dispose()
                }
            }
            catch {
                throw $_
            }
            finally {
                #Close archive
                $stream.Dispose()
            }
            $results = Get-ArchiveItem $packageName
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
        }
        It "Should load package successfully after saving it" {
            $pkg = [DBOpsPackage]::new($packageName)
            $pkg.Configuration.ApplicationName | Should Be 'TestApp2'
        }
        It "should test Alter method" {
            $pkg = [DBOpsPackage]::new($packageName)
            $pkg.Configuration.ApplicationName = 'TestApp3'
            $pkg.Configuration.Alter()
            $results = Get-ArchiveItem "$packageName"
            foreach ($file in (Get-DBOModuleFileList)) {
                Join-Path 'Modules\dbops' $file.Path | Should BeIn $results.Path
            }
            'dbops.config.json' | Should BeIn $results.Path
            'dbops.package.json' | Should BeIn $results.Path
            'Deploy.ps1' | Should BeIn $results.Path
        }
        It "Should load package successfully after saving it" {
            $p = [DBOpsPackage]::new($packageName)
            $p.Configuration.ApplicationName | Should Be 'TestApp3'
        }
        It "should test SaveToFile method" {
            [DBOpsConfig]::new((Get-Content $fullConfig -Raw)).SaveToFile($outConfig)
            $result = Get-Content $outConfig -Raw | ConvertFrom-Json -ErrorAction Stop
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            [PSCredential]::new('test', ($result.Credential.Password | ConvertTo-SecureString)).GetNetworkCredential().Password | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', ($result.Password | ConvertTo-SecureString)).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
        }
    }
    Context "tests static methods of DBOpsConfig" {
        It "should test static GetDeployFile method" {
            $f = [DBOpsConfig]::GetDeployFile()
            $f.Type | Should Be 'Misc'
            $f.Path | Should BeLike '*\Deploy.ps1'
            $f.Name | Should Be 'Deploy.ps1'
        }
        It "should test static FromFile method" {
            $result = [DBOpsConfig]::FromFile($fullConfig)
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            $result.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
            #negatives
            { [DBOpsConfig]::FromFile("$here\etc\notajsonfile.json") } | Should Throw
            { [DBOpsConfig]::FromFile("nonexisting\file") } | Should Throw
            { [DBOpsConfig]::FromFile($null) } | Should Throw
        }
        It "should test static FromJsonString method" {
            $result = [DBOpsConfig]::FromJsonString((Get-Content $fullConfig -Raw))
            $result.ApplicationName | Should Be "MyTestApp"
            $result.SqlInstance | Should Be "TestServer"
            $result.Database | Should Be "MyTestDB"
            $result.DeploymentMethod | Should Be "SingleTransaction"
            $result.ConnectionTimeout | Should Be 40
            $result.ExecutionTimeout | Should Be 0
            $result.Encrypt | Should Be $null
            $result.Credential.UserName | Should Be 'CredentialUser'
            $result.Credential.GetNetworkCredential().Password  | Should Be $testPassword
            $result.Username | Should Be "TestUser"
            [PSCredential]::new('test', $result.Password).GetNetworkCredential().Password | Should Be "TestPassword"
            $result.SchemaVersionTable | Should Be "test.Table"
            $result.Silent | Should Be $true
            $result.Variables | Should Be $null
            $result.Schema | Should Be "testschema"
            #negatives
            { [DBOpsConfig]::FromJsonString((Get-Content "$here\etc\notajsonfile.json" -Raw)) } | Should Throw
            { [DBOpsConfig]::FromJsonString($null) } | Should Throw
            { [DBOpsConfig]::FromJsonString('') } | Should Throw
        }
    }
}