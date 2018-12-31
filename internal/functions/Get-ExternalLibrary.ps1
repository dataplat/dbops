function Get-ExternalLibrary {
    # Returns all external dependencies for RDBMS
    Param (
        [string]$Type
    )
    $jsonFile = Join-PSFPath -Normalize (Get-Item $PSScriptRoot).Parent.FullName "json\dbops.dependencies.json"
    $d = Get-Content $jsonFile -Raw | ConvertFrom-Json
    if ($Type) { $d.$Type }
    else { $d }
}