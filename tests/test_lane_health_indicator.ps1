# Test: v21.4 Lane Health Indicator - Dot Position & D:0/0 Prevention
#
# Acceptance Criteria:
# 1. Lane dot (●) rendered at fixed column ($Half - 2), not string-appended
# 2. Health×confidence rule: RED (blocked), YELLOW (unknown), GREEN (healthy)
# 3. D:0/0 never shown when active/pending > 0 - show D:— instead
#
# Run: pwsh tests/test_lane_health_indicator.ps1

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

Write-Host "`n=== v21.4 Lane Health Indicator Tests ===" -ForegroundColor Cyan

# Setup: Get paths and load control_panel
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"
$cpContent = Get-Content $cpPath -Raw

# ============================================================================
# TEST 1: Dot rendering is position-based (not string-append)
# ============================================================================
Write-Host "`n--- Test 1: Position-Based Dot Rendering ---" -ForegroundColor Yellow

# Test 1a: Uses Set-Pos for dot placement (v24.0: now uses $R in lane loop)
$hasSetPosForDot = $cpContent -match 'Set-Pos \$R \$dotX'
Write-TestResult "Uses Set-Pos for dot placement" $hasSetPosForDot

# Test 1b: dotX calculated from $Half - 2
$hasDotXCalculation = $cpContent -match '\$dotX\s*=\s*\$Half\s*-\s*2'
Write-TestResult "dotX calculated as `$Half - 2" $hasDotXCalculation

# Test 1c: Dot character is ● (BLACK CIRCLE U+25CF)
$hasDotChar = $cpContent -match '\[char\]0x25CF' -or $cpContent -match '●'
Write-TestResult "Uses ● (BLACK CIRCLE) for dot" $hasDotChar

# Test 1d: Dot NOT appended to summary string
$notAppendedToSummary = -not ($cpContent -match 'Write-Host.*summary.*\$\(.*Dot\)')
Write-TestResult "Dot NOT appended to summary string" $notAppendedToSummary

# ============================================================================
# TEST 2: Health×Confidence Collapse Rule
# ============================================================================
Write-Host "`n--- Test 2: Health×Confidence Rule ---" -ForegroundColor Yellow

# Test 2a: Get-LaneHealthIndicator accepts Done, Total, Active, Blocked params
$hasHealthParams = $cpContent -match 'function Get-LaneHealthIndicator\s*\{[^}]*\[int\]\$Done' -or
                   $cpContent -match 'Get-LaneHealthIndicator.*-Done.*-Total.*-Active.*-Blocked'
Write-TestResult "Get-LaneHealthIndicator accepts progress params" $hasHealthParams

# Test 2b: RED condition includes blocked > 0
$hasRedForBlocked = $cpContent -match '\$Blocked -gt 0' -and $cpContent -match 'Color = "Red"'
Write-TestResult "RED when blocked > 0" $hasRedForBlocked

# Test 2c: YELLOW for unknown accounting (total==0 with ANY activity)
$hasYellowUnknown = $cpContent -match '\$Total -eq 0 -and \(\$Active -gt 0 -or \$Status\.State -eq "RUNNING"\)'
Write-TestResult "YELLOW when total==0 and (active>0 OR RUNNING)" $hasYellowUnknown

# Test 2d: GREEN when done/total >= 0.7 and no blockers
$hasGreenHighConfidence = $cpContent -match '\$ratio -ge 0\.7' -and $cpContent -match '\$Blocked -eq 0'
Write-TestResult "GREEN when ratio >= 0.7 and no blockers" $hasGreenHighConfidence

# ============================================================================
# TEST 3: D:0/0 Prevention Logic
# ============================================================================
Write-Host "`n--- Test 3: D:0/0 Prevention ---" -ForegroundColor Yellow

# Test 3a: D:— token exists for unknown accounting
$hasDashToken = $cpContent -match '"D:—"' -or $cpContent -match 'D:—'
Write-TestResult "D:— token for unknown accounting" $hasDashToken

# Test 3b: Logic prevents D:0/0 when active/pending exists
$hasPreventionLogic = $cpContent -match '\$laneProgress\.total -eq 0' -and $cpContent -match '"D:—"'
Write-TestResult "D:0/0 prevented when active/pending exists" $hasPreventionLogic

# Test 3c: D:done/total shown when total > 0
$hasNormalToken = $cpContent -match '"D:\$\(\$laneProgress\.done\)/\$\(\$laneProgress\.total\)"'
Write-TestResult "Normal D:x/x token when total > 0" $hasNormalToken

# ============================================================================
# TEST 4: Get-LaneProgress includes failed
# ============================================================================
Write-Host "`n--- Test 4: Get-LaneProgress Includes Failed ---" -ForegroundColor Yellow

# Test 4a: failedStatuses defined
$hasFailedStatuses = $cpContent -match '\$failedStatuses\s*=.*"failed"'
Write-TestResult "failedStatuses category defined" $hasFailedStatuses

# Test 4b: failed included in result
$hasFailedResult = $cpContent -match 'result\.failed\s*='
Write-TestResult "result.failed returned" $hasFailedResult

