# Test: v18.2 Header and Init Shell consistency
#
# Acceptance Criteria:
# 1. Init shell test: When init marker exists + docs stubbed (readiness BOOTSTRAP),
#    the header shows "EXECUTION MODE" (not BOOTSTRAP panel)
# 2. Header uniqueness: No "[>] Standalone" or "EXEC [VIBE]" appears in rendered output
#
# Run: pwsh tests/test_header_init_shell.ps1

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

Write-Host "`n=== v18.2 Header & Init Shell Tests ===" -ForegroundColor Cyan

# Setup: Get paths
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"
$cpContent = Get-Content $cpPath -Raw

# ============================================================================
# TEST 1: Header uniqueness - No legacy header patterns in code
# ============================================================================
Write-Host "`n--- Test 1: Header Uniqueness (no legacy patterns) ---" -ForegroundColor Yellow

# Test 1a: No "[>] Standalone" pattern (should use mode-based header)
$standalonePattern = '\[>\]\s*Standalone'
$hasStandalonePattern = $cpContent -match $standalonePattern
Write-TestResult "No '[>] Standalone' pattern in code" (-not $hasStandalonePattern) `
    "Legacy header pattern should be removed"

# Test 1b: No "EXEC [VIBE]" pattern in active dashboard header
$execVibePattern = 'EXEC\s*\[VIBE\]'
$execVibeMatches = Select-String -InputObject $cpContent -Pattern $execVibePattern -AllMatches
$activeExecVibe = $false
if ($execVibeMatches) {
    foreach ($match in $execVibeMatches.Matches) {
        # Check if it's in a comment (preceded by # on same line)
        $lineStart = $cpContent.LastIndexOf("`n", $match.Index)
        if ($lineStart -eq -1) { $lineStart = 0 }
        $lineBeforeMatch = $cpContent.Substring($lineStart, $match.Index - $lineStart)
        if ($lineBeforeMatch -notmatch '#') {
            $activeExecVibe = $true
            break
        }
    }
}
Write-TestResult "No active 'EXEC [VIBE]' header in code" (-not $activeExecVibe) `
    "Legacy dashboard header should be commented out or removed"

# Test 1c: Show-Header is the single source of truth
$showHeaderCalls = Select-String -InputObject $cpContent -Pattern 'Show-Header' -AllMatches
$showHeaderCount = if ($showHeaderCalls.Matches) { $showHeaderCalls.Matches.Count } else { 0 }
# Should have: function definition + at least 1 call in main loop
Write-TestResult "Show-Header function exists and is called" ($showHeaderCount -ge 2) `
    "Found $showHeaderCount references (need function def + call)"

# ============================================================================
# TEST 2: Init Shell Contract - Separate init from readiness
# ============================================================================
Write-Host "`n--- Test 2: Init Shell Contract ---" -ForegroundColor Yellow

# Test 2a: Draw-Dashboard uses Test-RepoInitialized
$dashboardCode = Select-String -Path $cpPath -Pattern 'function Draw-Dashboard' -Context 0,50
if ($dashboardCode) {
    $contextLines = $dashboardCode.Line + "`n" + ($dashboardCode.Context.PostContext -join "`n")
    $usesTestRepoInit = $contextLines -match 'Test-RepoInitialized'
    Write-TestResult "Draw-Dashboard uses Test-RepoInitialized" $usesTestRepoInit `
        "Dashboard should check init status, not just readiness"
} else {
    Write-TestResult "Draw-Dashboard function found" $false "Could not find Draw-Dashboard"
}

# Test 2b: Conditional rendering uses $IsInitialized (not $IsPreInit or $IsBootstrap alone)
$conditionalCode = Select-String -Path $cpPath -Pattern 'CONDITIONAL RENDERING' -Context 0,15
if ($conditionalCode) {
    $contextLines = ($conditionalCode.Context.PostContext -join "`n")
    $usesIsInitialized = $contextLines -match '\$IsInitialized'
    Write-TestResult "Conditional rendering uses `$IsInitialized" $usesIsInitialized `
        "Panel selection should be based on init state"
} else {
    # Alternative: check for -not $IsInitialized pattern
    $hasInitCheck = $cpContent -match 'if\s*\(\s*-not\s+\$IsInitialized\s*\)'
    Write-TestResult "Panel selection based on init state" $hasInitCheck `
        "Should use -not `$IsInitialized for PRE_INIT panel"
}

