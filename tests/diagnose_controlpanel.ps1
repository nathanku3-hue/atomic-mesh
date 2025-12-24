#!/usr/bin/env pwsh
# Diagnostic that simulates EXACTLY what control_panel.ps1 does
$ErrorActionPreference = "Stop"

Write-Host "=== CONTROL PANEL SIMULATION ===" -ForegroundColor Cyan
Write-Host "PS Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host ""

# Capture launch path EXACTLY like control_panel.ps1 does
$LaunchPath = (Get-Location).Path
Write-Host "Launch path: $LaunchPath" -ForegroundColor Gray

# Navigate to repo root (where control_panel.ps1 lives)
Set-Location $PSScriptRoot/..
Write-Host "Repo root: $(Get-Location)" -ForegroundColor Gray
Write-Host ""

# Step 1: Load module EXACTLY like control_panel.ps1
Write-Host "[1] Loading module (same as control_panel.ps1)..." -NoNewline
$repoRoot = Join-Path $PSScriptRoot ".."
$modulePath = Join-Path $repoRoot "src\AtomicMesh.UI\AtomicMesh.UI.psd1"
if (-not (Test-Path $modulePath)) {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    Module not found: $modulePath" -ForegroundColor Yellow
    exit 1
}
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}

# Step 2: Test that Get-RealSnapshot is accessible from module scope
Write-Host "[2] Testing module-scoped function access..." -NoNewline
$testResult = & (Get-Module AtomicMesh.UI) {
    try {
        $raw = Get-RealSnapshot -RepoRoot $args[0]
        return @{ Success = $true; Data = $raw }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
} $LaunchPath

if ($testResult.Success) {
    Write-Host " OK" -ForegroundColor Green
    Write-Host "    ReadinessMode: $($testResult.Data.ReadinessMode)" -ForegroundColor Gray
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($testResult.Error)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Get-RealSnapshot fails when called from module scope." -ForegroundColor Red
    Write-Host "This is the root cause of 'Backend unavailable'." -ForegroundColor Red
    exit 1
}

# Step 3: Test SnapshotLoader creation from module scope
Write-Host "[3] Testing SnapshotLoader from module scope..." -NoNewline
$loaderTestResult = & (Get-Module AtomicMesh.UI) {
    $SnapshotLoader = { param($root) Get-RealSnapshot -RepoRoot $root }
    try {
        $raw = & $SnapshotLoader $args[0]
        return @{ Success = $true; Data = $raw }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
} $LaunchPath

if ($loaderTestResult.Success) {
    Write-Host " OK" -ForegroundColor Green
    Write-Host "    ReadinessMode: $($loaderTestResult.Data.ReadinessMode)" -ForegroundColor Gray
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($loaderTestResult.Error)" -ForegroundColor Yellow
    exit 1
}

# Step 4: Test Convert-RawSnapshotToUi from module scope
Write-Host "[4] Testing Convert-RawSnapshotToUi..." -NoNewline
$convertResult = & (Get-Module AtomicMesh.UI) {
    try {
        $snapshot = Convert-RawSnapshotToUi -Raw $args[0]
        return @{
            Success = $true
            AdapterError = $snapshot.AdapterError
            DocScores = $snapshot.DocScores
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
} $testResult.Data

if ($convertResult.Success) {
    Write-Host " OK" -ForegroundColor Green
    Write-Host "    AdapterError: '$($convertResult.AdapterError)'" -ForegroundColor Gray
    if ($convertResult.AdapterError) {
        Write-Host ""
        Write-Host "AdapterError is SET. This causes 'Backend unavailable'." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($convertResult.Error)" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "=== ALL MODULE-SCOPED TESTS PASSED ===" -ForegroundColor Green
Write-Host ""
Write-Host "If control_panel.ps1 still shows 'Backend unavailable':" -ForegroundColor Cyan
Write-Host "1. Close ALL PowerShell/Terminal windows" -ForegroundColor White
Write-Host "2. Open a completely NEW window" -ForegroundColor White
Write-Host "3. cd to: $(Get-Location)" -ForegroundColor White
Write-Host "4. Run: .\control_panel.ps1" -ForegroundColor White
