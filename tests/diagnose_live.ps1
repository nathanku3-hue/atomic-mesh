#!/usr/bin/env pwsh
# Live diagnostic: Trace exactly what happens in /draft-plan flow

$ErrorActionPreference = "Continue"  # Don't stop on errors, we want to see them

Write-Host "=== LIVE DIAGNOSTIC: /draft-plan ===" -ForegroundColor Cyan
Write-Host ""

# Load module
$modulePath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "AtomicMesh.UI.psm1"
Write-Host "1. Loading module..." -ForegroundColor Yellow
try {
    Import-Module $modulePath -Force
    Write-Host "   OK" -ForegroundColor Green
} catch {
    Write-Host "   FAILED: $_" -ForegroundColor Red
    exit 1
}

# Dot-source private files to access internals
$privateRoot = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private"
Write-Host ""
Write-Host "2. Loading private files..." -ForegroundColor Yellow

$files = @(
    "Models/UiToast.ps1",
    "Models/PlanState.ps1",
    "Models/LaneMetrics.ps1",
    "Models/WorkerInfo.ps1",
    "Models/SchedulerDecision.ps1",
    "Models/UiAlerts.ps1",
    "Models/UiSnapshot.ps1",
    "Models/UiCache.ps1",
    "Models/UiState.ps1",
    "Guards/CommandGuards.ps1",
    "Adapters/MeshServerAdapter.ps1"
)

foreach ($f in $files) {
    $path = Join-Path $privateRoot $f
    try {
        . $path
        Write-Host "   $f OK" -ForegroundColor Green
    } catch {
        Write-Host "   $f FAILED: $_" -ForegroundColor Red
    }
}

# Get project path
$projectPath = (Get-Location).Path
Write-Host ""
Write-Host "3. Project path: $projectPath" -ForegroundColor Yellow

# Create state and snapshot
Write-Host ""
Write-Host "4. Creating State + Snapshot..." -ForegroundColor Yellow

try {
    $state = [UiState]::new()
    $state.Cache = [UiCache]::new()
    $state.Cache.Metadata = @{
        "ProjectPath" = $projectPath
        "ModuleRoot" = (Split-Path -Parent (Split-Path -Parent $modulePath))
    }
    $state.Toast = [UiToast]::new()
    Write-Host "   State created" -ForegroundColor Green
} catch {
    Write-Host "   State FAILED: $_" -ForegroundColor Red
    exit 1
}

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.IsInitialized = $true
    $snapshot.DocsAllPassed = $true
    $snapshot.BlockingFiles = @()
    $snapshot.ReadinessMode = "normal"
    Write-Host "   Snapshot created" -ForegroundColor Green
} catch {
    Write-Host "   Snapshot FAILED: $_" -ForegroundColor Red
    exit 1
}

# Test guard
Write-Host ""
Write-Host "5. Testing guard: Test-CanDraftPlan..." -ForegroundColor Yellow
$guard = Test-CanDraftPlan -Snapshot $snapshot -State $state
Write-Host "   Guard result:" -ForegroundColor Cyan
$guard | Format-Table -AutoSize

if (-not $guard.Ok) {
    Write-Host "   GUARD BLOCKED! Message: $($guard.Message)" -ForegroundColor Red
} else {
    Write-Host "   Guard passed" -ForegroundColor Green
}

# Test adapter directly
Write-Host ""
Write-Host "6. Testing adapter: Invoke-DraftPlan..." -ForegroundColor Yellow
$draftResult = Invoke-DraftPlan -ProjectPath $projectPath -TimeoutMs 10000
Write-Host "   Adapter result:" -ForegroundColor Cyan
$draftResult | Format-Table -AutoSize

Write-Host "   Status: $($draftResult.Status)" -ForegroundColor Cyan
Write-Host "   Ok: $($draftResult.Ok)" -ForegroundColor Cyan
Write-Host "   Message: $($draftResult.Message)" -ForegroundColor Cyan
Write-Host "   Path: $($draftResult.Path)" -ForegroundColor Cyan

# Simulate router switch
Write-Host ""
Write-Host "7. Simulating router switch statement..." -ForegroundColor Yellow
Write-Host "   Input status: '$($draftResult.Status)'" -ForegroundColor Gray

switch ($draftResult.Status) {
    "OK" {
        Write-Host "   MATCHED: OK" -ForegroundColor Green
        $leafName = Split-Path $draftResult.Path -Leaf
        $toastMsg = "Draft created: $leafName"
        Write-Host "   Toast would be: $toastMsg" -ForegroundColor Cyan
    }
    "EXISTS" {
        Write-Host "   MATCHED: EXISTS" -ForegroundColor Green
        $leafName = Split-Path $draftResult.Path -Leaf
        $toastMsg = "Draft exists: $leafName (run /accept-plan)"
        Write-Host "   Toast would be: $toastMsg" -ForegroundColor Cyan
    }
    "BLOCKED" {
        Write-Host "   MATCHED: BLOCKED" -ForegroundColor Yellow
        $filesList = if ($draftResult.BlockingFiles.Count -gt 0) {
            $draftResult.BlockingFiles -join ", "
        } else { "context docs" }
        $toastMsg = "BLOCKED: Complete $filesList first"
        Write-Host "   Toast would be: $toastMsg" -ForegroundColor Yellow
    }
    default {
        Write-Host "   MATCHED: default (ERROR or unknown)" -ForegroundColor Red
        $msg = if ($draftResult.Message) { $draftResult.Message } else { "Unknown error" }
        $toastMsg = "Draft failed: $msg"
        Write-Host "   Toast would be: $toastMsg" -ForegroundColor Red
    }
}

# Now call the actual router
Write-Host ""
Write-Host "8. Calling actual Invoke-CommandRouter..." -ForegroundColor Yellow

# Read router source to dot-source it
$routerPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Public" "Invoke-CommandRouter.ps1"
. $routerPath

try {
    $result = Invoke-CommandRouter -Command "/draft-plan" -State $state -Snapshot $snapshot
    Write-Host "   Router returned: $result" -ForegroundColor Cyan
} catch {
    Write-Host "   Router EXCEPTION: $_" -ForegroundColor Red
    Write-Host "   $($_.ScriptStackTrace)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "9. State after router:" -ForegroundColor Yellow
Write-Host "   CurrentPage: $($state.CurrentPage)" -ForegroundColor Gray
Write-Host "   ForceDataRefresh: $($state.ForceDataRefresh)" -ForegroundColor Gray
Write-Host "   Toast.Message: $($state.Toast.Message)" -ForegroundColor Gray
Write-Host "   Toast.Level: $($state.Toast.Level)" -ForegroundColor Gray

Write-Host ""
Write-Host "=== DIAGNOSTIC COMPLETE ===" -ForegroundColor Cyan
