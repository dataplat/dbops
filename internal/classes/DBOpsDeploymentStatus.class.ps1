class DBOpsDeploymentStatus {
    [string] $SqlInstance
    [string] $Database
    [string[]] $SourcePath
    [DBOpsConnectionType] $ConnectionType
    [DBOpsConfig] $Configuration
    [DbUp.Engine.SqlScript[]] $Scripts
    [Exception] $Error
    [bool] $Successful
    [datetime] $StartTime
    [datetime] $EndTime
    [string[]] $DeploymentLog

    DBOpsDeploymentStatus() {
        Add-Member -InputObject $this -MemberType ScriptProperty -Name Duration -TypeName timespan -Value {
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
        $dur = switch ($this.Duration) {
            $null { "Not run yet" }
            default { $this.Duration.ToString('hh\:mm\:ss\.f') }
        }
        $scriptCount = switch ($this.Scripts) {
            $null { 0 }
            default { $this.Scripts.count() }
        }
        return "Deployment status`: $status. Duration`: $dur. Script count`: $scriptCount"
    }
}