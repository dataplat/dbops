dotnet new tool-manifest
dotnet tool install Cake.Tool --version 1.1.0
Invoke-WebRequest https://cakebuild.net/download/bootstrapper/dotnet-tool/windows -OutFile build.ps1
if ($prNo = $env:APPVEYOR_PULL_REQUEST_NUMBER) {
    Write-Host "PR Build, creating an explicit branch"
    git fetch --unshallow
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch origin
    git branch master origin/master
    git checkout -b "pr-build-$prNo"
}
