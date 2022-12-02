Describe "ConvertFrom-EncryptedString tests" -Tag UnitTests {
    BeforeAll {
        $commandName = $PSCommandPath.Replace(".Tests.ps1", "").Replace($PSScriptRoot, "").Trim("/")
        . $PSScriptRoot\fixtures.ps1 -CommandName $commandName

        New-Workfolder -Force

        . "$PSScriptRoot\..\..\internal\functions\New-EncryptionKey.ps1"
        . "$PSScriptRoot\..\..\internal\functions\Get-EncryptionKey.ps1"

        $keyPath = Join-PSFPath -Normalize $workFolder "tmp_key.key"
        $secret = 'MahS3cr#t'
        $secureSecret = $secret | ConvertTo-SecureString -AsPlainText -Force

        $null = Set-DBODefaultSetting -Name security.encryptionkey -Value $keyPath -Temporary
        $null = Set-DBODefaultSetting -Name security.usecustomencryptionkey -Value $true -Temporary
        New-EncryptionKey 3>$null
    }
    AfterAll {
        Remove-Workfolder
        Reset-DBODefaultSetting -Name security.usecustomencryptionkey, security.encryptionkey
    }
    Context "Should return the strings decrypted" {
        It "should re-use existing key and decrypt" {
            $key = [System.IO.File]::ReadAllBytes($keyPath)
            $encString = $secureSecret | ConvertFrom-SecureString -Key $key
            $pwdString = $encString | ConvertFrom-EncryptedString
            [pscredential]::new('a', $pwdString).GetNetworkCredential().Password | Should -Be $secret
        }
    }
    Context "Negative tests" {
        BeforeAll {
            $null = Set-DBODefaultSetting -Name security.encryptionkey -Value $keyPath -Temporary
            $null = Set-DBODefaultSetting -Name security.usecustomencryptionkey -Value $true -Temporary
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            New-EncryptionKey 3>$null
            $key = [System.IO.File]::ReadAllBytes($keyPath)
            $encString = $secureSecret | ConvertFrom-SecureString -Key $key
        }
        AfterAll {
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            Reset-DBODefaultSetting -Name security.usecustomencryptionkey, security.encryptionkey
        }
        It "Should fail to decrypt without a key" {
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            { $encString | ConvertFrom-EncryptedString } | Should -Throw 'Encryption key not found'
        }
        It "Should fail to decrypt without a proper key" {
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            $file = New-Item -Path $keyPath -ItemType File
            [System.IO.File]::WriteAllBytes($keyPath, [byte[]](1, 2))
            { $encString | ConvertFrom-EncryptedString } | Should -Throw 'The specified key is not valid*'
        }
    }
}