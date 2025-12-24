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

    # P8: Doc readiness with per-doc scores for rated display
    [hashtable]$DocScores            # @{ PRD = @{score=60; exists=$true; threshold=80}; ... }
    [bool]$DocsAllPassed             # True when all 3 docs meet their thresholds
 
    # P8 legacy: backward compat (derived from DocScores)
    [hashtable]$DocsReadiness        # @{ PRD = $true; SPEC = $false; DECISION_LOG = $false }
    [int]$DocsReadyCount             # Count of ready docs (0-3)
    [int]$DocsTotalCount             # Always 3
 
    # Initialization status (separate from DB presence)
    [bool]$IsInitialized             # True if project has marker file or 2/3 docs
    # History/feed data
    [object]$ActiveTask              # Currently active task (from snapshot)
    [object[]]$PendingTasks          # Pending tasks sampled for overlay
    [object]$SchedulerLastDecision   # Last scheduler decision (for observability)
    [object[]]$HistoryTasks          # Optional history entries (tasks)
    [object[]]$HistoryDocs           # Optional history entries (docs)
    [object[]]$HistoryShip           # Optional history entries (ship artifacts)

    # Librarian feedback (optional, from out-of-band cache)
    [hashtable]$LibrarianDocFeedback     # @{ PRD = @{one_liner=""; paragraph=""}; ... }
    [bool]$LibrarianDocFeedbackStale     # True if cache file > 10 min old
    [bool]$LibrarianDocFeedbackPresent   # True if cache file exists and was parsed

    # Tier 2: Librarian quality metrics (0 = not present)
    [int]$LibrarianOverallQuality        # 0-5 scale
    [int]$LibrarianConfidence            # 0-100 scale
    [int]$LibrarianCriticalRisksCount    # count of critical risks flagged

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
        # P8 defaults: rated doc readiness with per-doc scores
        $this.DocScores = @{
            PRD = @{ score = 0; exists = $false; threshold = 80 }
            SPEC = @{ score = 0; exists = $false; threshold = 80 }
            DECISION_LOG = @{ score = 0; exists = $false; threshold = 30 }
        }
        $this.DocsAllPassed = $false
        # P8 legacy (backward compat, derived from DocScores)
        $this.DocsReadiness = @{ PRD = $false; SPEC = $false; DECISION_LOG = $false }
        $this.DocsReadyCount = 0
        $this.DocsTotalCount = 3
        # Initialization default
        $this.IsInitialized = $false
        # History/feed defaults
        $this.ActiveTask = $null
        $this.PendingTasks = @()
        $this.SchedulerLastDecision = $null
        $this.HistoryTasks = @()
        $this.HistoryDocs = @()
        $this.HistoryShip = @()
        # Librarian feedback defaults (empty = not present)
        $this.LibrarianDocFeedback = @{
            PRD = @{ one_liner = ""; paragraph = "" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
        $this.LibrarianDocFeedbackStale = $false
        $this.LibrarianDocFeedbackPresent = $false
        # Tier 2 defaults (0 = not present)
        $this.LibrarianOverallQuality = 0
        $this.LibrarianConfidence = 0
        $this.LibrarianCriticalRisksCount = 0
    }
}