# Test 4c: total is explicit sum (not COUNT(*))
$hasExplicitSum = $cpContent -match '\$result\.total\s*=\s*\$result\.done\s*\+.*\$result\.failed'
Write-TestResult "total is explicit sum including failed" $hasExplicitSum

# ============================================================================
# TEST 5: Unit Test - Health Indicator Logic
# ============================================================================
Write-Host "`n--- Test 5: Health Indicator Unit Tests ---" -ForegroundColor Yellow

# Extract Get-LaneHealthIndicator function for testing
$funcMatch = [regex]::Match($cpContent, '(?ms)# --- v21\.4: Helper to compute per-lane health.*?function Get-LaneHealthIndicator\s*\{.*?^\s{8}\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if ($funcMatch.Success) {
    try {
        Invoke-Expression $funcMatch.Value

        # Test cases
        $testCases = @(
            @{ Status = @{State="BLOCKED"}; Done=0; Total=10; Active=0; Blocked=1; Expected="Red"; Desc="BLOCKED state -> RED" },
            @{ Status = @{State="RUNNING"}; Done=0; Total=0; Active=1; Blocked=0; Expected="Yellow"; Desc="active>0, total=0 -> YELLOW" },
            @{ Status = @{State="RUNNING"}; Done=0; Total=0; Active=0; Blocked=0; Expected="Yellow"; Desc="RUNNING but total=0 -> YELLOW (unknown accounting)" },
            @{ Status = @{State="RUNNING"}; Done=7; Total=10; Active=0; Blocked=0; Expected="Green"; Desc="70% done, no blockers -> GREEN" },
            @{ Status = @{State="IDLE"}; Done=0; Total=0; Active=0; Blocked=0; Expected="Yellow"; Desc="IDLE state -> YELLOW" },
            @{ Status = @{State="READY"}; Done=3; Total=10; Active=0; Blocked=0; Expected="Green"; Desc="READY state -> GREEN" },
            @{ Status = @{State="READY"}; Done=0; Total=0; Active=0; Blocked=0; Expected="Yellow"; Desc="READY but total=0 -> YELLOW (no tasks)" }
        )

        foreach ($tc in $testCases) {
            try {
                $result = Get-LaneHealthIndicator -Status $tc.Status -Done $tc.Done -Total $tc.Total -Active $tc.Active -Blocked $tc.Blocked
                $passed = $result.Color -eq $tc.Expected
                Write-TestResult $tc.Desc $passed "Got: $($result.Color), Expected: $($tc.Expected)"
            } catch {
                Write-TestResult $tc.Desc $false "Error: $_"
            }
        }
    } catch {
        Write-TestResult "Function extraction" $false "Could not load function: $_"
    }
} else {
    Write-TestResult "Function extraction" $false "Could not find Get-LaneHealthIndicator in source"
}

# ============================================================================
# TEST 6: D:— Token Logic Unit Test
# ============================================================================
Write-Host "`n--- Test 6: D:— Token Logic ---" -ForegroundColor Yellow

# Test that the token logic pattern exists and is correct
$hasTokenLogic = $cpContent -match '\$doneToken\s*=' -and $cpContent -match '\$laneProgress\.total -eq 0' -and $cpContent -match '"D:—"'
Write-TestResult "doneToken conditional logic correct" $hasTokenLogic

# Verify pattern: when total=0 AND (active>0 OR pending>0) -> D:—
$hasActiveOrPending = $cpContent -match '\$la -gt 0 -or \$laneProgress\.pending -gt 0 -or \$laneProgress\.active -gt 0'
Write-TestResult "Checks active OR pending for D:— decision" $hasActiveOrPending

# ============================================================================
# TEST 7: v24.0 Draw Dot Last (prevents overwrite)
# ============================================================================
Write-Host "`n--- Test 7: v24.0 Draw Dot Last ---" -ForegroundColor Yellow

# Test 7a: Dot drawn in lane loop (after Draw-RightPanelLine)
$hasDotInLoop = $cpContent -match 'Draw-RightPanelLine.*\r?\n.*\}[\s\S]{0,200}v24\.0.*Draw health dot LAST'
Write-TestResult "Dot drawn after Draw-RightPanelLine in loop" $hasDotInLoop

# Test 7b: Dot drawing removed from Draw-StreamLineLeft (should NOT have Set-Pos $Row $dotX)
$dotRemovedFromHelper = -not ($cpContent -match 'function Draw-StreamLineLeft[\s\S]*?Set-Pos \$Row \$dotX[\s\S]*?\n\s{8}\}')
Write-TestResult "Dot drawing removed from Draw-StreamLineLeft" $dotRemovedFromHelper

# Test 7c: Clamping logic present
$hasClampLogic = $cpContent -match 'if \(\$dotX -lt 0\).*\$dotX = 0' -and $cpContent -match 'if \(\$dotX -ge \$W\)'
Write-TestResult "dotX clamping logic present" $hasClampLogic

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

exit $testsFailed
