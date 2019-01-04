function Get-ExternalLibrary {
    # Returns all external dependencies for RDBMS
    Param (
        [DBOps.ConnectionType]$Type
    )
    $jsonFile = Join-PSFPath -Normalize (Get-Item $PSScriptRoot).Parent.FullName "json\dbops.dependencies.json"
    $d = Get-Content $jsonFile -Raw | ConvertFrom-Json
    if ($Type) { $d.$Type | Where-Object { -Not $_.PSEdition -or $_.PSEdition -eq $PSVersionTable.PSEdition } }
    else {
        $rdbms = $d | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name
        $output = @{}
        foreach ($t in $rdbms) {
            $output += @{
                $t = $d.$t | Where-Object { -Not $_.PSEdition -or $_.PSEdition -eq $PSVersionTable.PSEdition }
            }
        }
        [pscustomobject]$output
    }
}