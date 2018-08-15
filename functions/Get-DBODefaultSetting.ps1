function Get-DBODefaultSetting {
    <#
        .SYNOPSIS
            Retrieves default configuration elements by name.

        .DESCRIPTION
            Retrieves default configuration elements by name.
            Can be used to search the existing defaults list.

        .PARAMETER Name
            Default: "*"
            The name of the configuration element(s) to retrieve.
            May be any string, supports wildcards.

        .PARAMETER Force
            Overrides the default behavior and also displays hidden configuration values.
        
        .PARAMETER Value
            Extracts the value instead of returning the configuration object.
        .NOTES

        .EXAMPLE
            PS C:\> Get-DBODefaultSetting 'ExecutionTimeout'

            Retrieves the configuration element for the key "ExecutionTimeout"

        .EXAMPLE
            PS C:\> Get-DBODefaultSetting -Force

            Retrieve all configuration elements from the module, even hidden ones.
    #>
    [CmdletBinding(DefaultParameterSetName = "FullName")]
    Param (
        [Parameter(ParameterSetName = "FullName", Position = 0)]
        [Alias("FullName")]
        [string[]]$Name = "*",
        [switch]$Force,
        [switch]$Value
    )
    switch ($Value) {
        $true { 
            if ($Name.count -gt 1) {
                Write-PSFMessage -Level Warning -Message "Provide a single item when requesting a value"
                return
            }
            Get-PSFConfigValue -FullName "dbops.$Name" 
        }
        $false {
            foreach ($n in $Name) {
                Get-PSFConfig -Module dbops -Name $n -Force:$Force | Select-Object @{ Name = "Name"; Expression = {$_.FullName -replace '^dbops\.', '' } }, Value, Description
            }
        }
    }
}
