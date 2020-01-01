function Get-ExternalLibrary {
    # Returns all external dependencies for RDBMS
    Param (
        [DBOps.ConnectionType]$Type
    )
    Function Get-PackageList {
        Param (
            $Node
        )
        $jsonClause = {
            ((-Not $_.PSEdition) -or ($_.PSEdition -eq $PSVersionTable.PSEdition)) -and
            ((-Not $_.DotNetCore) -or ($runtime -ge [version]$_.DotNetCore))
        }
        $output = @()
        $applicableDependencies = $Node | Where-Object $jsonClause
        $groupedDependencies = $applicableDependencies | Group-Object -Property Name
        foreach ($group in $groupedDependencies) {
            $selectedGroup = $group.Group | Sort-Object -Property @{ Expression = { $_.DotNetCore -as [version] }; Descending = $true } | Select-Object -First 1
            if ($selectedGroup.Dependencies) {
                $output += Get-PackageList $selectedGroup.Dependencies
            }
            $output += $selectedGroup | Select-Object Name, MinimumVersion, RequiredVersion, MaximumVersion, Path
        }
        return $output
    }
    $jsonFile = Join-PSFPath -Normalize (Get-Item $PSScriptRoot).Parent.FullName "json\dbops.dependencies.json"
    $dependencies = Get-Content $jsonFile -Raw | ConvertFrom-Json
    # this is declared at module import
    $runtime = Get-PSFConfigValue dbops.runtime.dotnetversion

    if ($null -ne $Type) { Get-PackageList $dependencies.$Type }
    else {
        $rdbms = $dependencies | Get-Member | Where-Object MemberType -eq NoteProperty | Select-Object -ExpandProperty Name
        $output = @{ }
        foreach ($t in $rdbms) {
            $output.$t = Get-PackageList $dependencies.$t
        }
        [pscustomobject]$output
    }
}