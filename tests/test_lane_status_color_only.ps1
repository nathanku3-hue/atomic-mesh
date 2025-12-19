# Test: v23.0 Lane Status Color-Only - No RUNNING/OK/BLOCKED Words
#
# Acceptance Criteria:
# 1. Lane rows do NOT contain RUNNING, OK, or BLOCKED status words
# 2. Work lanes (BACKEND/FRONTEND) show tokens: A:<active> D:<done>/<total>
# 3. Audit lanes (QA/LIBRARIAN) show blank token field, keep summary text
# 4. Health dot remains at right side (position-based)
# 5. Color-only semantics: bar color conveys status
#
# Run: pwsh tests/test_lane_status_color_only.ps1

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

Write-Host "`n=== v23.0 Lane Status Color-Only Tests ===" -ForegroundColor Cyan

# Setup: Get paths and load control_panel
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"
$cpContent = Get-Content $cpPath -Raw

# ============================================================================
# TEST 1: No Status Words in Draw-StreamLineLeft Output
# ============================================================================
Write-Host "`n--- Test 1: No Status Words in Lane Output ---" -ForegroundColor Yellow

# Test 1a: Draw-StreamLineLeft does NOT output $Status.State directly
$noStateOutput = -not ($cpContent -match 'Draw-StreamLineLeft[^}]*Write-Host \$Status\.State')
Write-TestResult "Draw-StreamLineLeft does NOT Write-Host `$Status.State" $noStateOutput

