Function Get-VariableTokens {
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
        [string]$InputString
    )
    [regex]::matches($InputString, "\#\{([a-zA-Z0-9.]*)\}") | ForEach-Object { $_.Groups[1].Value }
}