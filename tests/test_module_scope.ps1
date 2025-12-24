#!/usr/bin/env pwsh
# Test that Get-RealSnapshot works from within module scope
param([string]$ProjectPath = "E:\Code\new")

$ErrorActionPreference = "Stop"

Write-Host "=== Module Scope Test ===" -ForegroundColor Cyan
Write-Host "Testing from: $ProjectPath"
Write-Host ""

# Import the module
$modulePath = Join-Path $PSScriptRoot "..\src\AtomicMesh.UI\AtomicMesh.UI.psd1"
Import-Module $modulePath -Force

# Test from within module scope using & (Get-Module)
Write-Host "Calling Get-RealSnapshot from module scope..." -ForegroundColor Yellow

$result = & (Get-Module AtomicMesh.UI) {
    param($path)
    try {
        $raw = Get-RealSnapshot -RepoRoot $path
        return @{
            Success = $true
            ReadinessMode = $raw.ReadinessMode
            IsInitialized = $raw.IsInitialized
            DbPresent = $raw.DbPresent
        }
    } catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
} -args $ProjectPath

if ($result.Success) {
    Write-Host "[OK] Get-RealSnapshot works from module scope" -ForegroundColor Green
    Write-Host "  ReadinessMode: $($result.ReadinessMode)"
    Write-Host "  IsInitialized: $($result.IsInitialized)"
    Write-Host "  DbPresent: $($result.DbPresent)"
} else {
    Write-Host "[FAIL] Get-RealSnapshot failed: $($result.Error)" -ForegroundColor Red
}
