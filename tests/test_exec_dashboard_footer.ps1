#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for EXEC dashboard footer - ensures no trailing artifacts.
.DESCRIPTION
    T-UX-FOOTER-NO-ARTIFACTS: The dashboard bottom border and footer line must NOT
    have trailing '+' or '|' pip artifacts at the right edge.
    v19.8 fixes:
    - Bottom border: Right panel ends with '|' not '+' (but footer clears it)
    - Footer line: Content extends to last column, no gap for pip to appear
.EXAMPLE
    .\tests\test_exec_dashboard_footer.ps1
#>

$ErrorActionPreference = "Stop"
$script:TestsPassed = 0
$script:TestsFailed = 0

# Load the control panel to get the test helper functions
$ControlPanelPath = Join-Path $PSScriptRoot "..\control_panel.ps1"
$content = Get-Content $ControlPanelPath -Raw

# Extract and evaluate the test helper functions
$borderFuncMatch = [regex]::Match($content, 'function Get-DashboardBottomBorderForTest \{[\s\S]*?\n\}')
if (-not $borderFuncMatch.Success) {
    Write-Host "FAIL: Could not find Get-DashboardBottomBorderForTest function" -ForegroundColor Red
    exit 1
}
Invoke-Expression $borderFuncMatch.Value

$footerFuncMatch = [regex]::Match($content, 'function Get-FooterLineForTest \{[\s\S]*?\n\}')
if (-not $footerFuncMatch.Success) {
    Write-Host "FAIL: Could not find Get-FooterLineForTest function" -ForegroundColor Red
    exit 1
}
Invoke-Expression $footerFuncMatch.Value

function Assert-Equal {
    param([string]$Expected, [string]$Actual, [string]$Message)
    if ($Expected -eq $Actual) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        Write-Host "    Expected: $Expected" -ForegroundColor Yellow
        Write-Host "    Actual:   $Actual" -ForegroundColor Yellow
        $script:TestsFailed++
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:TestsFailed++
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
        $script:TestsPassed++
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:TestsFailed++
    }
}

# ============================================================================
# TEST: Bottom border does NOT end with '+'
# ============================================================================
Write-Host "`nTest: Dashboard bottom border character" -ForegroundColor Cyan

$testWidths = @(80, 100, 120, 160, 200, 121)  # Include odd width

foreach ($width in $testWidths) {
    $borderLine = Get-DashboardBottomBorderForTest -TerminalWidth $width

    # v19.8 requirement: Line must NOT end with '+' or '|' (footer owns last column)
    $endsWithPlus = $borderLine -match '\+\s*$'
    Assert-False $endsWithPlus "Width $width`: Border does not end with '+'"

    $endsWithPipe = $borderLine -match '\|\s*$'
    Assert-False $endsWithPipe "Width $width`: Border does not end with '|'"

    # Line SHOULD end with '-' (not | or +, footer clears and owns the row)
    $endsWithDash = $borderLine -match '\-\s*$'
    Assert-True $endsWithDash "Width $width`: Border ends with '-'"

    # Line should be exactly terminal width characters
    Assert-Equal $width $borderLine.Length "Width $width`: Border is exactly $width chars"
}

# ============================================================================
# TEST: Border pattern structure
# ============================================================================
Write-Host "`nTest: Border pattern structure" -ForegroundColor Cyan

$borderLine = Get-DashboardBottomBorderForTest -TerminalWidth 120
$half = 60

$leftPanel = $borderLine.Substring(0, $half)
Assert-True ($leftPanel[0] -eq '+') "Left panel starts with '+'"
Assert-True ($leftPanel[-1] -eq '+') "Left panel ends with '+'"

# Right panel is $half to end, but ends with '-' (no trailing char, footer owns it)
$rightPanel = $borderLine.Substring($half)
Assert-True ($rightPanel[0] -eq '+') "Right panel starts with '+'"
Assert-True ($rightPanel[-1] -eq '-') "Right panel ends with '-' (v19.8: footer owns last col)"

# ============================================================================
# TEST: Footer line has NO trailing '|' pip artifact
# ============================================================================
Write-Host "`nTest: Footer line - no trailing '|' pip artifact" -ForegroundColor Cyan

$modes = @("OPS", "PLAN", "RUN", "SHIP")

foreach ($width in $testWidths) {
    foreach ($mode in $modes) {
        $footerLine = Get-FooterLineForTest -TerminalWidth $width -Mode $mode

        # v19.8 requirement: Line must NOT end with '|' (the pip artifact)
        $endsWithPipe = $footerLine -match '\|\s*$'
        Assert-False $endsWithPipe "Width $width, Mode $mode`: Footer does not end with '|' pip"

        # Line should be exactly terminal width characters
        Assert-Equal $width $footerLine.Length "Width $width, Mode $mode`: Footer is exactly $width chars"

        # Line should end with the mode badge ']'
        $endsWithBracket = $footerLine -match '\]\s*$'
        Assert-True $endsWithBracket "Width $width, Mode $mode`: Footer ends with ']' (mode badge)"
    }
}

# ============================================================================
# TEST: Footer line content is correct
# ============================================================================
Write-Host "`nTest: Footer line content" -ForegroundColor Cyan

$footerLine = Get-FooterLineForTest -TerminalWidth 120 -Mode "OPS"
Assert-True ($footerLine -match '\[OPS\]') "OPS mode shows [OPS] badge"
Assert-True ($footerLine -match "ask 'health', 'drift', or type /ops") "OPS mode shows correct hint"

$footerLine = Get-FooterLineForTest -TerminalWidth 120 -Mode "PLAN"
Assert-True ($footerLine -match '\[PLAN\]') "PLAN mode shows [PLAN] badge"
Assert-True ($footerLine -match "describe what you want to build") "PLAN mode shows correct hint"

# ============================================================================
# TEST: No double borders at right edge (the "pip" artifact pattern)
# ============================================================================
Write-Host "`nTest: No double border pattern at right edge" -ForegroundColor Cyan

foreach ($width in $testWidths) {
    $footerLine = Get-FooterLineForTest -TerminalWidth $width -Mode "OPS"

    # The buggy pattern was: content followed by gap followed by '|'
    # e.g., "[OPS] |" or "[OPS]  |"
    $hasDoubleBorder = $footerLine -match '\]\s+\|'
    Assert-False $hasDoubleBorder "Width $width`: No gap+pipe after mode badge"

    # Also check for literal "|" anywhere in the last 3 characters (except as part of content)
    $last3 = $footerLine.Substring($width - 3)
    $hasPipInLast3 = $last3 -match '\|'
    Assert-False $hasPipInLast3 "Width $width`: No '|' in last 3 characters"
}

# ============================================================================
# SUMMARY
# ============================================================================
Write-Host "`n" + ("=" * 60) -ForegroundColor White
Write-Host "Results: $script:TestsPassed passed, $script:TestsFailed failed" -ForegroundColor $(if ($script:TestsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ("=" * 60) -ForegroundColor White

if ($script:TestsFailed -gt 0) {
    exit 1
}
exit 0
