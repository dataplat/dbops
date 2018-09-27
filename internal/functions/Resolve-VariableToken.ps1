Function Resolve-VariableToken {
    <#
    .SYNOPSIS
    Replaces all the tokens in a string with provided variables
    
    .DESCRIPTION
    Parses input string and replaces all the #{tokens} inside it with provided variables
    
    .PARAMETER InputString
    String to parse
    
    .PARAMETER Runtime
    Variables collection. Token names should match keys in the hashtable
    
    .EXAMPLE
    Resolve-VariableToken -InputString "SELECT '#{foo}' as str" -Runtime @{ foo = 'bar'}
    #>
    [CmdletBinding()]
    Param (
        [object[]]$InputObject,
        [hashtable]$Runtime
    )
    foreach ($obj in $InputObject) {
        if ($obj -is [string]) {
            Write-PSFMessage -Level Debug -Message "Processing string: $obj"
            $output = $obj
            foreach ($token in (Get-VariableTokens $obj)) {
                Write-PSFMessage -Level Debug -Message "Processing token: $token"
                #Replace variables found in the config
                $tokenRegEx = "\#\{$token\}"
                if ($Runtime) {
                    if ($Runtime.Keys -contains $token) {
                        $output = $output -replace $tokenRegEx, $Runtime.$token
                    }
                }
                Write-PSFMessage -Level Debug -Message "String after replace: $obj"
            }
            $output
        }
        else {
            $obj
        }
    }
}