<#
    .SYNOPSIS
    Creates a Markdown changelog file with markdown formatting.

    Original version created by @vexx32
    .DESCRIPTION
    Uses `git log` to compare the current commit to the last tagged commit,
    and parses the output into CSV data. This is then processed and PR body
    of submitted Pull Requests are added to the output file.
    .PARAMETER Path
    The file location to save the markdown text to. The file will be
    overwritten if it already contains data.
    .PARAMETER CommitID
    The commit tag or hash that is used to identify the commit to
    compare with. By default, the last value given by `git tag`
    will be used.
    .PARAMETER HeadCommitID
    The commit tag or hash that represents the current version
    of the repository. HEAD by default.
    .PARAMETER ApiKey
    The Github API key to use when looking up commit authors'
    Github user names.
    .PARAMETER IncludeDetails
    Add PR body to each entry in the change log
    .PARAMETER Append
    Append changelog to the top of the existing file
    .EXAMPLE
    New-Changelog.ps1 -Path File.md -ApiKey $GHApiKey
    Retrieves the commits since the last tagged commit and creates a
    Markdown-formatted plaintext file called File.md in the current
    location.
    .NOTES
    The Github API limitation of 60 requests per minute is -barely-
    usable without authentication. Authenticated requests have a
    substantially higher limit on requests per minute.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateScript( { Test-Path $_ -IsValid })]
    [string]
    $Path,

    [Parameter(Position = 1)]
    [ValidatePattern('[a-f0-9]{6,40}|v?(\d+\.)+\d+(-\w+\d+)?')]
    [string]
    $CommitID = (git tag | Select-Object -Last 1),

    [Parameter(Position = 2)]
    [ValidatePattern('[a-f0-9]{6,40}|v?(\d+\.)+\d+(-\w+\d+)?|HEAD')]
    [string]
    $HeadCommitID = 'HEAD',

    [Parameter()]
    [Alias('OauthToken')]
    [string]
    $ApiKey,

    [Parameter()]
    [switch]
    $IncludeDetails,

    [Parameter()]
    [switch]
    $Append
)
$RequestParams = @{ }
if ($ApiKey) {
    $RequestParams = @{
        SessionVariable = 'AuthSession'
        Headers         = @{ Authorization = "token $ApiKey" }
    }
    Invoke-RestMethod @RequestParams -Uri 'https://api.github.com/' | Out-String | Write-Verbose
}
$RequestParams = if ($AuthSession) { @{ WebSession = $AuthSession } } else { @{ } }
$gitParams = @(
    '--no-pager'
    'log'
    '--first-parent'
    "$CommitID..$HeadCommitID"
    '--format="%H"'
    '--'
    '.'
    '":(exclude)*.md"'
)
$commits = & git @gitParams

$prs = @()
foreach ($commit in $commits) {
    $result = Invoke-RestMethod @RequestParams -Uri "https://api.github.com/search/issues?q=$($commit)is%3Amerged"
    if ($result.total_count -gt 0) {
        $prs += $result.items | Sort-Object -Property score -Descending | Select-Object -First 1
    }
}
$prs = $prs | Sort-Object -Property number -Unique
$mdTable = @("# Release notes for $CommitID`:")
foreach ($pr in $prs) {
    $prData = Invoke-RestMethod @RequestParams -Uri $pr.url
    $mdTable += "- ### $($prData.title) (#$($prData.number)) by @$($prData.user.login)"
    if ($IncludeDetails -and $prData.body) {
        $mdTable += "   ------"
        foreach ($line in $prData.body.Split("`n")) {
            $mdTable += "   $line"
        }
    }
}
if ($Append) {
    if (Test-Path $Path) {
        $currentContent = Get-Content -Path $Path
    }
    else { $currentContent = @() }
    $mdTable + $currentContent | Set-Content -Path $Path
}
else { $mdTable | Set-Content -Path $Path }
