function Convert-RawSnapshotToUi {
    param(
        $Raw
    )

    $snapshot = [UiSnapshot]::new()

    # CRITICAL: Compute PlanState from raw.plan (has_draft, status, etc.)
    # This enables Next hint: /draft-plan vs /accept-plan transitions
    $snapshot.PlanState = Compute-PlanState -RawSnapshot $Raw

    # Use Compute-LaneMetrics for canonical lanes (BACKEND, FRONTEND, QA, LIBRARIAN)
    # with proper state/color logic (IDLE/RUNNING/QUEUED)
    $snapshot.LaneMetrics = Compute-LaneMetrics -RawSnapshot $Raw

    if ($Raw -and $Raw.Drift) {
        $alerts = [UiAlerts]::new()
        if ($Raw.Drift.HasDrift) {
            $alerts.Messages = @("Drift detected: $($Raw.Drift.Reason)")
        }
        else {
            $alerts.Messages = @()
        }
        $snapshot.Alerts = $alerts
    }

    # GOLDEN NUANCE fields (v4) - from tools/snapshot.py
    if ($Raw) {
        # ReadinessMode: "live" or "fail-open"
        if ($Raw.ReadinessMode) {
            $snapshot.ReadinessMode = [string]$Raw.ReadinessMode
        }

        # HealthStatus: "OK", "WARN", "FAIL"
        if ($Raw.HealthStatus) {
            $snapshot.HealthStatus = [string]$Raw.HealthStatus
        }

        # DistinctLaneCounts: { pending: n, active: m }
        if ($Raw.DistinctLaneCounts) {
            $snapshot.DistinctLaneCounts = @{
                pending = [int]($Raw.DistinctLaneCounts.pending)
                active = [int]($Raw.DistinctLaneCounts.active)
            }
        }

        # GitClean: boolean
        if ($null -ne $Raw.GitClean) {
            $snapshot.GitClean = [bool]$Raw.GitClean
        }

        # P1+P4: Task-specific hints + HIGH risk blocking
        if ($Raw.FirstBlockedTaskId) {
            $snapshot.FirstBlockedTaskId = [string]$Raw.FirstBlockedTaskId
        }
        if ($Raw.FirstErrorTaskId) {
            $snapshot.FirstErrorTaskId = [string]$Raw.FirstErrorTaskId
        }
        if ($null -ne $Raw.HighRiskUnverifiedCount) {
            $snapshot.HighRiskUnverifiedCount = [int]$Raw.HighRiskUnverifiedCount
        }

        # P5: Blocking files for /draft-plan feedback
        if ($Raw.BlockingFiles -and $Raw.BlockingFiles.Count -gt 0) {
            $snapshot.BlockingFiles = @($Raw.BlockingFiles | ForEach-Object { [string]$_ })
        }

        # P7: Optimize stage (entropy proof detection)
        if ($Raw.FirstUnoptimizedTaskId) {
            $snapshot.FirstUnoptimizedTaskId = [string]$Raw.FirstUnoptimizedTaskId
        }
        if ($null -ne $Raw.HasAnyOptimized) {
            $snapshot.HasAnyOptimized = [bool]$Raw.HasAnyOptimized
        }
        if ($null -ne $Raw.OptimizeTotalTasks) {
            $snapshot.OptimizeTotalTasks = [int]$Raw.OptimizeTotalTasks
        }

        # P8: Doc scores for rated readiness display
        if ($Raw.DocScores) {
            $snapshot.DocScores = @{}
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                $docData = $Raw.DocScores.$docName
                if ($docData) {
                    # PS5-compatible null checks (no ?? operator)
                    $score = if ($null -ne $docData.score) { [int]$docData.score } else { 0 }
                    $exists = if ($null -ne $docData.exists) { [bool]$docData.exists } else { $false }
                    $threshold = if ($null -ne $docData.threshold) { [int]$docData.threshold } else { 80 }
                    $hint = if ($docData.hint) { [string]$docData.hint } else { "" }
                    $snapshot.DocScores[$docName] = @{
                        score = $score
                        exists = $exists
                        threshold = $threshold
                        hint = $hint
                    }
                }
            }
        }
        if ($null -ne $Raw.DocsAllPassed) {
            $snapshot.DocsAllPassed = [bool]$Raw.DocsAllPassed
        }

        # P8 legacy: Doc readiness for pre-draft UI (derived from BlockingFiles)
        if ($Raw.DocsReadiness) {
            $snapshot.DocsReadiness = @{
                PRD = [bool]($Raw.DocsReadiness.PRD)
                SPEC = [bool]($Raw.DocsReadiness.SPEC)
                DECISION_LOG = [bool]($Raw.DocsReadiness.DECISION_LOG)
            }
        }
        if ($null -ne $Raw.DocsReadyCount) {
            $snapshot.DocsReadyCount = [int]$Raw.DocsReadyCount
        }
        if ($null -ne $Raw.DocsTotalCount) {
            $snapshot.DocsTotalCount = [int]$Raw.DocsTotalCount
        }

        # Initialization status (separate from DB presence)
        if ($null -ne $Raw.IsInitialized) {
            $snapshot.IsInitialized = [bool]$Raw.IsInitialized
        }

        # Librarian feedback (optional, from out-of-band cache)
        if ($Raw.LibrarianDocFeedback) {
            $snapshot.LibrarianDocFeedback = @{}
            foreach ($docName in @("PRD", "SPEC", "DECISION_LOG")) {
                $docData = $Raw.LibrarianDocFeedback.$docName
                $one_liner = if ($docData -and $docData.one_liner) { [string]$docData.one_liner } else { "" }
                $paragraph = if ($docData -and $docData.paragraph) { [string]$docData.paragraph } else { "" }
                $snapshot.LibrarianDocFeedback[$docName] = @{
                    one_liner = $one_liner
                    paragraph = $paragraph
                }
            }
        }
        if ($null -ne $Raw.LibrarianDocFeedbackStale) {
            $snapshot.LibrarianDocFeedbackStale = [bool]$Raw.LibrarianDocFeedbackStale
        }
        if ($null -ne $Raw.LibrarianDocFeedbackPresent) {
            $snapshot.LibrarianDocFeedbackPresent = [bool]$Raw.LibrarianDocFeedbackPresent
        }
        # Tier 2 fields with clamping
        if ($null -ne $Raw.LibrarianOverallQuality) {
            $val = [int]$Raw.LibrarianOverallQuality
            $snapshot.LibrarianOverallQuality = [Math]::Max(0, [Math]::Min(5, $val))
        }
        if ($null -ne $Raw.LibrarianConfidence) {
            $val = [int]$Raw.LibrarianConfidence
            $snapshot.LibrarianConfidence = [Math]::Max(0, [Math]::Min(100, $val))
        }
        if ($null -ne $Raw.LibrarianCriticalRisksCount) {
            $snapshot.LibrarianCriticalRisksCount = [Math]::Max(0, [int]$Raw.LibrarianCriticalRisksCount)
        }

        # History/feed data for overlays
        try {
            $snapshot.ActiveTask = $Raw.active_task
        } catch {
            $snapshot.ActiveTask = $null
        }
        try {
            if ($Raw.pending_tasks) {
                $snapshot.PendingTasks = @($Raw.pending_tasks)
            }
        } catch {}
        try {
            if ($Raw.history) {
                $snapshot.HistoryTasks = @($Raw.history)
            }
        } catch {}
        try {
            if ($Raw.scheduler_last_decision) {
                $snapshot.SchedulerLastDecision = $Raw.scheduler_last_decision
            }
        } catch {}
    }

    return $snapshot
}

