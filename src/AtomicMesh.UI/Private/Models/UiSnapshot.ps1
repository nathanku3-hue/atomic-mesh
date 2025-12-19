# NOTE: Using [object] to avoid type mismatch on module reload
class UiSnapshot {
    [object]$PlanState           # PlanState
    [object[]]$LaneMetrics       # LaneMetrics[]
    [object]$SchedulerDecision   # SchedulerDecision
    [object]$Alerts              # UiAlerts
    [string]$AdapterError

    # GOLDEN NUANCE fields (v4) - populated from tools/snapshot.py
    [string]$ReadinessMode      # "live" or "fail-open"
    [string]$HealthStatus       # "OK", "WARN", "FAIL"
    [hashtable]$DistinctLaneCounts  # @{ pending = n; active = m }
    [bool]$GitClean             # True if working directory is clean

    # P1+P4: Task-specific hints + HIGH risk blocking
    [string]$FirstBlockedTaskId     # First blocked task ID for /reset <id>
    [string]$FirstErrorTaskId       # First error task ID for /retry <id>
    [int]$HighRiskUnverifiedCount   # Count of HIGH risk unverified tasks

    # P5: Blocking files for /draft-plan feedback
    [string[]]$BlockingFiles        # List of files blocking plan (below threshold)

    # P7: Optimize stage (entropy proof detection)
    [string]$FirstUnoptimizedTaskId  # First task without entropy proof for /simplify <id>
    [bool]$HasAnyOptimized           # True if any task has entropy proof marker
    [int]$OptimizeTotalTasks         # Total active tasks for optimize stage

    UiSnapshot() {
        $this.PlanState = [PlanState]::new()
        $this.LaneMetrics = @()
        $this.SchedulerDecision = [SchedulerDecision]::new()
        $this.Alerts = [UiAlerts]::new()
        $this.AdapterError = ""
        # GOLDEN NUANCE defaults (fail-open)
        $this.ReadinessMode = "live"
        $this.HealthStatus = "OK"
        $this.DistinctLaneCounts = @{ pending = 0; active = 0 }
        $this.GitClean = $true
        # P1+P4 defaults
        $this.FirstBlockedTaskId = $null
        $this.FirstErrorTaskId = $null
        $this.HighRiskUnverifiedCount = 0
        # P5 default
        $this.BlockingFiles = @()
        # P7 defaults
        $this.FirstUnoptimizedTaskId = $null
        $this.HasAnyOptimized = $false
        $this.OptimizeTotalTasks = 0
    }
}
