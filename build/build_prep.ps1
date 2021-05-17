dotnet new tool-manifest
dotnet tool install Cake.Tool --version 1.1.0
Invoke-WebRequest https://cakebuild.net/download/bootstrapper/dotnet-tool/windows -OutFile build.ps1
git fetch --all