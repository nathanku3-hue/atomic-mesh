function Convert-RawSnapshotToUi {
    param(
        $Raw
    )

    $snapshot = [UiSnapshot]::new()

    # Map lane counts into LaneMetrics
    $laneMap = @{}
    if ($Raw -and $Raw.LaneCounts) {
        foreach ($entry in $Raw.LaneCounts) {
            $laneName = if ($entry.Lane) { [string]$entry.Lane } else { "UNKNOWN" }
            if (-not $laneMap.ContainsKey($laneName)) {
                $laneMap[$laneName] = [LaneMetrics]::CreateDefault($laneName)
            }
            $lane = $laneMap[$laneName]
            $status = if ($entry.Status) { $entry.Status.ToString().ToUpperInvariant() } else { "" }
            $count = [int]$entry.Count
            switch -Regex ($status) {
                "IN_PROGRESS|RUNNING|ACTIVE" { $lane.Active += $count }
                "QUEUED|PENDING|TODO"        { $lane.Queued += $count }
                default                      { $lane.Tokens += $count }
            }
        }
    }

    if ($laneMap.Count -gt 0) {
        $snapshot.LaneMetrics = $laneMap.Values
    }

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
    }

    return $snapshot
}

function Get-RealSnapshot {
    param(
        [string]$RepoRoot
    )

    $timeoutMs = 200
    $resolvedRoot = if ($RepoRoot) { (Resolve-Path $RepoRoot).Path } else { (Get-Location).Path }
    $scriptPath = Join-Path -Path $resolvedRoot -ChildPath "tools/snapshot.py"
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

    if (-not $proc.WaitForExit($timeoutMs)) {
        try { $proc.Kill() } catch {}
        throw "Snapshot backend timeout"
    }

    $stdout = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd().Trim()

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
