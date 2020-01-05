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
    $packageLowerName = $Name.ToLower()
    $Api = $Api.TrimEnd('/')
    # Get API endpoint URLs
    $index = Invoke-WebRequest "$Api/index.json" -ErrorAction Stop
    $indexObject = $index.Content | ConvertFrom-Json

    # search for package
    $searchUrl = $indexObject.resources | Where-Object { $_.'@type' -eq 'SearchQueryService' } | Select-Object -First 1
    $query = "?q=PackageId:{0}&prerelease={1}" -f $Name, (-Not $SkipPreRelease).ToString().ToLower()
    $packageInfoResponse = Invoke-WebRequest -Uri "$($searchUrl.'@id')$query" -ErrorAction Stop
    $packageInfoObject = $packageInfoResponse.Content | ConvertFrom-Json
    $packageInfo = $packageInfoObject.data | Select-Object -First 1
    if (-Not $packageInfo) {
        Write-PSFMessage -Level Critical -Message "Package $Name was not found"
    }
    $packageName = $packageInfo.id
    $packageLowerName = $packageName.ToLower()
    [array]$versionList = $packageInfo.versions.version
    Write-PSFMessage -Level Verbose -Message "Found a total of $($versionList.Count) versions of $packageName"

    # filter out the versions we don't need based on parameters
    if ($MinimumVersion) {
        $position = $versionList.IndexOf($MinimumVersion)
        if ($position -eq -1) {
            $versionList = $versionList | Where-Object { try { [version]$_ -ge $MinimumVersion } catch { $false } }
        }
        else {
            $versionList = $versionList[$position..($versionList.Count - 1)]
        }
    }
    if ($MaximumVersion) {
        $position = $versionList.IndexOf($MaximumVersion)
        if ($position -eq -1) {
            $versionList = $versionList | Where-Object { try { [version]$_ -le $MaximumVersion } catch { $false } }
        }
        else {
            $versionList = $versionList[0..$position]
        }
    }
    if ($RequiredVersion) {
        $versionList = $versionList | Where-Object { $_ -eq $RequiredVersion }
    }
    Write-PSFMessage -Level Verbose -Message "$($versionList.Count) versions left after applying filters"
    $selectedVersion = $versionList | Select-Object -Last 1
    if (-Not $selectedVersion) {
        Write-PSFMessage -Level Critical -Message "Version could not be found using current parameters" -EnableException $true
    }

    # download and extract the files
    Write-PSFMessage -Level Output -Message "Downloading version $selectedVersion of $packageName"
    $fileName = "$packageName.$selectedVersion.nupkg"
    # Path reference: https://github.com/OneGet/oneget/blob/master/src/Microsoft.PackageManagement/Utility/Platform/OSInformation.cs
    $scopePath = switch ($Scope) {
        'AllUsers' {
            switch ($IsWindows) {
                $false { "/usr/local/share/PackageManagement/NuGet/Packages" }
                default { Join-PSFPath $env:ProgramFiles "PackageManagement\NuGet\packages" }
            }
        }
        'CurrentUser' {
            switch ($IsWindows) {
                $false { Join-PSFPath $env:HOME ".local/share/PackageManagement/NuGet/Packages" }
                default { Join-PSFPath $env:LOCALAPPDATA "PackageManagement\NuGet\packages" }
            }
        }
    }
    $path = Join-PSFPath $scopePath "$packageName.$selectedVersion"
    $packagePath = Join-PSFPath $path $fileName
    if (Test-Path $path) {
        if ($Force) {
            Remove-Item $path -Recurse -Force
        }
        else {
            Write-PSFMessage -Level Critical -Message "$packageName.$selectedVersion already exists at destination" -EnableException $true
        }
    }
    $folder = New-Item -ItemType Directory -Path $path -Force

    $baseAddressUrl = $indexObject.resources | Where-Object { $_.'@type' -eq 'PackageBaseAddress/3.0.0' } | Select-Object -First 1
    $downloadUrl = "$($baseAddressUrl.'@id')$packageLowerName/$selectedVersion/$fileName"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $packagePath -ErrorAction Stop
    Write-PSFMessage -Level Verbose -Message "Extracting $fileName to $folder"
    if ($isCoreCLR) {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $folder, $true)
    }
    else {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $folder)
    }

    #return output
    [PSCustomObject]@{
        Name    = $packageName
        Source  = $packagePath
        Version = $selectedVersion
        Uri     = $downloadUrl
    } | Select-Object *
}