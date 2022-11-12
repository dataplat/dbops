param (
    [switch]$Internal,
    [switch]$Batch
)
if (!$Batch) {
    # Explicitly import the module for testing
    . "$PSScriptRoot\..\import.ps1"
}
# import test fixtures
. "$PSScriptRoot\..\fixtures.ps1"
