$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = "$RepoRoot\src\AtomicMesh.UI"

$files = @(
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1'
)
foreach ($file in $files) {
    $fullPath = Join-Path $ModuleRoot $file
    if (Test-Path $fullPath) { . $fullPath }
}

function Test-Check {
    param([string]$Name, [scriptblock]$Block)
    Write-Host "CHECK: $Name ... " -NoNewline
    try {
        $result = & $Block
        if ($result -eq $true) {
            Write-Host "PASS" -ForegroundColor Green
        } else {
            Write-Host "FAIL ($result)" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Test-Check "Pipeline reason includes stage abbreviation" {
    $snap = [UiSnapshot]::new()
    $snap.PlanState = [PlanState]::new()
    $snap.PlanState.Status = "DRAFT"
    $snap.PlanState.HasDraft = $true
    $snap.ReadinessMode = "live"

    $directives = Get-PipelineRightColumn -Snapshot $snap
    $reason = $directives[4].Text
    if ($reason -notmatch "Reason: PLN:") {
        return "Expected Plan abbreviation in reason line, got '$reason'"
    }
    return $true
}

Test-Check "Pipeline reason turns red when context is RED" {
    $snap = [UiSnapshot]::new()
    $snap.PlanState = [PlanState]::new()
    $snap.PlanState.Status = "PRE_INIT"  # Context RED

    $directives = Get-PipelineRightColumn -Snapshot $snap
    $color = $directives[4].Color
    if ($color -ne "Red") { return "Expected Red reason color, got $color" }
    return $true
}

Write-Host "All pipeline reason checks passed." -ForegroundColor Green
exit 0
