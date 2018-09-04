class DBOpsDeploymentStatus {
    [string] $SqlInstance
    [string] $Database
    [DBOpsConnectionType] $ConnectionType
    [DBOpsConfig] $Configuration
    [DbUp.Engine.SqlScript[]] $Scripts
    [Exception] $Error
    [bool] $Successful
    [timespan] $Duration
    [datetime] $StartTime
    [datetime] $EndTime
    [string[]] $DeploymentLog
}