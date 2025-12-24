#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression test for ForceDataRefresh flag behavior.
.DESCRIPTION
    Verifies that:
    1. ForceDataRefresh bypasses interval check
    2. Flag is cleared after tick (even on error)
    3. Without flag, interval check blocks refresh
.NOTES
    Run: pwsh tests/test_force_refresh.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== ForceDataRefresh Regression Test ===" -ForegroundColor Cyan
Write-Host ""

$moduleRoot = Join-Path $PSScriptRoot ".."
Set-Location $moduleRoot

$testsPassed = 0
$testsFailed = 0

function Test-Pass($name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
    $script:testsPassed++
}

function Test-Fail($name, $reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

# Load required files
. ./src/AtomicMesh.UI/Private/Models/PlanState.ps1
. ./src/AtomicMesh.UI/Private/Models/LaneMetrics.ps1
. ./src/AtomicMesh.UI/Private/Models/SchedulerDecision.ps1
. ./src/AtomicMesh.UI/Private/Models/UiAlerts.ps1
. ./src/AtomicMesh.UI/Private/Models/UiSnapshot.ps1
. ./src/AtomicMesh.UI/Private/Models/UiToast.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEvent.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEventLog.ps1
. ./src/AtomicMesh.UI/Private/Models/UiCache.ps1
. ./src/AtomicMesh.UI/Private/Models/UiState.ps1
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
. ./src/AtomicMesh.UI/Public/Start-ControlPanel.ps1

# ============================================================================
# Test 1: ForceDataRefresh defaults to false
# ============================================================================
Write-Host ""
Write-Host "Test 1: ForceDataRefresh defaults to false" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    if ($state.ForceDataRefresh -eq $false) {
        Test-Pass "ForceDataRefresh defaults to false"
    } else {
        Test-Fail "ForceDataRefresh defaults to false" "Got: $($state.ForceDataRefresh)"
    }
} catch {
    Test-Fail "ForceDataRefresh defaults to false" $_.Exception.Message
}

# ============================================================================
# Test 2: Without ForceDataRefresh, interval blocks refresh
# ============================================================================
Write-Host ""
Write-Host "Test 2: Interval blocks refresh when ForceDataRefresh=false" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    $state.AutoRefreshEnabled = $true
    $state.LastDataRefreshUtc = [datetime]::UtcNow  # Just refreshed
    $state.Cache.LastSnapshot = [UiSnapshot]::new()
    $state.Cache.LastSnapshot.ReadinessMode = "stale-test"

    $callCount = 0
    $mockLoader = {
        param($root)
        $script:callCount++
        return @{ ReadinessMode = "fresh-test"; LaneCounts = @() }
    }

    # Call with short interval - should NOT refresh (just refreshed)
    $result = Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "."

    if ($callCount -eq 0 -and $result.ReadinessMode -eq "stale-test") {
        Test-Pass "Interval blocks refresh when not due"
    } else {
        Test-Fail "Interval blocks refresh when not due" "callCount=$callCount, mode=$($result.ReadinessMode)"
    }
} catch {
    Test-Fail "Interval blocks refresh" $_.Exception.Message
}

# ============================================================================
# Test 3: ForceDataRefresh=true bypasses interval check
# ============================================================================
Write-Host ""
Write-Host "Test 3: ForceDataRefresh bypasses interval check" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    $state.AutoRefreshEnabled = $true
    $state.LastDataRefreshUtc = [datetime]::UtcNow  # Just refreshed
    $state.ForceDataRefresh = $true  # Force refresh
    $state.Cache.LastSnapshot = [UiSnapshot]::new()
    $state.Cache.LastSnapshot.ReadinessMode = "stale-test"

    $callCount = 0
    $mockLoader = {
        param($root)
        $script:callCount++
        return @{ ReadinessMode = "fresh-test"; LaneCounts = @() }
    }

    # Call with short interval - SHOULD refresh due to ForceDataRefresh
    $result = Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "."

    if ($callCount -eq 1) {
        Test-Pass "ForceDataRefresh bypasses interval check"
    } else {
        Test-Fail "ForceDataRefresh bypasses interval check" "callCount=$callCount (expected 1)"
    }
} catch {
    Test-Fail "ForceDataRefresh bypasses interval" $_.Exception.Message
}

# ============================================================================
# Test 4: ForceDataRefresh is cleared after tick (success case)
# ============================================================================
Write-Host ""
Write-Host "Test 4: ForceDataRefresh cleared after successful refresh" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    $state.AutoRefreshEnabled = $true
    $state.ForceDataRefresh = $true
    $state.Cache.LastSnapshot = [UiSnapshot]::new()

    $mockLoader = {
        param($root)
        return @{ ReadinessMode = "live"; LaneCounts = @() }
    }

    Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "." | Out-Null

    if ($state.ForceDataRefresh -eq $false) {
        Test-Pass "ForceDataRefresh cleared after successful refresh"
    } else {
        Test-Fail "ForceDataRefresh cleared after successful refresh" "Still true after tick"
    }
} catch {
    Test-Fail "ForceDataRefresh cleared on success" $_.Exception.Message
}

# ============================================================================
# Test 5: ForceDataRefresh is cleared after tick (error case)
# ============================================================================
Write-Host ""
Write-Host "Test 5: ForceDataRefresh cleared after failed refresh" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    $state.AutoRefreshEnabled = $true
    $state.ForceDataRefresh = $true
    $state.Cache.LastSnapshot = [UiSnapshot]::new()

    $mockLoader = {
        param($root)
        throw "Simulated backend error"
    }

    Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "." | Out-Null

    if ($state.ForceDataRefresh -eq $false) {
        Test-Pass "ForceDataRefresh cleared after failed refresh"
    } else {
        Test-Fail "ForceDataRefresh cleared after failed refresh" "Still true after error"
    }
} catch {
    # The function should catch errors internally, but check flag anyway
    if ($state.ForceDataRefresh -eq $false) {
        Test-Pass "ForceDataRefresh cleared after failed refresh"
    } else {
        Test-Fail "ForceDataRefresh cleared after failed refresh" "Still true: $_"
    }
}

# ============================================================================
# Test 6: Second tick after ForceDataRefresh respects interval again
# ============================================================================
Write-Host ""
Write-Host "Test 6: Second tick respects interval (no infinite refresh)" -ForegroundColor Cyan

try {
    $state = [UiState]::new()
    $state.AutoRefreshEnabled = $true
    $state.ForceDataRefresh = $true
    $state.Cache.LastSnapshot = [UiSnapshot]::new()

    $callCount = 0
    $mockLoader = {
        param($root)
        $script:callCount++
        return @{ ReadinessMode = "live"; LaneCounts = @() }
    }

    # First tick - should refresh (ForceDataRefresh=true)
    Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "." | Out-Null

    # Second tick immediately after - should NOT refresh (interval not due, flag cleared)
    Invoke-DataRefreshTick -State $state -DataIntervalMs 500 -NowUtc ([datetime]::UtcNow) -SnapshotLoader $mockLoader -RepoRoot "." | Out-Null

    if ($callCount -eq 1) {
        Test-Pass "Second tick respects interval (no hammer)"
    } else {
        Test-Fail "Second tick respects interval" "callCount=$callCount (expected 1)"
    }
} catch {
    Test-Fail "Second tick respects interval" $_.Exception.Message
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Tests passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })
Write-Host "============================================" -ForegroundColor Cyan

if ($testsFailed -gt 0) {
    exit 1
}
exit 0
