Describe "ConvertTo-EncryptedString tests" -Tag UnitTests {
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
    }
    AfterAll {
        Remove-Workfolder
        Reset-DBODefaultSetting -Name security.usecustomencryptionkey, security.encryptionkey
    }
    Context "Should return the strings encrypted" {
        It "should try to encrypt without a key in place" {
            $encString = $secureSecret | ConvertTo-EncryptedString -WarningVariable warnVar 3>$null
            $encString | Should -Not -BeNullOrEmpty
            $warnVar | Should -BeLike '*The key file does not exist. Creating a new key at*'
        }
        It "should re-use existing key and decrypt" {
            $encString = $secureSecret | ConvertTo-EncryptedString -WarningVariable warnVar 3>$null
            $key = Get-EncryptionKey
            $key = [System.IO.File]::ReadAllBytes($keyPath)
            $encString = $secureSecret | ConvertTo-EncryptedString
            $pwdString = $encString | ConvertTo-SecureString -Key $key
            [pscredential]::new('a', $pwdString).GetNetworkCredential().Password | Should -Be $secret
        }
    }
    Context "Negative tests" {
        It "Should fail to encrypt without a proper key" {
            if (Test-Path $keyPath) { Remove-Item $keyPath -Force }
            $null = New-Item -Path $keyPath -ItemType File
            [System.IO.File]::WriteAllBytes($keyPath, [byte[]](1, 2))
            { $secureSecret | ConvertTo-EncryptedString } | Should -Throw 'The specified key is not valid*'
        }
    }
}