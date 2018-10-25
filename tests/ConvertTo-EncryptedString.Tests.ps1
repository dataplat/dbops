Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    Import-Module "$here\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running $commandName tests" -ForegroundColor Cyan
}
. "$here\..\internal\functions\New-EncryptionKey.ps1"
. "$here\..\internal\functions\Get-EncryptionKey.ps1"

$keyPath = Join-PSFPath -Normalize "$here\etc\tmp_key.key"
$secret = 'MahS3cr#t'
$secureSecret = $secret | ConvertTo-SecureString -AsPlainText -Force

Describe "ConvertTo-EncryptedString tests" -Tag $commandName, UnitTests {
    BeforeAll {
        $null = Set-DBODefaultSetting -Name security.encryptionkey -Value $keyPath -Temporary
        $null = Set-DBODefaultSetting -Name security.usecustomencryptionkey -Value $true -Temporary
        if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
    }
    AfterAll {
        if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
        Reset-DBODefaultSetting -Name security.usecustomencryptionkey, security.encryptionkey
    }
    Context "Should return the strings encrypted" {
        It "should try to encrypt without a key in place" {
            $encString = $secureSecret | ConvertTo-EncryptedString -WarningVariable warnVar 3>$null
            $key = Get-EncryptionKey
            $encString | Should -Not -BeNullOrEmpty
            $warnVar | Should -BeLike '*The key file does not exist. Creating a new key at*'
        }
        It "should re-use existing key and decrypt" {
            $key = [System.IO.File]::ReadAllBytes($keyPath)
            $encString = $secureSecret | ConvertTo-EncryptedString
            $pwdString = $encString | ConvertTo-SecureString -Key $key
            [pscredential]::new('a', $pwdString).GetNetworkCredential().Password | Should -Be $secret
        }
    }
    Context "Negative tests" {
        It "Should fail to encrypt without a proper key" {
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            $file = New-Item -Path $keyPath -ItemType File
            [System.IO.File]::WriteAllBytes($keyPath, [byte[]](1, 2))
            { $secureSecret | ConvertTo-EncryptedString } | Should Throw 'The specified key is not valid'
        }
    }
}