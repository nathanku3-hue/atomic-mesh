#!/usr/bin/env powershell
# Test specifically for PS5.1 compatibility
$ErrorActionPreference = "Stop"

Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host "Working dir: $(Get-Location)" -ForegroundColor Cyan

Set-Location $PSScriptRoot/..

Write-Host "`n=== Loading Module ===" -ForegroundColor Yellow
try {
    Import-Module ./src/AtomicMesh.UI/AtomicMesh.UI.psd1 -Force -ErrorAction Stop
    Write-Host "Module loaded OK" -ForegroundColor Green
} catch {
    Write-Host "Module load FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

Write-Host "`n=== Testing RealAdapter ===" -ForegroundColor Yellow
# Dot-source to get access to private function
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1

try {
    $raw = Get-RealSnapshot -RepoRoot "."
    Write-Host "Snapshot OK" -ForegroundColor Green
    Write-Host "  ReadinessMode: $($raw.ReadinessMode)"
} catch {
    Write-Host "Snapshot FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}
