# Write-Host -Object "appveyor.post: Sending coverage data" -ForeGroundColor DarkGreen
# Push-AppveyorArtifact PesterResultsCoverage.json -FileName "PesterResultsCoverage"
# codecov -f PesterResultsCoverage.json --flag "ps,$($env:SCENARIO.toLower())" | Out-Null

