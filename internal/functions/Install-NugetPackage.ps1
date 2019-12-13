function Install-NugetPackage {
    # This function acts similarly to Install-Package -SkipDependencies and downloads nuget packages from nuget.org
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    Param (
        [string]$Name,
        [string]$MinimumVersion,
        [string]$RequiredVersion,
        [string]$MaximumVersion,
        [switch]$SkipPreRelease,
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'AllUsers',
        [switch]$Force,
        [string]$Api = 'https://api.nuget.org/v3'
    )
    $packageName = $Name.ToLower()
    $Api = $Api.TrimEnd('/')
    $index = Invoke-WebRequest "$Api/index.json" -ErrorAction Stop
    $indexObject = $index.Content | ConvertFrom-Json
    $baseAddress = $indexObject.resources | Where-Object { $_.'@type' -eq 'PackageBaseAddress/3.0.0' }
    $packageVersions = Invoke-WebRequest "$($baseAddress.'@id')$packageName/index.json" -ErrorAction Stop
    $packageVersionsObject = $packageVersions.Content | ConvertFrom-Json
    [array]$versionList = $packageVersionsObject.Versions
    Write-PSFMessage -Level Verbose -Message "Found a total of $($versionList.Count) versions of $packageName"
    if ($SkipPreRelease) {
        $versionList = $versionList | Where-Object { try { [version]$_ } catch { $false } }
    }
    if ($MinimumVersion) {
        $versionList = $versionList | Where-Object { $_ -ge $MinimumVersion }
    }
    if ($MaximumVersion) {
        $versionList = $versionList | Where-Object { $_ -le $MaximumVersion }
    }
    if ($RequiredVersion) {
        $versionList = $versionList | Where-Object { $_ -eq $RequiredVersion }
    }
    Write-PSFMessage -Level Verbose -Message "$($versionList.Count) versions left after applying filters"
    $selectedVersion = $versionList | Sort-Object -Descending | Select-Object -First 1
    if (-Not $selectedVersion) {
        Write-PSFMessage -Level Critical -Message "Version could not be found using current parameters" -EnableException $true
    }
    Write-PSFMessage -Level Verbose -Message "Downloading version $selectedVersion of $packageName"
    $fileName = "$packageName.$selectedVersion.nupkg"
    $scopePath = switch ($Scope) {
        'AllUsers' { $env:ProgramFiles }
        'CurrentUser' { $env:LOCALAPPDATA }
    }
    $path = Join-PSFPath $scopePath PackageManagement\NuGet\Packages\ "$packageName.$selectedVersion"
    $folder = New-Item -ItemType Directory -Path $path -Force
    $packagePath = Join-PSFPath $path $fileName
    Invoke-WebRequest "$($baseAddress.'@id')$packageName/$selectedVersion/$fileName" -OutFile $packagePath -ErrorAction Stop
    Write-PSFMessage -Level Verbose -Message "Extracting $fileName to $folder"
    Expand-Archive -Path $packagePath -DestinationPath $folder -Force:$Force -ErrorAction Stop
}