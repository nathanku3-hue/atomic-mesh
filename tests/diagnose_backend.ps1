#!/usr/bin/env pwsh
# Quick diagnostic for "Backend unavailable" errors
$ErrorActionPreference = "Stop"

Write-Host "=== Backend Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# Step 0: Environment info
Write-Host "Step 0: Environment" -ForegroundColor Yellow
Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"
Write-Host "  Current dir: $(Get-Location)"

$pythonVersion = python --version 2>&1
Write-Host "  Python: $pythonVersion"

$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
Write-Host "  Python path: $pythonPath"
Write-Host ""

Set-Location $PSScriptRoot/..

# Load files
. ./src/AtomicMesh.UI/Private/Models/PlanState.ps1
. ./src/AtomicMesh.UI/Private/Models/LaneMetrics.ps1
. ./src/AtomicMesh.UI/Private/Models/SchedulerDecision.ps1
. ./src/AtomicMesh.UI/Private/Models/UiAlerts.ps1
. ./src/AtomicMesh.UI/Private/Models/UiSnapshot.ps1
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1

Write-Host "Step 1: Testing Python directly..." -ForegroundColor Yellow
$testDir = if ($args[0]) { $args[0] } else { (Get-Location).Path }
$resolvedDir = (Resolve-Path $testDir -ErrorAction SilentlyContinue).Path
if (-not $resolvedDir) { $resolvedDir = $testDir }
Write-Host "  Target (input): $testDir"
Write-Host "  Target (resolved): $resolvedDir"

# Check marker/docs before calling Python
$markerPath = Join-Path $resolvedDir "control\state\.mesh_initialized"
$hasMarker = Test-Path $markerPath
$docsDir = Join-Path $resolvedDir "docs"
$docCount = 0
foreach ($doc in @("PRD.md", "SPEC.md", "DECISION_LOG.md")) {
    if (Test-Path (Join-Path $docsDir $doc)) { $docCount++ }
}
Write-Host "  Marker exists: $hasMarker"
Write-Host "  Golden docs: $docCount/3"

try {
    $output = python tools/snapshot.py $resolvedDir 2>&1
    $json = $output | ConvertFrom-Json
    Write-Host "[OK] Python works" -ForegroundColor Green
    Write-Host "  ProjectRoot: $($json.ProjectRoot)"
    Write-Host "  DbPathTried: $($json.DbPathTried)"
    Write-Host "  DbPresent: $($json.DbPresent)"
    Write-Host "  ReadinessMode: $($json.ReadinessMode)"
    Write-Host "  IsInitialized: $($json.IsInitialized)"
} catch {
    Write-Host "[FAIL] Python error: $_" -ForegroundColor Red
    Write-Host "Raw output: $output"
    exit 1
}

Write-Host ""
Write-Host "Step 2: Testing Get-RealSnapshot..." -ForegroundColor Yellow

try {
    $result = Get-RealSnapshot -RepoRoot $testDir
    Write-Host "[OK] Get-RealSnapshot works" -ForegroundColor Green
    Write-Host "  ReadinessMode: $($result.ReadinessMode)"
    Write-Host "  IsInitialized: $($result.IsInitialized)"
} catch {
    Write-Host "[FAIL] Get-RealSnapshot error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 3: Testing Convert-RawSnapshotToUi..." -ForegroundColor Yellow

try {
    $snapshot = Convert-RawSnapshotToUi -Raw $result
    Write-Host "[OK] Convert-RawSnapshotToUi works" -ForegroundColor Green
    Write-Host "  AdapterError: '$($snapshot.AdapterError)'"
    Write-Host "  IsInitialized: $($snapshot.IsInitialized)"
} catch {
    Write-Host "[FAIL] Convert-RawSnapshotToUi error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== All checks passed ===" -ForegroundColor Green
