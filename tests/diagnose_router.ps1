#!/usr/bin/env pwsh
# Diagnose router handling of /draft-plan

$ErrorActionPreference = "Stop"

Write-Host "=== Diagnose Router /draft-plan ===" -ForegroundColor Cyan
Write-Host ""

# Load the full module
$modulePath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "AtomicMesh.UI.psm1"
Write-Host "Loading module: $modulePath"
Import-Module $modulePath -Force

# Also dot-source the adapter to make sure it's available
$adapterPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Adapters" "MeshServerAdapter.ps1"
Write-Host "Loading adapter: $adapterPath"
. $adapterPath

$projectPath = (Get-Location).Path
Write-Host "ProjectPath: $projectPath"
Write-Host ""

# Create minimal state and snapshot objects
Write-Host "=== Creating State + Snapshot ===" -ForegroundColor Yellow

# Check if UiState class exists
try {
    $state = [UiState]::new()
    $state.Cache = [UiCache]::new()
    $state.Cache.Metadata = @{
        "ProjectPath" = $projectPath
        "ModuleRoot" = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $adapterPath)))
    }
    $state.Toast = [UiToast]::new()
    Write-Host "State created successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to create UiState: $_" -ForegroundColor Red
    exit 1
}

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.IsInitialized = $true
    $snapshot.DocsAllPassed = $true
    $snapshot.BlockingFiles = @()
    Write-Host "Snapshot created successfully" -ForegroundColor Green
} catch {
    Write-Host "Failed to create UiSnapshot: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Call the router
Write-Host "=== Calling Invoke-CommandRouter /draft-plan ===" -ForegroundColor Yellow
try {
    $result = Invoke-CommandRouter -Command "/draft-plan" -State $state -Snapshot $snapshot
    Write-Host "Router returned: $result" -ForegroundColor Cyan
} catch {
    Write-Host "Router threw exception: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
}

Write-Host ""

# Check state after call
Write-Host "=== State After Router Call ===" -ForegroundColor Yellow
Write-Host "CurrentPage: $($state.CurrentPage)"
Write-Host "ForceDataRefresh: $($state.ForceDataRefresh)"
Write-Host "Toast.Message: $($state.Toast.Message)"
Write-Host "Toast.Severity: $($state.Toast.Severity)"
