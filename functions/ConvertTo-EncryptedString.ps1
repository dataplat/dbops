Function ConvertTo-EncryptedString {
    <#
    .SYNOPSIS
    Converts a SecureString object to an encrypted string.
    
    .DESCRIPTION
    Converts a SecureString object to an encrypted string with an option to use a custom key.
    
    Key path can be defined by:
    PS> Get/Set-DBODefaultSetting -Name security.encryptionkey

    Custom key is enforced in a Unix environment by a default setting security.usecustomencryptionkey
    PS> Get/Set-DBODefaultSetting -Name security.usecustomencryptionkey
   
    .PARAMETER SecureString
    SecureString to be encrypted
    
    .PARAMETER Confirm
    Prompts to confirm certain actions

    .PARAMETER WhatIf
    Shows what would happen if the command would execute, but does not actually perform the command

    .EXAMPLE
    # Converts a password provided by user to an encrypted string
    ConvertTo-EncryptedString -String (Read-Host -AsSecureString)
    
    .NOTES
    
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [secureString]$SecureString
    )
    $params = @{ SecureString = $SecureString }
    if (Get-DBODefaultSetting -Name security.usecustomencryptionkey -Value) {
        $key = Get-EncryptionKey
        if (!$key -and $PSCmdlet.ShouldProcess("Generating a new encryption key")) {
            $key = New-EncryptionKey
        }
        $params += @{ Key = $key }
    }
    try {
        ConvertFrom-SecureString @params
    }
    catch {
        Stop-PSFFunction -Message "Failed to encrypt the secure string" -ErrorRecord $_ -EnableException $true
    }
}