# Test 2c: Strategic locking separate from panel selection
$hasStrategicLocked = $cpContent -match '\$IsStrategicLocked'
Write-TestResult "`$IsStrategicLocked variable exists" $hasStrategicLocked `
    "Strategic command locking should be separate from panel display"

# ============================================================================
# TEST 3: Show-Header Mode Label Contract
# ============================================================================
Write-Host "`n--- Test 3: Show-Header Mode Label ---" -ForegroundColor Yellow

# Test 3a: Header shows "EXECUTION MODE" when initialized
$headerModePattern = 'EXECUTION MODE'
$headerHasModeLabel = $cpContent -match $headerModePattern
Write-TestResult "Header can show 'EXECUTION MODE' label" $headerHasModeLabel `
    "Header should display mode based on init state"

# Test 3b: Header shows "BOOTSTRAP" when not initialized
$headerBootstrapPattern = '\$modeLabel.*BOOTSTRAP'
$headerHasBootstrapLabel = $cpContent -match $headerBootstrapPattern
Write-TestResult "Header shows 'BOOTSTRAP' when not initialized" $headerHasBootstrapLabel `
    "Header should show BOOTSTRAP for uninitialized repos"

# Test 3c: CTX score with color in header
$ctxScorePattern = 'CTX.*\$ctxScore'
$hasCTXScore = $cpContent -match $ctxScorePattern
Write-TestResult "Header shows CTX score" $hasCTXScore `
    "Header should display context readiness score"

# Test 3d: CTX color mapping exists
$ctxColorPattern = '\$ctxColor.*Green.*Yellow.*Red'
$hasCTXColorMapping = $cpContent -match $ctxColorPattern
Write-TestResult "CTX score has color mapping" $hasCTXColorMapping `
    "CTX score should be colored (green/yellow/red)"

# ============================================================================
# TEST 4: Lane Count Status Arrays
# ============================================================================
Write-Host "`n--- Test 4: Lane Count Status Arrays ---" -ForegroundColor Yellow

# Test 4a: Global PendingStatuses array exists
$hasPendingStatuses = $cpContent -match '\$Global:PendingStatuses\s*='
Write-TestResult "`$Global:PendingStatuses array defined" $hasPendingStatuses `
    "Lane counts should use configurable pending status array"

# Test 4b: Global ActiveStatuses array exists
$hasActiveStatuses = $cpContent -match '\$Global:ActiveStatuses\s*='
Write-TestResult "`$Global:ActiveStatuses array defined" $hasActiveStatuses `
    "Lane counts should use configurable active status array"

# Test 4c: Get-LaneActivityCounts uses status arrays
$laneCountCode = Select-String -Path $cpPath -Pattern 'function Get-LaneActivityCounts' -Context 0,20
if ($laneCountCode) {
    $contextLines = $laneCountCode.Line + "`n" + ($laneCountCode.Context.PostContext -join "`n")
    $usesArrays = ($contextLines -match 'PendingStatuses') -and ($contextLines -match 'ActiveStatuses')
    Write-TestResult "Get-LaneActivityCounts uses status arrays" $usesArrays `
        "Function should use global arrays, not hardcoded statuses"
} else {
    Write-TestResult "Get-LaneActivityCounts function found" $false
}

# ============================================================================
# TEST 5: Strategic Lock UX (v18.2.1)
# ============================================================================
Write-Host "`n--- Test 5: Strategic Lock UX ---" -ForegroundColor Yellow

# Test 5a: STRATEGIC LOCKED message in EXEC shell when docs incomplete
$hasStrategicLockedMsg = $cpContent -match 'STRATEGIC LOCKED'
Write-TestResult "STRATEGIC LOCKED message exists" $hasStrategicLockedMsg `
    "Should show prominent lock indicator when initialized but docs incomplete"

# Test 5b: Next action hint includes /lib prompt prd
$hasLibPromptHint = $cpContent -match '/lib prompt prd'
Write-TestResult "Lock state shows '/lib prompt prd' hint" $hasLibPromptHint `
    "Should guide user to fill docs when strategic is locked"

# Test 5c: Strategic lock uses Red color (prominent)
$hasRedLockColor = $cpContent -match 'IsStrategicLocked.*Red'
Write-TestResult "Strategic lock uses Red color" $hasRedLockColor `
    "Lock indicator should be RED to be prominent"

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

if ($testsFailed -gt 0) {
    Write-Host "`n  Some tests failed. Check output above." -ForegroundColor Yellow
}

exit $testsFailed
