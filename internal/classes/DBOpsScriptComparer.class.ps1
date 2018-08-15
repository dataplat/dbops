using namespace System.Collections.Generic
class DBOpsScriptEqualityComparer : IEqualityComparer[String] {
    [bool] Equals ([string] $x, [string] $y) {
        return $x.Equals($y)
    }
    [int] GetHashCode ([string] $x) {
        return $x.GetHashCode();
    }
}
class DBOpsScriptComparer : DBOpsScriptEqualityComparer, IComparer[String] {
    hidden [string[]] $Scripts

    DBOpsScriptComparer ([string[]]$ScriptList) {
        $this.Scripts = $ScriptList
    }

    [int] Compare ([string] $x, [string] $y) {
        #Disable all the custom sorting: using array order instead of string order
        return $this.Scripts.IndexOf($x).CompareTo($this.Scripts.IndexOf($y))
    }
    [bool] Equals ([string] $x, [string] $y) {
        return ([DBOpsScriptEqualityComparer]$this).Equals($x, $y)
    }
    [int] GetHashCode ([string] $x) {
        return ([DBOpsScriptEqualityComparer]$this).GetHashCode($x)
    }
}