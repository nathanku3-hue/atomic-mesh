# Test: v22.0 Progress Bar and De-coloring
#
# Acceptance Criteria:
# 1. Render-ProgressBar5 correctly maps done/total to 5-block bars
# 2. Min-1 rule: if done > 0 but rounds to 0 blocks, show 1 block
# 3. FRONTEND row should NOT have multiple colored segments (de-coloring)
#
# Run: pwsh tests/test_progress_bar_decolor.ps1

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

Write-Host "`n=== v22.0 Progress Bar & De-coloring Tests ===" -ForegroundColor Cyan

# Setup: Get paths and load control_panel
$scriptDir = Split-Path -Parent $PSScriptRoot
$cpPath = Join-Path $scriptDir "control_panel.ps1"
$cpContent = Get-Content $cpPath -Raw

# ============================================================================
# TEST 1: Render-ProgressBar5 function exists
# ============================================================================
Write-Host "`n--- Test 1: Render-ProgressBar5 Function ---" -ForegroundColor Yellow

$hasRenderProgressBar5 = $cpContent -match 'function Render-ProgressBar5'
Write-TestResult "Render-ProgressBar5 function exists" $hasRenderProgressBar5

# ============================================================================
# TEST 2: Progress bar rendering logic
# ============================================================================
Write-Host "`n--- Test 2: Progress Bar Rendering Logic ---" -ForegroundColor Yellow

# Test 2a: Function handles total=0 case (empty bar)
$hasEmptyBarLogic = $cpContent -match 'if \(\$Total -le 0\).*□□□□□'
Write-TestResult "Handles total=0 with empty bar" ($cpContent -match '\$Total -le 0' -and $cpContent -match '"□□□□□"')

# Test 2b: Min-1 rule exists (if done>0 and blocks==0, blocks=1)
$hasMin1Rule = $cpContent -match 'if \(\$Done -gt 0 -and \$blocks -eq 0\)'
Write-TestResult "Min-1 rule implemented" $hasMin1Rule `
    "Should ensure at least 1 block when done > 0"

# Test 2c: Standard rounding used
$hasRounding = $cpContent -match '\[Math\]::Round\(5 \* \$ratio\)'
Write-TestResult "Uses standard rounding" $hasRounding

# Test 2d: Cap at 5 blocks
$hasCap = $cpContent -match '\$blocks -gt 5'
Write-TestResult "Caps at 5 blocks" $hasCap

# ============================================================================
# TEST 3: Get-LaneProgress function
# ============================================================================
Write-Host "`n--- Test 3: Get-LaneProgress Function ---" -ForegroundColor Yellow

$hasGetLaneProgress = $cpContent -match 'function Get-LaneProgress'
Write-TestResult "Get-LaneProgress function exists" $hasGetLaneProgress

# Test 3b: Returns expected fields
$returnsDone = $cpContent -match 'result\.done\s*='
$returnsTotal = $cpContent -match 'result\.total\s*='
$returnsActive = $cpContent -match 'result\.active\s*='
$returnsPending = $cpContent -match 'result\.pending\s*='
$returnsBlocked = $cpContent -match 'result\.blocked\s*='
Write-TestResult "Returns done, total, active, pending, blocked" `
    ($returnsDone -and $returnsTotal -and $returnsActive -and $returnsPending -and $returnsBlocked)

# ============================================================================
# TEST 4: De-coloring implementation
# ============================================================================
Write-Host "`n--- Test 4: De-coloring Implementation ---" -ForegroundColor Yellow

# Test 4a: Lane name rendered in neutral color (DarkGray)
$hasNeutralLaneName = $cpContent -match 'Write-Host "\$\(\$lane.*Name.*" -NoNewline -ForegroundColor DarkGray'
Write-TestResult "Lane name uses neutral color" `
    ($cpContent -match '\$laneDisplay\.Name.*-ForegroundColor DarkGray' -or $cpContent -match '\$laneForRow\.Name.*-ForegroundColor DarkGray')

# Test 4b: State rendered in neutral color (not BarColor)
$hasNeutralState = $cpContent -match '\$.*State.*-ForegroundColor DarkGray'
Write-TestResult "State uses neutral color" $hasNeutralState

# Test 4c: Bar still uses BarColor
$hasColoredBar = $cpContent -match '\$.*Bar.*-ForegroundColor \$.*BarColor'
Write-TestResult "Bar retains BarColor" $hasColoredBar

# ============================================================================
# TEST 5: Compact tokens for work lanes
# ============================================================================
Write-Host "`n--- Test 5: Compact Tokens ---" -ForegroundColor Yellow

# Test 5a: A:<active> D:<done>/<total> or D:— format (v22.1 supports both)
$hasCompactTokens = $cpContent -match '"A:\$la \$doneToken"' -or $cpContent -match 'A:\$.*D:\$'
Write-TestResult "Compact token format A:x D:x/x or D:—" $hasCompactTokens

# Test 5b: Work lanes marked with IsWorkLane
$hasIsWorkLane = $cpContent -match 'IsWorkLane\s*=\s*\$true'
Write-TestResult "Work lanes marked with IsWorkLane flag" $hasIsWorkLane

# ============================================================================
# TEST 6: Progress bar expected outputs (unit test simulation)
# ============================================================================
Write-Host "`n--- Test 6: Expected Bar Outputs ---" -ForegroundColor Yellow

# Extract and define the function locally for testing (avoid loading full control_panel.ps1)
$funcMatch = [regex]::Match($cpContent, '(?ms)function Render-ProgressBar5\s*\{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if ($funcMatch.Success) {
    try {
        Invoke-Expression $funcMatch.Value

        # Test cases: [done, total, expected_bar]
        $testCases = @(
            @{ Done = 0; Total = 0; Expected = "□□□□□"; Desc = "0/0 -> empty" },
            @{ Done = 0; Total = 10; Expected = "□□□□□"; Desc = "0/10 -> empty" },
            @{ Done = 5; Total = 10; Expected = "■■□□□"; Desc = "5/10 -> half (2.5 banker-rounds to 2)" },
            @{ Done = 10; Total = 10; Expected = "■■■■■"; Desc = "10/10 -> full" },
            @{ Done = 1; Total = 10; Expected = "■□□□□"; Desc = "1/10 -> min-1 rule" },
            @{ Done = 2; Total = 10; Expected = "■□□□□"; Desc = "2/10 -> 1 block" },
            @{ Done = 3; Total = 10; Expected = "■■□□□"; Desc = "3/10 -> 2 blocks" },
            @{ Done = 8; Total = 10; Expected = "■■■■□"; Desc = "8/10 -> 4 blocks" }
        )

        foreach ($tc in $testCases) {
            try {
                $result = Render-ProgressBar5 -Done $tc.Done -Total $tc.Total
                $passed = $result -eq $tc.Expected
                Write-TestResult $tc.Desc $passed "Got: $result, Expected: $($tc.Expected)"
            } catch {
                Write-TestResult $tc.Desc $false "Error: $_"
            }
        }
    } catch {
        Write-TestResult "Function extraction" $false "Could not load function: $_"
    }
} else {
    Write-TestResult "Function extraction" $false "Could not find Render-ProgressBar5 in source"
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Green" })

exit $testsFailed
