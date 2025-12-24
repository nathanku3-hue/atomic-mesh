#!/usr/bin/env pwsh
# Complete diagnostic for backend unavailable issue
param([switch]$Verbose)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot/..

Write-Host "=== BACKEND DIAGNOSTIC ===" -ForegroundColor Cyan
Write-Host "PS Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "Working Dir: $(Get-Location)" -ForegroundColor Gray
Write-Host ""

$failed = $false

# Step 1: Check Python
Write-Host "[1] Python check..." -NoNewline
try {
    $pyVer = python --version 2>&1
    Write-Host " OK ($pyVer)" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    Python not found in PATH" -ForegroundColor Yellow
    $failed = $true
}

# Step 2: Check snapshot.py exists
Write-Host "[2] snapshot.py exists..." -NoNewline
$snapshotPy = "./tools/snapshot.py"
if (Test-Path $snapshotPy) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    File not found: $snapshotPy" -ForegroundColor Yellow
    $failed = $true
}

# Step 3: Run snapshot.py directly
Write-Host "[3] Direct Python call..." -NoNewline
try {
    $result = python tools/snapshot.py . 2>&1
    if ($LASTEXITCODE -eq 0) {
        $json = $result | ConvertFrom-Json
        Write-Host " OK (ReadinessMode: $($json.ReadinessMode))" -ForegroundColor Green
        if ($Verbose) {
            Write-Host "    DocScores: $($json.DocScores | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    } else {
        Write-Host " FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "    $result" -ForegroundColor Yellow
        $failed = $true
    }
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    $failed = $true
}

# Step 4: Check timeout values in files
Write-Host "[4] Timeout values..." -NoNewline
$adapterContent = Get-Content ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1 -Raw
$pyContent = Get-Content ./tools/snapshot.py -Raw
$adapterTimeout = if ($adapterContent -match '\$timeoutMs\s*=\s*(\d+)') { [int]$Matches[1] } else { 0 }
$pyGuard = if ($pyContent -match 'TIMING_GUARD_MS\s*=\s*(\d+)') { [int]$Matches[1] } else { 0 }

if ($adapterTimeout -ge 1000 -and $pyGuard -ge 400) {
    Write-Host " OK (Adapter: ${adapterTimeout}ms, Python: ${pyGuard}ms)" -ForegroundColor Green
} else {
    Write-Host " WARNING" -ForegroundColor Yellow
    Write-Host "    Adapter timeout: ${adapterTimeout}ms (should be >= 1000)" -ForegroundColor Yellow
    Write-Host "    Python guard: ${pyGuard}ms (should be >= 400)" -ForegroundColor Yellow
}

# Step 5: Check for PS7+ syntax (exclude comments)
Write-Host "[5] PS5 syntax check..." -NoNewline
# Match actual usage like "$x ?? 0" not comments mentioning ??
$codeLines = $adapterContent -split "`n" | Where-Object { $_ -notmatch '^\s*#' }
$codeOnly = $codeLines -join "`n"
$hasPS7Syntax = $codeOnly -match '\$\w+\s*\?\?' -or $codeOnly -match '\?\.'
if ($hasPS7Syntax) {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    Found PS7+ syntax (?? or ?.) in RealAdapter.ps1" -ForegroundColor Yellow
    $failed = $true
} else {
    Write-Host " OK (no PS7+ syntax)" -ForegroundColor Green
}

# Step 6: Load module
Write-Host "[6] Module load..." -NoNewline
try {
    Import-Module ./src/AtomicMesh.UI/AtomicMesh.UI.psd1 -Force -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    $failed = $true
}

# Step 7: Test RealAdapter through module context
Write-Host "[7] RealAdapter call..." -NoNewline
# Must dot-source since it's private
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = Get-RealSnapshot -RepoRoot "."
    $sw.Stop()
    $elapsed = $sw.ElapsedMilliseconds
    Write-Host " OK (${elapsed}ms, Mode: $($raw.ReadinessMode))" -ForegroundColor Green
    if ($Verbose -and $raw.DocScores) {
        Write-Host "    DocScores: $($raw.DocScores | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
    $failed = $true
}

# Summary
Write-Host ""
if ($failed) {
    Write-Host "=== DIAGNOSTIC FAILED ===" -ForegroundColor Red
    Write-Host "Fix the issues above and try again." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
    Write-Host "Close this window completely, reopen PowerShell, then run:" -ForegroundColor Cyan
    Write-Host "  .\control_panel.ps1" -ForegroundColor White
    exit 0
}
