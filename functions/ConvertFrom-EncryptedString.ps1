Function ConvertFrom-EncryptedString {
    <#
    .SYNOPSIS
    Converts an encrypted string to a SecureString object.
    
    .DESCRIPTION
    Converts an encrypted string to a SecureString object with an option to use a custom key.
    
    Key path can be defined by:
    PS> Get/Set-DBODefaultSetting -Name security.encryptionkey

    Custom key is enforced in a Unix environment by a default setting security.usecustomencryptionkey
    PS> Get/Set-DBODefaultSetting -Name security.usecustomencryptionkey
   
    .PARAMETER String
    String to be decrypted

    .EXAMPLE
    # Converts a password provided by user to an encrypted string
    $encrypted = ConvertTo-EncryptedString -String (Read-Host -AsSecureString)
    $decrypted = ConvertFrom-EncryptedString -String $encrypted
    
    .NOTES
    
    #>
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [String]$String
    )
    $params = @{ String = $String }
    if (Get-DBODefaultSetting -Name security.usecustomencryptionkey -Value) {
        $key = Get-EncryptionKey
        if ($null -eq $key) {
            Stop-PSFFunction -Message "Encryption key not found" -EnableException $true
        }
        $params += @{ Key = Get-EncryptionKey }
    }
    try {
        ConvertTo-SecureString @params -ErrorAction Stop
    }
    catch {
        Stop-PSFFunction -Message "Failed to decrypt the secure string" -ErrorRecord $_ -EnableException $true
    }
}