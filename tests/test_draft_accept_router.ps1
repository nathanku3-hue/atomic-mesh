#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for /draft-plan and /accept-plan backend integration.
.DESCRIPTION
    v20.0: Verifies elimination of silent failures:
    - /draft-plan calls Invoke-DraftPlan (not just toast)
    - /accept-plan calls Invoke-AcceptPlan (not local state mutation)
    - ForceDataRefresh is set on success
    - BLOCKED/ERROR statuses are surfaced in toasts
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

# Load the module
$moduleRoot = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI"
$modulePath = Join-Path $moduleRoot "AtomicMesh.UI.psm1"

if (-not (Test-Path $modulePath)) {
    Write-Host "FAIL: AtomicMesh.UI.psm1 not found at $modulePath" -ForegroundColor Red
    exit 1
}

try {
    Import-Module $modulePath -Force -ErrorAction Stop
} catch {
    Write-Host "FAIL: Could not import module: $_" -ForegroundColor Red
    exit 1
}

# Read the router source code for static analysis
$routerPath = Join-Path $moduleRoot "Public" "Invoke-CommandRouter.ps1"
$routerContent = Get-Content $routerPath -Raw

# Read the adapter source code
$adapterPath = Join-Path $moduleRoot "Private" "Adapters" "MeshServerAdapter.ps1"
if (-not (Test-Path $adapterPath)) {
    Fail "MeshServerAdapter.ps1 exists" "Adapter file not found"
} else {
    Pass "MeshServerAdapter.ps1 exists"
}

$adapterContent = Get-Content $adapterPath -Raw

# =============================================================================
# Test 1: /draft-plan calls Invoke-DraftPlan
# =============================================================================
if ($routerContent -match '"draft-plan"\s*\{[\s\S]*?Invoke-DraftPlan\s+-ProjectPath') {
    Pass "/draft-plan calls Invoke-DraftPlan"
} else {
    Fail "/draft-plan calls Invoke-DraftPlan" "Expected Invoke-DraftPlan call in draft-plan handler"
}

# =============================================================================
# Test 2: /accept-plan calls Invoke-AcceptPlan
# =============================================================================
if ($routerContent -match '"accept-plan"\s*\{[\s\S]*?Invoke-AcceptPlan\s+-ProjectPath') {
    Pass "/accept-plan calls Invoke-AcceptPlan"
} else {
    Fail "/accept-plan calls Invoke-AcceptPlan" "Expected Invoke-AcceptPlan call in accept-plan handler"
}

# =============================================================================
# Test 3: /draft-plan sets ForceDataRefresh on success
# =============================================================================
if ($routerContent -match '"draft-plan"\s*\{[\s\S]*?"OK"\s*\{[\s\S]*?ForceDataRefresh\s*=\s*\$true') {
    Pass "/draft-plan sets ForceDataRefresh on OK"
} else {
    Fail "/draft-plan sets ForceDataRefresh on OK" "Expected ForceDataRefresh = `$true in OK case"
}

# =============================================================================
# Test 4: /accept-plan sets ForceDataRefresh on success
# =============================================================================
if ($routerContent -match '"accept-plan"\s*\{[\s\S]*?"OK"\s*\{[\s\S]*?ForceDataRefresh\s*=\s*\$true') {
    Pass "/accept-plan sets ForceDataRefresh on OK"
} else {
    Fail "/accept-plan sets ForceDataRefresh on OK" "Expected ForceDataRefresh = `$true in OK case"
}

# =============================================================================
# Test 5: /accept-plan does NOT mutate PlanState.Accepted directly
# =============================================================================
if ($routerContent -notmatch '"accept-plan"\s*\{[\s\S]*?\$snapshotRef\.PlanState\.Accepted\s*=') {
    Pass "/accept-plan does not mutate PlanState.Accepted locally"
} else {
    Fail "/accept-plan local mutation removed" "Still mutates PlanState.Accepted directly"
}

# =============================================================================
# Test 6: /draft-plan handles BLOCKED status
# =============================================================================
if ($routerContent -match '"draft-plan"\s*\{[\s\S]*?"BLOCKED"\s*\{[\s\S]*?Toast\.Set') {
    Pass "/draft-plan shows toast on BLOCKED"
} else {
    Fail "/draft-plan shows toast on BLOCKED" "Expected Toast.Set in BLOCKED case"
}

# =============================================================================
# Test 7: /accept-plan handles BLOCKED status
# =============================================================================
if ($routerContent -match '"accept-plan"\s*\{[\s\S]*?"BLOCKED"\s*\{[\s\S]*?Toast\.Set') {
    Pass "/accept-plan shows toast on BLOCKED"
} else {
    Fail "/accept-plan shows toast on BLOCKED" "Expected Toast.Set in BLOCKED case"
}

