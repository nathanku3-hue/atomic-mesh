#!/usr/bin/env pwsh
# Test module internal snapshot loading
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot/..
Write-Host "Working dir: $(Get-Location)" -ForegroundColor Cyan

# Load module
Write-Host "`n=== Module Import ===" -ForegroundColor Yellow
Import-Module ./src/AtomicMesh.UI/AtomicMesh.UI.psd1 -Force
Write-Host "Module loaded OK" -ForegroundColor Green

# Check internal function by reading the file and looking for timeout
Write-Host "`n=== Check RealAdapter Timeout ===" -ForegroundColor Yellow
$adapterPath = "./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1"
$content = Get-Content $adapterPath -Raw
if ($content -match '\$timeoutMs\s*=\s*(\d+)') {
    $timeout = [int]$Matches[1]
    Write-Host "File timeout: ${timeout}ms" -ForegroundColor $(if ($timeout -ge 1000) { "Green" } else { "Red" })
} else {
    Write-Host "Could not find timeout in file" -ForegroundColor Yellow
}

# Check Python timing guard
Write-Host "`n=== Check snapshot.py Timing Guard ===" -ForegroundColor Yellow
$snapshotPy = "./tools/snapshot.py"
$pyContent = Get-Content $snapshotPy -Raw
if ($pyContent -match 'TIMING_GUARD_MS\s*=\s*(\d+)') {
    $guard = [int]$Matches[1]
    Write-Host "Python guard: ${guard}ms" -ForegroundColor $(if ($guard -ge 400) { "Green" } else { "Red" })
} else {
    Write-Host "Could not find timing guard" -ForegroundColor Yellow
}

# Test internal call by dot-sourcing the adapter file in current scope
Write-Host "`n=== Direct Adapter Test ===" -ForegroundColor Yellow
. $adapterPath

try {
    $raw = Get-RealSnapshot -RepoRoot "."
    Write-Host "Snapshot OK" -ForegroundColor Green
    Write-Host "  ReadinessMode: $($raw.ReadinessMode)"
    if ($raw.DocScores) {
        Write-Host "  DocScores: $($raw.DocScores | ConvertTo-Json -Compress)"
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
