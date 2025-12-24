#!/usr/bin/env pwsh
# Diagnose path flow through the snapshot system
# This traces exactly what path is used at each step

$ErrorActionPreference = "Stop"

Write-Host "=== Path Flow Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# Step 0: Environment
Write-Host "Step 0: Environment" -ForegroundColor Yellow
Write-Host "  Current directory: $(Get-Location)"
Write-Host "  Script directory: $PSScriptRoot"
Write-Host ""

Set-Location $PSScriptRoot/..

# Load module
$modulePath = Join-Path $PSScriptRoot "..\src\AtomicMesh.UI\AtomicMesh.UI.psd1"
Import-Module $modulePath -Force

# Test with different project paths
$testPaths = @(
    @{ Name = "E:\Code\new"; Expected = "0 pending, 0 active (no DB)" },
    @{ Name = "E:\Code\atomic-mesh-ui-sandbox"; Expected = "counts from module's DB" }
)

foreach ($test in $testPaths) {
    $path = $test.Name
    Write-Host "Step 1: Testing path '$path'" -ForegroundColor Yellow

    # Check if path exists
    if (-not (Test-Path $path)) {
        Write-Host "  [SKIP] Path does not exist" -ForegroundColor Gray
        Write-Host ""
        continue
    }

    # Check for DBs
    $tasksDb = Join-Path $path "tasks.db"
    $meshDb = Join-Path $path "mesh.db"
    Write-Host "  tasks.db exists: $(Test-Path $tasksDb)"
    Write-Host "  mesh.db exists: $(Test-Path $meshDb)"

    # Call snapshot.py directly
    Write-Host "  Calling snapshot.py..." -ForegroundColor Gray
    $output = python tools/snapshot.py $path 2>&1
    try {
        $json = $output | ConvertFrom-Json
        Write-Host "  ProjectRoot: $($json.ProjectRoot)"
        Write-Host "  DbPathTried: $($json.DbPathTried)"
        Write-Host "  DbPresent: $($json.DbPresent)"
        Write-Host "  ReadinessMode: $($json.ReadinessMode)"
        Write-Host "  IsInitialized: $($json.IsInitialized)"
        Write-Host "  DistinctLaneCounts.pending: $($json.DistinctLaneCounts.pending)"
        Write-Host "  DistinctLaneCounts.active: $($json.DistinctLaneCounts.active)"
        Write-Host "  [OK] Expected: $($test.Expected)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] JSON parse error: $_" -ForegroundColor Red
        Write-Host "  Raw output: $output" -ForegroundColor Gray
    }

    Write-Host ""
}

Write-Host "Step 2: Testing Get-RealSnapshot function" -ForegroundColor Yellow
$testPath = "E:\Code\new"
if (Test-Path $testPath) {
    try {
        $raw = Get-RealSnapshot -RepoRoot $testPath
        Write-Host "  RepoRoot passed: $testPath"
        Write-Host "  DistinctLaneCounts.pending: $($raw.DistinctLaneCounts.pending)"
        Write-Host "  DistinctLaneCounts.active: $($raw.DistinctLaneCounts.active)"
        Write-Host "  [OK]" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "  [SKIP] E:\Code\new does not exist" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Diagnostic Complete ===" -ForegroundColor Cyan
