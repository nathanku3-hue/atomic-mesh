# Run this to diagnose where "1 pending | 2 active" comes from
# Usage: powershell -NoProfile -File diagnose_counts.ps1

$ErrorActionPreference = "Stop"
$projectPath = (Get-Location).Path

Write-Host "=== DIAGNOSTIC: Header Counts Issue ===" -ForegroundColor Yellow
Write-Host "Project Path: $projectPath" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check for database files
Write-Host "=== Step 1: Database Files ===" -ForegroundColor Yellow
$meshDb = Join-Path $projectPath "mesh.db"
$tasksDb = Join-Path $projectPath "tasks.db"

Write-Host "  mesh.db:  $(if (Test-Path $meshDb) { 'EXISTS' } else { 'NOT FOUND' })" -ForegroundColor $(if (Test-Path $meshDb) { 'Green' } else { 'DarkGray' })
Write-Host "  tasks.db: $(if (Test-Path $tasksDb) { 'EXISTS' } else { 'NOT FOUND' })" -ForegroundColor $(if (Test-Path $tasksDb) { 'Green' } else { 'DarkGray' })

# Step 2: Run snapshot.py directly
Write-Host ""
Write-Host "=== Step 2: snapshot.py Output ===" -ForegroundColor Yellow
$snapshotPath = Join-Path $projectPath "tools\snapshot.py"
if (Test-Path $snapshotPath) {
    $result = & python $snapshotPath $projectPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $result | ConvertFrom-Json
        Write-Host "  DbPathTried: $($json.DbPathTried)" -ForegroundColor Cyan
        Write-Host "  DbPresent: $($json.DbPresent)" -ForegroundColor Cyan
        Write-Host "  DistinctLaneCounts.pending: $($json.DistinctLaneCounts.pending)" -ForegroundColor Magenta
        Write-Host "  DistinctLaneCounts.active: $($json.DistinctLaneCounts.active)" -ForegroundColor Magenta
        Write-Host "  LaneCounts: $($json.LaneCounts.Count) entries" -ForegroundColor Gray
    } else {
        Write-Host "  ERROR: $result" -ForegroundColor Red
    }
} else {
    Write-Host "  snapshot.py not found at: $snapshotPath" -ForegroundColor Red
}

# Step 3: Check module loading
Write-Host ""
Write-Host "=== Step 3: Module Functions ===" -ForegroundColor Yellow
$modulePath = Join-Path $projectPath "src\AtomicMesh.UI\AtomicMesh.UI.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force

    # Check what SnapshotLoader would be used
    Write-Host "  Module loaded from: $modulePath" -ForegroundColor Green

    # Dot-source private files to test
    $privateRoot = Join-Path $projectPath "src\AtomicMesh.UI\Private"
    . "$privateRoot\Models\PlanState.ps1"
    . "$privateRoot\Models\LaneMetrics.ps1"
    . "$privateRoot\Models\WorkerInfo.ps1"
    . "$privateRoot\Models\SchedulerDecision.ps1"
    . "$privateRoot\Models\UiAlerts.ps1"
    . "$privateRoot\Models\UiToast.ps1"
    . "$privateRoot\Models\UiEvent.ps1"
    . "$privateRoot\Models\UiEventLog.ps1"
    . "$privateRoot\Models\UiSnapshot.ps1"
    . "$privateRoot\Models\UiCache.ps1"
    . "$privateRoot\Models\UiState.ps1"
    . "$privateRoot\Adapters\RealAdapter.ps1"
    . "$privateRoot\Reducers\ComputeLaneMetrics.ps1"

    # Get snapshot via RealAdapter
    Write-Host ""
    Write-Host "=== Step 4: Get-RealSnapshot Result ===" -ForegroundColor Yellow
    try {
        $raw = Get-RealSnapshot -RepoRoot $projectPath
        Write-Host "  DistinctLaneCounts.pending: $($raw.DistinctLaneCounts.pending)" -ForegroundColor Magenta
        Write-Host "  DistinctLaneCounts.active: $($raw.DistinctLaneCounts.active)" -ForegroundColor Magenta

        $snapshot = Convert-RawSnapshotToUi -Raw $raw
        Write-Host ""
        Write-Host "=== Step 5: Converted UiSnapshot ===" -ForegroundColor Yellow
        Write-Host "  DistinctLaneCounts.pending: $($snapshot.DistinctLaneCounts.pending)" -ForegroundColor Magenta
        Write-Host "  DistinctLaneCounts.active: $($snapshot.DistinctLaneCounts.active)" -ForegroundColor Magenta
        Write-Host "  LaneMetrics count: $($snapshot.LaneMetrics.Count)" -ForegroundColor Gray

        if ($snapshot.LaneMetrics -and $snapshot.LaneMetrics.Count -gt 0) {
            Write-Host "  LaneMetrics details:" -ForegroundColor Yellow
            foreach ($lane in $snapshot.LaneMetrics) {
                Write-Host "    $($lane.Name): Queued=$($lane.Queued), Active=$($lane.Active)" -ForegroundColor DarkGray
            }
        }

        # Simulate header calculation
        Write-Host ""
        Write-Host "=== Step 6: Header Calculation ===" -ForegroundColor Yellow
        $pendingCount = 0
        $activeCount = 0

        if ($snapshot.DistinctLaneCounts) {
            $pendingCount = [int]$snapshot.DistinctLaneCounts.pending
            $activeCount = [int]$snapshot.DistinctLaneCounts.active
            Write-Host "  Source: DistinctLaneCounts" -ForegroundColor Green
        } elseif ($snapshot.LaneMetrics) {
            foreach ($lane in $snapshot.LaneMetrics) {
                $pendingCount += $lane.Queued
                $activeCount += $lane.Active
            }
            Write-Host "  Source: LaneMetrics FALLBACK" -ForegroundColor Yellow
        } else {
            Write-Host "  Source: NONE (both empty)" -ForegroundColor Red
        }

        Write-Host ""
        Write-Host "  *** HEADER SHOULD SHOW: $pendingCount pending | $activeCount active ***" -ForegroundColor White -BackgroundColor DarkBlue

    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  Module not found at: $modulePath" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== END DIAGNOSTIC ===" -ForegroundColor Yellow
