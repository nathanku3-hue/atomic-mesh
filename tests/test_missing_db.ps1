#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression test for missing database scenario.
.DESCRIPTION
    Verifies that when ProjectPath has no tasks.db:
    - No exception is thrown
    - Snapshot fields have defaults
    - ReadinessMode = "no-db"
    - DbPresent = false
    - UI shows "tasks.db not found" message
.NOTES
    Run: pwsh tests/test_missing_db.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Missing Database Regression Test ===" -ForegroundColor Cyan
Write-Host ""

# Setup: use a temp directory with no database
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Write-Host "Test dir: $tempDir" -ForegroundColor Gray

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
. ./src/AtomicMesh.UI/Private/Render/Console.ps1
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
. ./src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1

# ============================================================================
# Test 1: Get-RealSnapshot does not throw for missing DB
# ============================================================================
Write-Host ""
Write-Host "Test 1: Get-RealSnapshot does not throw for missing DB" -ForegroundColor Cyan

try {
    $raw = Get-RealSnapshot -RepoRoot $tempDir
    if ($raw) {
        Test-Pass "No exception thrown"
    } else {
        Test-Fail "No exception thrown" "Result was null"
    }
} catch {
    Test-Fail "No exception thrown" $_.Exception.Message
}

# ============================================================================
# Test 2: ReadinessMode = "no-db"
# ============================================================================
Write-Host ""
Write-Host "Test 2: ReadinessMode = 'no-db'" -ForegroundColor Cyan

if ($raw.ReadinessMode -eq "no-db") {
    Test-Pass "ReadinessMode = 'no-db'"
} else {
    Test-Fail "ReadinessMode = 'no-db'" "Got: '$($raw.ReadinessMode)'"
}

# ============================================================================
# Test 3: DbPresent = false
# ============================================================================
Write-Host ""
Write-Host "Test 3: DbPresent = false" -ForegroundColor Cyan

if ($raw.DbPresent -eq $false) {
    Test-Pass "DbPresent = false"
} else {
    Test-Fail "DbPresent = false" "Got: '$($raw.DbPresent)'"
}

# ============================================================================
# Test 4: LaneCounts is empty array
# ============================================================================
Write-Host ""
Write-Host "Test 4: LaneCounts is empty" -ForegroundColor Cyan

if ($raw.LaneCounts.Count -eq 0) {
    Test-Pass "LaneCounts is empty"
} else {
    Test-Fail "LaneCounts is empty" "Got: $($raw.LaneCounts.Count) items"
}

# ============================================================================
# Test 5: DocScores has default values
# ============================================================================
Write-Host ""
Write-Host "Test 5: DocScores has defaults" -ForegroundColor Cyan

$prdScore = $raw.DocScores.PRD.score
$prdExists = $raw.DocScores.PRD.exists
if ($prdScore -eq 0 -and $prdExists -eq $false) {
    Test-Pass "DocScores has defaults (PRD score=0, exists=false)"
} else {
    Test-Fail "DocScores has defaults" "Got: score=$prdScore, exists=$prdExists"
}

# ============================================================================
# Test 6: Convert-RawSnapshotToUi works with no-db snapshot
# ============================================================================
Write-Host ""
Write-Host "Test 6: Convert-RawSnapshotToUi handles no-db" -ForegroundColor Cyan

try {
    $snapshot = Convert-RawSnapshotToUi -Raw $raw
    if ($snapshot) {
        Test-Pass "Convert-RawSnapshotToUi succeeds"
    } else {
        Test-Fail "Convert-RawSnapshotToUi succeeds" "Result was null"
    }
} catch {
    Test-Fail "Convert-RawSnapshotToUi succeeds" $_.Exception.Message
}

# ============================================================================
# Test 7: UI shows "tasks.db not found" for no-db mode
# ============================================================================
Write-Host ""
Write-Host "Test 7: UI shows 'tasks.db not found' message" -ForegroundColor Cyan

try {
    # Set ReadinessMode on snapshot for reducer
    $snapshot.ReadinessMode = "no-db"
    $directives = Get-DocsRightColumn -Snapshot $snapshot

    $foundMessage = $false
    foreach ($d in $directives) {
        if ($d.Text -match "tasks\.db not found") {
            $foundMessage = $true
            break
        }
    }

    if ($foundMessage) {
        Test-Pass "UI shows 'tasks.db not found'"
    } else {
        $texts = ($directives | ForEach-Object { $_.Text }) -join ", "
        Test-Fail "UI shows 'tasks.db not found'" "Directives: $texts"
    }
} catch {
    Test-Fail "UI shows 'tasks.db not found'" $_.Exception.Message
}

# ============================================================================
# Test 8: Next hint is /init for no-db mode
# ============================================================================
Write-Host ""
Write-Host "Test 8: Next hint is /init for no-db mode" -ForegroundColor Cyan

try {
    $lastDirective = $directives[-1]
    if ($lastDirective.Text -match "/init") {
        Test-Pass "Next hint is /init"
    } else {
        Test-Fail "Next hint is /init" "Got: '$($lastDirective.Text)'"
    }
} catch {
    Test-Fail "Next hint is /init" $_.Exception.Message
}

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

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
