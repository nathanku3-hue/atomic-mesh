function Get-UiSnapshotRaw {
    param([string]$DbPath)

    # DEPRECATED: Stub adapter for testing only.
    # Production uses Get-RealSnapshot from RealAdapter.ps1 (calls snapshot.py)
    # Keep zeros to avoid confusion if accidentally used.
    $lanes = @(
        @{ name = "BACKEND"; queued = 0; active = 0; tokens = 0 },
        @{ name = "FRONTEND"; queued = 0; active = 0; tokens = 0 },
        @{ name = "QA/AUDIT"; queued = 0; active = 0; tokens = 0 },
        @{ name = "LIBRARIAN"; queued = 0; active = 0; tokens = 0 }
    )

    return @{
        plan      = @{
            status    = "DRAFT"
            accepted  = $false
            has_draft = $true
            id        = "draft-001"
            summary   = "Stub plan (phase 1)"
        }
        lanes     = $lanes
        scheduler = @{
            next_action = "/accept-plan"
            reason      = "Awaiting acceptance"
        }
        alerts    = @()
        db_path   = $DbPath
    }
}

function Get-UiSnapshot {
    param([string]$DbPath)

    $raw = Get-UiSnapshotRaw -DbPath $DbPath
    $snapshot = [UiSnapshot]::new()
    $snapshot.AdapterError = ""
    $snapshot.PlanState = Compute-PlanState -RawSnapshot $raw
    $snapshot.LaneMetrics = Compute-LaneMetrics -RawSnapshot $raw

    $snapshot.SchedulerDecision = [SchedulerDecision]::new()
    if ($raw.scheduler) {
        $snapshot.SchedulerDecision.NextAction = $raw.scheduler.next_action
        $snapshot.SchedulerDecision.Reason = $raw.scheduler.reason
    }

    if ($raw.alerts) {
        $alerts = [UiAlerts]::new()
        $alerts.Messages = @($raw.alerts)
        $snapshot.Alerts = $alerts
    }

    return $snapshot
}