# =============================================================================
# v23.1: Async snapshot state (non-blocking refresh)
# =============================================================================
$script:AsyncSnapshot = @{
    Process = $null
    StartTime = $null
    RepoRoot = $null
    ScriptPath = $null
}

function Get-SnapshotScriptPath {
    # Find snapshot.py relative to MODULE location, not project path
    $moduleRoot = $PSScriptRoot
    $moduleRoot = Split-Path -Parent $moduleRoot  # Adapters/ → Private/
    $moduleRoot = Split-Path -Parent $moduleRoot  # Private/ → AtomicMesh.UI/
    $moduleRoot = Split-Path -Parent $moduleRoot  # AtomicMesh.UI/ → src/
    $moduleRoot = Split-Path -Parent $moduleRoot  # src/ → repo root
    return Join-Path -Path $moduleRoot -ChildPath "tools\snapshot.py"
}

function Start-AsyncSnapshot {
    param([string]$RepoRoot)

    # If already running, don't start another
    if ($script:AsyncSnapshot.Process -and -not $script:AsyncSnapshot.Process.HasExited) {
        return
    }

    $resolvedRoot = if ($RepoRoot) { (Resolve-Path $RepoRoot -ErrorAction SilentlyContinue).Path } else { (Get-Location).Path }
    if (-not $resolvedRoot) { $resolvedRoot = (Get-Location).Path }

    $scriptPath = Get-SnapshotScriptPath
    if (-not (Test-Path $scriptPath)) { return }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "python"
    $psi.Arguments = "-u `"$scriptPath`" `"$resolvedRoot`""
    $psi.WorkingDirectory = $resolvedRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($proc) {
            $script:AsyncSnapshot.Process = $proc
            $script:AsyncSnapshot.StartTime = [datetime]::UtcNow
            $script:AsyncSnapshot.RepoRoot = $resolvedRoot
            $script:AsyncSnapshot.ScriptPath = $scriptPath
        }
    } catch {}
}