# =============================================================================
# Test 8: Adapter has proper timeout handling
# =============================================================================
if ($adapterContent -match 'WaitForExit\(\$TimeoutMs\)' -and
    $adapterContent -match 'try\s*\{\s*\$proc\.Kill\(\)') {
    Pass "Adapter has timeout + kill logic"
} else {
    Fail "Adapter timeout handling" "Expected WaitForExit with timeout and Kill on timeout"
}

# =============================================================================
# Test 9: Adapter uses raw string for Windows paths
# =============================================================================
if ($adapterContent -match "r'\`$escapedPath'" -or $adapterContent -match "r'\`$moduleRoot'") {
    Pass "Adapter uses raw string r'...' for Windows paths"
} else {
    Fail "Adapter path escaping" "Expected raw string pattern for Windows paths"
}

# =============================================================================
# Test 10: Adapter suppresses Python logging
# =============================================================================
if ($adapterContent -match 'logging\.disable\(logging\.INFO\)') {
    Pass "Adapter suppresses Python INFO logging"
} else {
    Fail "Adapter logging suppression" "Expected logging.disable(logging.INFO)"
}

# =============================================================================
# Test 11: Get-LatestDraftPlan function exists
# =============================================================================
if ($adapterContent -match 'function\s+Get-LatestDraftPlan') {
    Pass "Get-LatestDraftPlan function exists"
} else {
    Fail "Get-LatestDraftPlan function" "Expected Get-LatestDraftPlan in adapter"
}

# =============================================================================
# Test 12: /accept-plan calls Get-LatestDraftPlan for default path
# =============================================================================
if ($routerContent -match '"accept-plan"\s*\{[\s\S]*?Get-LatestDraftPlan\s+-ProjectPath') {
    Pass "/accept-plan uses Get-LatestDraftPlan for default path"
} else {
    Fail "/accept-plan uses Get-LatestDraftPlan" "Expected Get-LatestDraftPlan call"
}

# =============================================================================
# Test 13: Adapter returns structured result (never throws)
# =============================================================================
if ($adapterContent -match '\$result\s*=\s*@\{' -and
    $adapterContent -match 'Ok\s*=\s*\$false' -and
    $adapterContent -match 'return\s+\$result') {
    Pass "Adapter returns structured result (never throws)"
} else {
    Fail "Adapter structured result" "Expected @{ Ok=...; Status=...; } return pattern"
}

# =============================================================================
# Test 14: v20.0 comment present (migration marker)
# =============================================================================
if ($routerContent -match 'v20\.0.*Real backend call') {
    Pass "v20.0 migration marker present"
} else {
    Fail "v20.0 migration marker" "Expected v20.0 comment indicating real backend call"
}

# =============================================================================
# Functional Test: Verify functions are callable
# =============================================================================
Write-Host ""
Write-Host "=== Functional Tests ===" -ForegroundColor Cyan

# Dot-source adapter directly for testing (Private functions not exported)
. $adapterPath

# Test Get-LatestDraftPlan with non-existent path
try {
    $testPath = Join-Path $env:TEMP "nonexistent_mesh_test_$(Get-Random)"
    $result = Get-LatestDraftPlan -ProjectPath $testPath
    if ($null -eq $result) {
        Pass "Get-LatestDraftPlan returns null for missing dir"
    } else {
        Fail "Get-LatestDraftPlan null return" "Expected null for non-existent directory"
    }
} catch {
    Fail "Get-LatestDraftPlan callable" "Function threw: $_"
}

# Test Invoke-DraftPlan structure (will fail on backend but should return structured result)
try {
    $testPath = Join-Path $env:TEMP "mesh_test_$(Get-Random)"
    New-Item -ItemType Directory -Path $testPath -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testPath "docs\PLANS") -Force | Out-Null

    $result = Invoke-DraftPlan -ProjectPath $testPath -TimeoutMs 500
    if ($result.ContainsKey("Ok") -and $result.ContainsKey("Status") -and $result.ContainsKey("Message")) {
        Pass "Invoke-DraftPlan returns structured result"
    } else {
        Fail "Invoke-DraftPlan structure" "Expected Ok, Status, Message keys"
    }

    Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Fail "Invoke-DraftPlan callable" "Function threw: $_"
}

# Test Invoke-AcceptPlan with non-existent file
try {
    $testPath = Join-Path $env:TEMP "mesh_test_$(Get-Random)"
    New-Item -ItemType Directory -Path $testPath -Force | Out-Null

    $result = Invoke-AcceptPlan -ProjectPath $testPath -PlanPath "nonexistent.md" -TimeoutMs 500
    if ($result.Ok -eq $false -and $result.Message -match "not found") {
        Pass "Invoke-AcceptPlan returns error for missing file"
    } else {
        Fail "Invoke-AcceptPlan file check" "Expected Ok=false with 'not found' message"
    }

    Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Fail "Invoke-AcceptPlan callable" "Function threw: $_"
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
