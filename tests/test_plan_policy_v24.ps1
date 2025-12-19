# Test: v24.0 PLAN Policy Implementation
#
# Verifies PLAN_POLICY_SPEC.md compliance:
# 1. Next: exact strings with parentheticals
# 2. No status words (RUNNING/OK/BLOCKED) in PLAN lane rows
# 3. Drift detection and warning
# 4. Health dots present on lane rows
#
# Run: pwsh tests/test_plan_policy_v24.ps1

param([switch]$Verbose)

$ErrorActionPreference = "Stop"
$testsPassed = 0
$testsFailed = 0

function Write-TestResult($name, $passed, $detail = "") {
    if ($passed) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
        $script:testsPassed++
    } else {
        Write-Host "  [FAIL] $name" -ForegroundColor Red
        if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
        $script:testsFailed++
    }
}

Write-Host "`n=== v24.0 PLAN Policy Tests ===" -ForegroundColor Cyan

# Setup: Get paths and load control_panel
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"
$cpContent = Get-Content $cpPath -Raw

# ============================================================================
# TEST 1: Next: Exact Strings with Parentheticals (Spec Section 3)
# ============================================================================
Write-Host "`n--- Test 1: Next: Exact Strings with Parentheticals ---" -ForegroundColor Yellow

# Test 1a: State 1 - No draft exists
$hasNoDraftString = $cpContent -match '/draft-plan \(creates plan file\)'
Write-TestResult "Next: /draft-plan (creates plan file)" $hasNoDraftString

# Test 1b: State 2 - Draft exists, DB has no tasks
$hasAcceptString = $cpContent -match '/accept-plan \(loads tasks into DB\)'
Write-TestResult "Next: /accept-plan (loads tasks into DB)" $hasAcceptString

# Test 1c: State 3 - Ready to go (no drift)
$hasGoString = $cpContent -match '/go \(pick next task\)'
Write-TestResult "Next: /go (pick next task)" $hasGoString

# Test 1d: State 4 - Drift detected
$hasDriftGoString = $cpContent -match '/go \(using accepted plan\)'
Write-TestResult "Next: /go (using accepted plan) for drift state" $hasDriftGoString

# ============================================================================
# TEST 2: Drift Warning (Spec Section 3.1)
# ============================================================================
Write-Host "`n--- Test 2: Drift Warning ---" -ForegroundColor Yellow

# Test 2a: Drift warning exact text
$hasDriftWarning = $cpContent -match 'Draft changed.*accept-plan to load new tasks'
Write-TestResult "Drift warning text present" $hasDriftWarning

# Test 2b: Drift warning is yellow
$driftYellowColor = $cpContent -match 'if \(\$driftWarning\).*"Yellow"'
Write-TestResult "Drift warning colored yellow" $driftYellowColor

# Test 2c: Get-PlanDriftStatus function exists
$hasDriftFunc = $cpContent -match 'function Get-PlanDriftStatus'
Write-TestResult "Get-PlanDriftStatus function exists" $hasDriftFunc

# Test 2d: Drift detection compares source_plan_hash
$comparesHash = $cpContent -match 'source_plan_hash.*FROM tasks'
Write-TestResult "Drift compares source_plan_hash from DB" $comparesHash

# Test 2e: Drift cache exists for efficiency
$hasDriftCache = $cpContent -match '\$Global:DriftCache'
Write-TestResult "Drift cache for efficiency" $hasDriftCache

# ============================================================================
# TEST 3: No Status Words in PLAN Lane Rows (Spec Section 4.1)
# ============================================================================
Write-Host "`n--- Test 3: No Status Words in PLAN Lane Rows ---" -ForegroundColor Yellow

