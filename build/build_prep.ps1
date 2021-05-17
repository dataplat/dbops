dotnet new tool-manifest
dotnet tool install Cake.Tool --version 1.1.0
# if ($prNo = $env:APPVEYOR_PULL_REQUEST_NUMBER) {
#     Write-Host "PR Build, creating an explicit branch"
#     git checkout -qb "pr-build-$prNo"
# }
