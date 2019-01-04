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
        [object]$Runtime
    )
    foreach ($obj in $InputObject) {
        if ($obj -is [string]) {
            $output = $obj
            foreach ($token in (Get-VariableTokens $obj)) {
                #Replace variables found in the config
                $tokenRegEx = "\#\{$token\}"
                if ($Runtime) {
                    if ($Runtime -is [hashtable]) { $variableList = $Runtime.Keys }
                    else { $variableList = $Runtime.psobject.Properties.Name }
                    if ($variableList -contains $token) {
                        Write-PSFMessage -Level Debug -Message "Replacing token $token"
                        $output = $output -replace $tokenRegEx, $Runtime.$token
                    }
                }
            }
            $output
        }
        else {
            $obj
        }
    }
}