function Get-AsyncSnapshotResult {
    # Returns $null if not ready, hashtable with result if done
    $proc = $script:AsyncSnapshot.Process
    if (-not $proc) { return $null }

    # Check timeout (1200ms max)
    $elapsed = ([datetime]::UtcNow - $script:AsyncSnapshot.StartTime).TotalMilliseconds
    if ($elapsed -gt 1200 -and -not $proc.HasExited) {
        try { $proc.Kill() } catch {}
        $script:AsyncSnapshot.Process = $null
        return @{ Error = "Snapshot backend timeout" }
    }

    # Not done yet
    if (-not $proc.HasExited) { return $null }

    # Process completed - read results
    try {
        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()
        $exitCode = $proc.ExitCode

        $script:AsyncSnapshot.Process = $null

        if ($exitCode -ne 0) {
            $errLine = if ($stderr) { $stderr.Split("`n")[0] } else { "exit $exitCode" }
            return @{ Error = "Backend Error: $errLine" }
        }

        if (-not $stdout) {
            return @{ Error = "Backend Error: empty output" }
        }

        $data = $stdout | ConvertFrom-Json -ErrorAction Stop
        return @{ Data = $data }
    }
    catch {
        $script:AsyncSnapshot.Process = $null
        return @{ Error = "Invalid snapshot JSON: $($_.Exception.Message)" }
    }
}

function Get-RealSnapshot {
    param(
        [string]$RepoRoot
    )

    # Synchronous fallback (used for initial load)
    $timeoutMs = 1200
    $resolvedRoot = if ($RepoRoot) { (Resolve-Path $RepoRoot).Path } else { (Get-Location).Path }

    $scriptPath = Get-SnapshotScriptPath

    if (-not (Test-Path $scriptPath)) {
        throw "Backend Error: snapshot.py not found at $scriptPath"
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "python"
    $psi.Arguments = "-u `"$scriptPath`" `"$resolvedRoot`""
    $psi.WorkingDirectory = $resolvedRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc) {
        throw "Backend Error: unable to start python process"
    }

    # Read stdout/stderr synchronously to drain pipes (avoids 4KB deadlock on WaitForExit)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit() | Out-Null
    $stdout = $stdout.Trim()
    $stderr = $stderr.Trim()

    if ($proc.ExitCode -ne 0) {
        $errLine = if ($stderr) { $stderr.Split("`n")[0] } else { "exit $($proc.ExitCode)" }
        throw "Backend Error: $errLine"
    }

    if (-not $stdout) {
        throw "Backend Error: empty output"
    }

    try {
        return $stdout | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Invalid snapshot JSON: $($_.Exception.Message)"
    }
}