# Test 1b: No hardcoded RUNNING in Write-Host within Draw-StreamLineLeft
# Extract the function and check
$funcPattern = '(?ms)function Draw-StreamLineLeft\s*\{.*?^\s{8}\}'
$funcMatch = [regex]::Match($cpContent, $funcPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
$funcBody = $funcMatch.Value

$noRunningInFunc = -not ($funcBody -match 'Write-Host.*"RUNNING"')
Write-TestResult "No hardcoded 'RUNNING' in Write-Host calls" $noRunningInFunc

$noOkInFunc = -not ($funcBody -match 'Write-Host.*"OK"')
Write-TestResult "No hardcoded 'OK' in Write-Host calls" $noOkInFunc

# Test 1c: Regex strips status words from summary
$hasStatusWordStrip = $cpContent -match '\$summary = \$summary -replace "\^\(OK\|RUNNING\|BLOCKED\)'
Write-TestResult "Summary strips status words via regex" $hasStatusWordStrip

# ============================================================================
# TEST 2: Token Format for Work Lanes
# ============================================================================
Write-Host "`n--- Test 2: Token Format for Work Lanes ---" -ForegroundColor Yellow

# Test 2a: isWorkLane check exists
$hasWorkLaneCheck = $cpContent -match '\$isWorkLane\s*=\s*\$StreamName -in @\("BACKEND", "FRONTEND"\)'
Write-TestResult "isWorkLane check for BACKEND/FRONTEND" $hasWorkLaneCheck

# Test 2b: Token format A:n D:n/n
$hasTokenFormat = $cpContent -match '"A:\$active D:\$done/\$total"'
Write-TestResult "Token format A:`$active D:`$done/`$total" $hasTokenFormat

# Test 2c: D:— for unknown (total=0)
$hasDashForUnknown = $cpContent -match '"A:\$active D:\$\(\[char\]0x2014\)"'
Write-TestResult "D:(em-dash) when total unknown" $hasDashForUnknown

# Test 2d: Token field is 12 chars wide (padded)
$hasTokenPadding = $cpContent -match '\$tokenStr\.PadRight\(12\)'
Write-TestResult "Token field padded to 12 chars" $hasTokenPadding

# ============================================================================
# TEST 3: Audit Lanes (QA/LIBRARIAN) - Blank Token Field
# ============================================================================
Write-Host "`n--- Test 3: Audit Lanes Blank Token Field ---" -ForegroundColor Yellow

# Test 3a: Else branch writes 12 spaces for non-work lanes
$hasBlankToken = $cpContent -match 'Write-Host \(" " \* 12\) -NoNewline'
Write-TestResult "Non-work lanes write 12 spaces (blank token field)" $hasBlankToken

# Test 3b: Summary still displayed for audit lanes
$hasSummaryOutput = $cpContent -match 'Write-Host \$summary\.PadRight\(\$summaryMaxLen\)'
Write-TestResult "Summary still displayed" $hasSummaryOutput

# ============================================================================
# TEST 4: Layout Comment Updated
# ============================================================================
Write-Host "`n--- Test 4: Layout Comment Updated ---" -ForegroundColor Yellow

# Test 4a: v23.0 version in comment
$hasV23Comment = $cpContent -match '# v23\.0.*color-only status'
Write-TestResult "v23.0 version comment present" $hasV23Comment

# Test 4b: Layout shows tokens:12 instead of state:8
$hasTokensLayout = $cpContent -match '<tokens:12>'
Write-TestResult "Layout comment shows tokens:12 field" $hasTokensLayout

# Test 4c: summaryMaxLen calculation updated
$hasSummaryMaxLen = $cpContent -match '\$summaryMaxLen = \$ContentWidth - 10 - 6 - 12 - 2 - 2'
Write-TestResult "summaryMaxLen accounts for 12-char token field" $hasSummaryMaxLen

# ============================================================================
# TEST 5: Health Dot Still Position-Based
# ============================================================================
Write-Host "`n--- Test 5: Health Dot Position ---" -ForegroundColor Yellow

# Test 5a: dotX still calculated
$hasDotX = $cpContent -match '\$dotX\s*=\s*\$Half\s*-\s*2'
Write-TestResult "dotX still calculated as `$Half - 2" $hasDotX

# Test 5b: Set-Pos used for dot placement (uses $R in lane loop, not $Row)
$hasSetPosForDot = $cpContent -match 'Set-Pos \$R \$dotX'
Write-TestResult "Set-Pos used for dot placement" $hasSetPosForDot

# ============================================================================
# TEST 6: laneProgress Retrieved Early
# ============================================================================
Write-Host "`n--- Test 6: laneProgress Retrieved Early ---" -ForegroundColor Yellow

# Test 6a: laneProgress is retrieved before token output
# Check that Get-LaneProgress is called BEFORE the isWorkLane check
$funcLines = $funcBody -split "`n"
$laneProgressLine = -1
$isWorkLaneLine = -1
for ($i = 0; $i -lt $funcLines.Count; $i++) {
    if ($funcLines[$i] -match 'Get-LaneProgress') { $laneProgressLine = $i }
    if ($funcLines[$i] -match '\$isWorkLane\s*=') { $isWorkLaneLine = $i }
}
$laneProgressFirst = ($laneProgressLine -gt 0 -and $isWorkLaneLine -gt 0 -and $laneProgressLine -lt $isWorkLaneLine)
Write-TestResult "laneProgress retrieved before token output" $laneProgressFirst

# ============================================================================
# TEST 7: Regression - State Values Still Set Internally
# ============================================================================
Write-Host "`n--- Test 7: State Values Still Set Internally ---" -ForegroundColor Yellow

# The Get-StreamStatusLine function should still SET State values for internal use
# (even though they're no longer printed)
$hasRunningState = $cpContent -match '\$result\.State\s*=\s*"RUNNING"'
Write-TestResult "RUNNING state still set internally" $hasRunningState

$hasOkState = $cpContent -match '\$result\.State\s*=\s*"OK"'
Write-TestResult "OK state still set internally" $hasOkState

$hasBlockedState = $cpContent -match '\$result\.State\s*=\s*"BLOCKED"'
Write-TestResult "BLOCKED state still set internally" $hasBlockedState

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

exit $testsFailed
