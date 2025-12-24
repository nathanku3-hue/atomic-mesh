$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = "$RepoRoot\src\AtomicMesh.UI"

# Load models and history overlay helpers
$files = @(
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiToast.ps1',
    'Private/Models/UiEvent.ps1',
    'Private/Models/UiEventLog.ps1',
    'Private/Models/UiCache.ps1',
    'Private/Models/UiState.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Render/Overlays/RenderHistory.ps1'
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

Test-Check "History rows retrieved for TASKS subview" {
    $state = [UiState]::new()
    $snap = [UiSnapshot]::new()
    $snap.IsInitialized = $true
    $snap.HistoryTasks = @(
        @{ worker = "BE"; content = "Task A"; status = "done" },
        @{ worker = "FE"; content = "Task B"; status = "pending" }
    )
    $state.Cache.LastSnapshot = $snap

    $rows = Get-HistoryRows -State $state -Subview "TASKS"
    if ($rows.Count -ne 2) { return "Expected 2 history rows, got $($rows.Count)" }
    if ($rows[0].worker -ne "BE" -or $rows[1].status -ne "pending") {
        return "Unexpected row content"
    }
    return $true
}

Test-Check "History rows fall back to empty when snapshot missing" {
    $state = [UiState]::new()
    $rows = Get-HistoryRows -State $state -Subview "DOCS"
    if ($rows.Count -ne 0) { return "Expected empty rows when no snapshot" }
    return $true
}

Write-Host "All history overlay data checks passed." -ForegroundColor Green
exit 0
