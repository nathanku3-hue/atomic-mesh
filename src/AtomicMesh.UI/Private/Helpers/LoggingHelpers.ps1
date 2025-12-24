# =============================================================================
# Pipeline Snapshot Logging (opt-in)
# - Controlled by state.EnableSnapshotLogging (set via -Dev or env:MESH_LOG_SNAPSHOTS)
# - Writes to ProjectPath\control\state\pipeline_snapshots.jsonl
# - Dedupe on content hash to avoid churn
# - Schema: ts, stages, next, reason, source, counts (backward compatible only)
# =============================================================================

function Get-PipelineLogPath {
    param([string]$ProjectPath)

    if (-not $ProjectPath) { return $null }
    $logDir = Join-Path $ProjectPath "control\state"
    return Join-Path $logDir "pipeline_snapshots.jsonl"
}

function Get-PipelineLogHash {
    param($Record)

    if (-not $Record) { return "" }
    $hashContent = $Record | ConvertTo-Json -Depth 4 -Compress
    return $hashContent.GetHashCode().ToString()
}

function Write-PipelineSnapshotIfEnabled {
    param(
        $State,
        $Snapshot,
        [string]$ProjectPath
    )

    if (-not $State -or -not $State.EnableSnapshotLogging) { return }
    if (-not $Snapshot) { return }

    $summary = Get-PipelineSummary -Snapshot $Snapshot
    if (-not $summary) { return }

    $sourceValue = $summary.Source
    if (-not $sourceValue -or [string]::IsNullOrWhiteSpace($sourceValue)) {
        $mode = if ($Snapshot -and $Snapshot.ReadinessMode) { $Snapshot.ReadinessMode } else { "live" }
        $sourceValue = "snapshot.py ($mode)"
    }

    $nonGreenStages = @($summary.StageStates | Where-Object { $_.state -ne "GREEN" -and $_.state -ne "GRAY" })

    $record = @{
        ts      = [datetime]::UtcNow.ToString("o")
        stages  = [ordered]@{}
        next    = $summary.NextHint.Command
        reason  = $summary.NextHint.Reason
        source  = $sourceValue
        any_non_green = [bool]($nonGreenStages.Count -gt 0)
        counts  = [ordered]@{
            queued  = $summary.Counts.queued
            active  = $summary.Counts.active
            blocked = $summary.Counts.blocked
            total   = $summary.Counts.total
        }
    }

    # Sort stages for deterministic hashing
    $sortedStages = @($summary.StageStates | Sort-Object -Property name)
    foreach ($stage in $sortedStages) {
        if ($stage.name) {
            $record.stages[$stage.name] = $stage.state
        }
    }

    # Dedupe on content (ignore ts)
    $hashBasis = [ordered]@{
        stages = $record.stages
        next   = $record.next
        reason = $record.reason
        source = $record.source
        counts = $record.counts
        any_non_green = $record.any_non_green
    }
    $hash = Get-PipelineLogHash -Record $hashBasis
    $isTransitionIntoNonGreen = (-not $State.LastPipelineNonGreen) -and $record.any_non_green
    if (($hash -eq $State.LastPipelineSnapshotHash) -and (-not $isTransitionIntoNonGreen)) { 
        # Update last non-green flag even if we skip logging
        $State.LastPipelineNonGreen = $record.any_non_green
        return 
    }

    $logPath = Get-PipelineLogPath -ProjectPath $ProjectPath
    if (-not $logPath) { return }

    $logDir = Split-Path $logPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }

    try {
        $jsonLine = $record | ConvertTo-Json -Depth 4 -Compress
        Add-Content -Path $logPath -Value $jsonLine -Encoding UTF8
        $State.LastPipelineSnapshotHash = $hash
        $State.LastPipelineNonGreen = $record.any_non_green
    }
    catch {
        # Logging failures should never break UI
        return
    }
}
