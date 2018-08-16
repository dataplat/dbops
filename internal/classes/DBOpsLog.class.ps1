class DBOpsLog : DbUp.Engine.Output.IUpgradeLog {
    #Hidden properties
    hidden [string]$logToFile
    hidden [bool]$silent
    
    #Constructors
    DBOpsLog ([bool]$silent, [string]$outFile, [bool]$append) {
        $this.silent = $silent
        $this.logToFile = $outFile
        $txt = "Logging started at " + (get-date).ToString()
        if ($outFile) {
            if ($append) {
                $txt | Out-File $this.logToFile -Append
            }
            else {
                $txt | Out-File $this.logToFile -Force
            }
        }
    }
    
    #Methods
    [void] WriteInformation([string]$format, [object[]]$params) {
        if (!$this.silent) {
            Write-Host ($format -f $params)
        }
        if ($this.logToFile) {
            $this.WriteToFile($format, $params)
        }
    }
    [void] WriteError([string]$format, [object[]]$params) {
        if (!$this.silent) {
            Write-Error ($format -f $params)
        }
        if ($this.logToFile) {
            $this.WriteToFile($format, $params)
        }
    }
    [void] WriteWarning([string]$format, [object[]]$params) {
        if (!$this.silent) {
            Write-Warning ($format -f $params)
        }
        if ($this.logToFile) {
            $this.WriteToFile($format, $params)
        }
    }
    [void] WriteToFile([string]$format, [object[]]$params) {
        $format -f $params | Out-File $this.logToFile -Append
    }
}