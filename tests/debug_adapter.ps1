#!/usr/bin/env pwsh
# Debug script to test adapter and snapshot loading
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot/..
Write-Host "Working dir: $(Get-Location)" -ForegroundColor Cyan

# Test 1: Direct Python call
Write-Host "`n=== Test 1: Direct Python ===" -ForegroundColor Yellow
try {
    $result = python tools/snapshot.py . 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $result | ConvertFrom-Json
        Write-Host "Python OK - DocScores: $($json.DocScores | ConvertTo-Json -Compress)" -ForegroundColor Green
    } else {
        Write-Host "Python FAILED: $result" -ForegroundColor Red
    }
} catch {
    Write-Host "Python ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: RealAdapter
Write-Host "`n=== Test 2: RealAdapter ===" -ForegroundColor Yellow
try {
    . ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
    $raw = Get-RealSnapshot -RepoRoot "."
    Write-Host "RealAdapter OK - DocScores present: $($null -ne $raw.DocScores)" -ForegroundColor Green
    if ($raw.DocScores) {
        Write-Host ($raw.DocScores | ConvertTo-Json -Depth 3)
    }
} catch {
    Write-Host "RealAdapter ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Full module load and Get-PipelineRightColumn
Write-Host "`n=== Test 3: Get-PipelineRightColumn ===" -ForegroundColor Yellow
try {
    . ./src/AtomicMesh.UI/Private/Models/PlanState.ps1
    . ./src/AtomicMesh.UI/Private/Models/LaneMetrics.ps1
    . ./src/AtomicMesh.UI/Private/Models/SchedulerDecision.ps1
    . ./src/AtomicMesh.UI/Private/Models/UiAlerts.ps1
    . ./src/AtomicMesh.UI/Private/Models/UiSnapshot.ps1
    . ./src/AtomicMesh.UI/Private/Render/Console.ps1
    . ./src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1

    $snapshot = Convert-RawSnapshotToUi -Raw $raw
    Write-Host "Snapshot AdapterError: '$($snapshot.AdapterError)'" -ForegroundColor Cyan
    Write-Host "Snapshot DocScores: $($snapshot.DocScores | ConvertTo-Json -Compress)" -ForegroundColor Cyan

    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    Write-Host "First directive: '$($directives[0].Text)'" -ForegroundColor $(if ($directives[0].Text -eq "STATUS") { "Red" } else { "Green" })

    foreach ($d in $directives) {
        Write-Host "  - $($d.Text) [$($d.Color)]"
    }
} catch {
    Write-Host "Pipeline ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}
