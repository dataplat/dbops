Function Get-VariableToken {
    <#
    .SYNOPSIS
    Get a list of #{tokens} from the string

    .DESCRIPTION
    Returns an array of tokens that matches token regex #{token}

    .PARAMETER InputString
    String to run regex against

    .EXAMPLE
    Get-VariableTokens '#{foo} myString #{bar}' # returns @('foo','bar')
    #>
    Param (
        [string]$InputString,
        [string]$RegexString
    )
    [regex]::matches($InputString, $RegexString) | ForEach-Object { $_.Groups[1].Value }
}