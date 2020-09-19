class DBOpsDeploymentStatus {
    [string] $SqlInstance
    [string] $Database
    [string[]] $SourcePath
    [System.Nullable[DBOps.ConnectionType]] $ConnectionType
    [DBOpsConfig] $Configuration
    [DBOps.Extensions.SqlScript[]] $Scripts
    [Exception] $Error
    [System.Nullable[bool]] $Successful
    [System.Nullable[datetime]] $StartTime
    [System.Nullable[datetime]] $EndTime
    [string[]] $DeploymentLog

    DBOpsDeploymentStatus() {
        Add-Member -InputObject $this -MemberType ScriptProperty -Name Duration -Value {
            if ($this.StartTime -and $this.EndTime) {
                return $this.EndTime.Subtract($this.StartTime)
            }
            else {
                return [timespan]::new(0)
            }
        }
    }

    [string] ToString() {
        $status = switch ($this.Successful) {
            $true { "Successful" }
            $false { "Failed" }
            default { "Not deployed" }
        }
        $dur = switch ($this.Duration.TotalMilliseconds) {
            0 { "Not run yet" }
            default { $this.Duration.ToString('hh\:mm\:ss') }
        }
        $scriptCount = ($this.Scripts | Measure-Object).Count
        return "Deployment status`: $status. Duration`: $dur. Script count`: $scriptCount"
    }
}