# Extract Draw-PlanScreen function
$planScreenPattern = '(?ms)function Draw-PlanScreen\s*\{.*?^# --- v21'
$planScreenMatch = [regex]::Match($cpContent, $planScreenPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
$planScreenBody = $planScreenMatch.Value

# Test 3a: No State.PadRight(8) in PLAN lane rendering
$noStatePadRight = -not ($planScreenBody -match 'Write-Host.*\$.*Status\.State\.PadRight\(8\)')
Write-TestResult "No State.PadRight(8) in PLAN lanes" $noStatePadRight

# Test 3b: v24.0 comment for color-only lanes
$hasV24ColorOnly = $planScreenBody -match 'v24\.0.*[Cc]olor-only'
Write-TestResult "v24.0 color-only comment present" $hasV24ColorOnly

# Test 3c: Reason displayed (tokens for work lanes)
$hasReasonDisplay = $planScreenBody -match 'Write-Host \$reason\.PadRight'
Write-TestResult "Reason (tokens) displayed" $hasReasonDisplay

# ============================================================================
# TEST 4: Health Dot on Lane Rows (Spec Section 5)
# ============================================================================
Write-Host "`n--- Test 4: Health Dot on Lane Rows ---" -ForegroundColor Yellow

# Test 4a: Health dot character output
$hasDotOutput = $planScreenBody -match 'Write-Host "●"'
Write-TestResult "Health dot character output" $hasDotOutput

# Test 4b: Dot color switch statement
$hasDotColorSwitch = $planScreenBody -match '\$dotColor = switch'
Write-TestResult "Dot color determined by switch" $hasDotColorSwitch

# Test 4c: Green for healthy
$hasGreenDot = $planScreenBody -match '"Green"\s*\{\s*"Green"\s*\}'
Write-TestResult "Green dot for healthy status" $hasGreenDot

# Test 4d: Red for blocked/failed
$hasRedDot = $planScreenBody -match '"Red"\s*\{\s*"Red"\s*\}'
Write-TestResult "Red dot for blocked/failed status" $hasRedDot

# Test 4e: Yellow for unknown accounting (D:—)
$hasYellowDash = $planScreenBody -match 'D:—.*Yellow'
Write-TestResult "Yellow dot for unknown accounting (D:—)" $hasYellowDash

# ============================================================================
# TEST 5: Work Lane Token Format (Spec Section 4.2)
# ============================================================================
Write-Host "`n--- Test 5: Work Lane Token Format ---" -ForegroundColor Yellow

# Test 5a: A: counter present
$hasACounter = $cpContent -match '"A:\$la'
Write-TestResult "A:<active> counter format" $hasACounter

# Test 5b: D:n/n format
$hasDCounter = $cpContent -match 'D:\$\(.*done.*\)/\$\(.*total.*\)'
Write-TestResult "D:<done>/<total> format" $hasDCounter

# Test 5c: D:— for unknown
$hasDDash = $cpContent -match '"D:—"'
Write-TestResult "D:— for unknown accounting" $hasDDash

# ============================================================================
# TEST 6: State Variables Still Set (for internal logic)
# ============================================================================
Write-Host "`n--- Test 6: State Variables Still Set Internally ---" -ForegroundColor Yellow

# States should still be set even if not displayed
$hasRunningState = $cpContent -match '\$state\s*=\s*"RUNNING"'
Write-TestResult "RUNNING state set internally" $hasRunningState

$hasPendingState = $cpContent -match '\$state\s*=\s*"PENDING"'
Write-TestResult "PENDING state set internally" $hasPendingState

$hasIdleState = $cpContent -match '\$state\s*=\s*"IDLE"'
Write-TestResult "IDLE state set internally" $hasIdleState

$hasOkState = $cpContent -match '\$state\s*=\s*"OK"'
Write-TestResult "OK state set internally" $hasOkState

# ============================================================================
# TEST 7: Next Logic State Machine (Spec Section 2)
# ============================================================================
Write-Host "`n--- Test 7: Next Logic State Machine ---" -ForegroundColor Yellow

# Test 7a: Check for has_draft condition
$hasHasDraftCheck = $cpContent -match '-not \$hasDraft\)'
Write-TestResult "State 1: No draft -> /draft-plan" $hasHasDraftCheck

# Test 7b: Check for totalTasks == 0 condition
$hasNoTasksCheck = $cpContent -match '\$totalTasks -eq 0'
Write-TestResult "State 2: No tasks -> /accept-plan" $hasNoTasksCheck

# Test 7c: Check for drift detection in go logic
$hasDriftCheck = $cpContent -match '\$driftStatus\.drifted'
Write-TestResult "State 4: Drift detected triggers different message" $hasDriftCheck

# ============================================================================
# TEST 8: Audit Lane Format (Spec Section 4.3)
# ============================================================================
Write-Host "`n--- Test 8: Audit Lane Format ---" -ForegroundColor Yellow

# Audit lanes should not have A:/D: tokens
$auditLanes = @("QA/AUDIT", "LIBRARIAN")
foreach ($lane in $auditLanes) {
    # Look for audit lane reason that doesn't have A: or D: format
    # These should have summary text like "clean", "All verified", etc.
}

# Test 8a: QA lane has descriptive summary
$qaClean = $cpContent -match '\$qaReason\s*=\s*"clean"'
Write-TestResult "QA has 'clean' summary option" $qaClean

# Test 8b: LIBRARIAN has clean summary (in Reason field)
$libClean = $cpContent -match 'Reason\s*=\s*"clean"'
Write-TestResult "LIBRARIAN has 'clean' summary option" $libClean

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

if ($testsFailed -gt 0) {
    Write-Host "`nFailed tests indicate PLAN_POLICY_SPEC.md compliance issues." -ForegroundColor Yellow
    Write-Host "See docs/PLAN_POLICY_SPEC.md for expected behavior." -ForegroundColor DarkGray
}

exit $testsFailed
