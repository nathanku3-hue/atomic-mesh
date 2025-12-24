#!/usr/bin/env pwsh
# Full control panel simulation diagnostic
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot/..

Write-Host "=== FULL CONTROL PANEL DIAGNOSTIC ===" -ForegroundColor Cyan
Write-Host "PS Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host ""

# Step 1: Force remove any cached module
Write-Host "[1] Clearing module cache..." -NoNewline
try {
    Remove-Module AtomicMesh.UI -Force -ErrorAction SilentlyContinue
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " (none cached)" -ForegroundColor Gray
}

# Step 2: Import fresh
Write-Host "[2] Importing module fresh..." -NoNewline
try {
    Import-Module ./src/AtomicMesh.UI/AtomicMesh.UI.psd1 -Force -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This is the root cause. The module failed to load." -ForegroundColor Red
    Write-Host "Check for syntax errors in the .ps1 files." -ForegroundColor Yellow
    exit 1
}

# Step 3: Dot-source RealAdapter to get Get-RealSnapshot
Write-Host "[3] Loading RealAdapter..." -NoNewline
$projectPath = (Get-Location).Path
try {
    . ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "RealAdapter.ps1 failed to load. Check for syntax errors." -ForegroundColor Red
    exit 1
}

# Step 4: Call Get-RealSnapshot directly
Write-Host "[4] Calling Get-RealSnapshot..." -NoNewline
try {
    $raw = Get-RealSnapshot -RepoRoot $projectPath
    if ($raw) {
        Write-Host " OK" -ForegroundColor Green
        Write-Host "    ReadinessMode: $($raw.ReadinessMode)" -ForegroundColor Gray
    } else {
        Write-Host " FAILED (null result)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Get-RealSnapshot failed. This causes 'Backend unavailable'." -ForegroundColor Red
    Write-Host "Exception details:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

# Step 5: Convert to UI snapshot
Write-Host "[5] Convert-RawSnapshotToUi..." -NoNewline
try {
    $snapshot = Convert-RawSnapshotToUi -Raw $raw
    Write-Host " OK" -ForegroundColor Green
    Write-Host "    AdapterError: '$($snapshot.AdapterError)'" -ForegroundColor Gray
    Write-Host "    DocScores: $($snapshot.DocScores | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Convert-RawSnapshotToUi failed. Check RealAdapter.ps1." -ForegroundColor Red
    exit 1
}

# Step 6: Check AdapterError state
Write-Host "[6] Checking error state..." -NoNewline
if ($snapshot.AdapterError -and $snapshot.AdapterError.Length -gt 0) {
    Write-Host " ERROR SET" -ForegroundColor Red
    Write-Host "    AdapterError: $($snapshot.AdapterError)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "AdapterError is set. This causes 'Backend unavailable'." -ForegroundColor Red
    exit 1
} else {
    Write-Host " OK (no error)" -ForegroundColor Green
}

# Step 7: Test Get-PipelineRightColumn
Write-Host "[7] Get-PipelineRightColumn..." -NoNewline
try {
    # Need to dot-source the reducer
    . ./src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $firstText = $directives[0].Text
    if ($firstText -eq "STATUS") {
        Write-Host " ERROR STATE" -ForegroundColor Red
        Write-Host "    Reducer returned STATUS (Backend unavailable)" -ForegroundColor Yellow
        Write-Host "    Check hasAdapterError detection logic" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host " OK ($firstText)" -ForegroundColor Green
    }
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
Write-Host ""
Write-Host "The control panel should work. If still failing:" -ForegroundColor Cyan
Write-Host "1. Close ALL PowerShell windows completely" -ForegroundColor White
Write-Host "2. Open a NEW PowerShell window" -ForegroundColor White
Write-Host "3. Navigate to this directory" -ForegroundColor White
Write-Host "4. Run: .\control_panel.ps1" -ForegroundColor White
