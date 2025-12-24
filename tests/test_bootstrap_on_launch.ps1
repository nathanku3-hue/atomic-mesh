#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for bootstrap page auto-switch on launch
.DESCRIPTION
    Verifies:
    - Update-AutoPageFromPlanStatus helper exists
    - Uses Test-RepoInitialized for ground truth (not plan status)
    - Uninitialized repo auto-switches to BOOTSTRAP page
    - Initialized repo auto-switches from BOOTSTRAP to PLAN page
    - Only switches when on PLAN or BOOTSTRAP (not from GO)
#>

$ErrorActionPreference = "Stop"
$testsFailed = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

$controlPanelPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Public" "Start-ControlPanel.ps1"

if (-not (Test-Path $controlPanelPath)) {
    Write-Host "FAIL: Start-ControlPanel.ps1 not found" -ForegroundColor Red
    exit 1
}

$content = Get-Content $controlPanelPath -Raw

# 1) Update-AutoPageFromPlanStatus helper exists
if ($content -match 'function\s+Update-AutoPageFromPlanStatus') {
    Pass "Update-AutoPageFromPlanStatus helper exists"
} else {
    Fail "Update-AutoPageFromPlanStatus helper" "Expected function definition"
}

# 2) Helper uses Test-RepoInitialized (ground truth, not plan status)
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?Test-RepoInitialized') {
    Pass "Helper uses Test-RepoInitialized for ground truth"
} else {
    Fail "Test-RepoInitialized" "Expected Test-RepoInitialized call in Update-AutoPageFromPlanStatus"
}

# 3) Helper checks $isInitialized flag
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?\$isInitialized') {
    Pass "Helper uses isInitialized flag"
} else {
    Fail "isInitialized flag" "Expected isInitialized variable in Update-AutoPageFromPlanStatus"
}

# 4) Switches to BOOTSTRAP only when on PLAN page (not from GO)
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?CurrentPage -eq "PLAN"[\s\S]*?SetPage\("BOOTSTRAP"\)') {
    Pass "Switches to BOOTSTRAP only when on PLAN page"
} else {
    Fail "PLAN->BOOTSTRAP guard" "Expected CurrentPage -eq PLAN check before switching to BOOTSTRAP"
}

# 5) Switches back to PLAN when initialized and on BOOTSTRAP
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?CurrentPage -eq "BOOTSTRAP"[\s\S]*?SetPage\("PLAN"\)') {
    Pass "Switches to PLAN when initialized and on BOOTSTRAP"
} else {
    Fail "BOOTSTRAP->PLAN transition" "Expected transition from BOOTSTRAP to PLAN when initialized"
}

# 6) Helper is called after data refresh
if ($content -match 'Invoke-DataRefreshTick[\s\S]{0,200}Update-AutoPageFromPlanStatus') {
    Pass "Update-AutoPageFromPlanStatus called after data refresh"
} else {
    Fail "Helper invocation" "Expected Update-AutoPageFromPlanStatus after Invoke-DataRefreshTick"
}

# 7) Uses ProjectPath from state metadata
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?Metadata\["ProjectPath"\]') {
    Pass "Uses ProjectPath from state metadata"
} else {
    Fail "ProjectPath usage" "Expected Metadata[ProjectPath] in Update-AutoPageFromPlanStatus"
}

# 8) Stores IsInitialized in state metadata (single source of truth for header)
if ($content -match 'Update-AutoPageFromPlanStatus[\s\S]*?Metadata\["IsInitialized"\]\s*=') {
    Pass "Stores IsInitialized in state metadata"
} else {
    Fail "IsInitialized storage" "Expected Metadata[IsInitialized] = in Update-AutoPageFromPlanStatus"
}

# 9) Header reads IsInitialized from state (not plan status)
$renderCommonPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Render" "RenderCommon.ps1"
if (Test-Path $renderCommonPath) {
    $renderContent = Get-Content $renderCommonPath -Raw
    if ($renderContent -match 'Metadata\["IsInitialized"\]') {
        Pass "Header reads IsInitialized from state metadata"
    } else {
        Fail "Header IsInitialized" "Expected Metadata[IsInitialized] in RenderCommon.ps1"
    }
} else {
    Fail "RenderCommon.ps1" "File not found"
}

Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
