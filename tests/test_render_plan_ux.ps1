#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for PLAN screen UX redesign (v24.0)
.DESCRIPTION
    Verifies RenderPlan.ps1 improvements:
    - Next action displayed at TOP (most prominent position)
    - Empty lanes hidden with idle summary
    - No Bar column clutter
    - Compact output for idle state
#>

$ErrorActionPreference = "Stop"
$renderPlanPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Render" "RenderPlan.ps1"

if (-not (Test-Path $renderPlanPath)) {
    Write-Host "FAIL: RenderPlan.ps1 not found" -ForegroundColor Red
    exit 1
}

$content = Get-Content $renderPlanPath -Raw
$testsFailed = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

# 1) Next action at TOP - before lane table (not at bottom)
# Check that ">>> Next:" appears before "$laneHeader" in the code
$nextActionPos = $content.IndexOf('>>> Next:')
$laneHeaderPos = $content.IndexOf('$laneHeader')
if ($nextActionPos -gt 0 -and $laneHeaderPos -gt 0 -and $nextActionPos -lt $laneHeaderPos) {
    Pass "Next action displayed at TOP (before lane table)"
} else {
    Fail "Next action at TOP" "Expected '>>> Next:' to appear before lane table rendering"
}

# 2) Empty lanes filtered - not rendered when Q:0 AND A:0
if ($content -match 'if \(\$l\.Queued -gt 0 -or \$l\.Active -gt 0 -or \$l\.State -eq "RUNNING"\)') {
    Pass "Empty lanes filtered (only show active lanes)"
} else {
    Fail "Empty lanes filtered" "Expected filter logic for lanes with Q>0, A>0, or RUNNING"
}

# 3) Idle summary line displayed
if ($content -match 'All \$idleLaneCount lanes idle\. Type /go or /help\.') {
    Pass "Idle state shows summary line"
} else {
    Fail "Idle summary line" "Expected 'All N lanes idle' message"
}

# 4) Bar column removed from lane output
if ($content -notmatch 'Bar\s*\|' -and $content -notmatch '\$bar\s*=.*\.\.\.\.\.\.\.\.\.\.' -and $content -notmatch '"\.\.\.\.\.\.\.\.\.\."') {
    Pass "Bar column removed (no placeholder dots)"
} else {
    Fail "Bar column removed" "Found Bar column or placeholder dots in lane rendering"
}

# 5) Compact lane format (Q | A | State)
if ($content -match 'Lane\s+\|\s+Q\s+\|\s+A\s+\|\s+State') {
    Pass "Lane header uses compact format (Q | A | State)"
} else {
    Fail "Compact lane format" "Expected 'Lane | Q | A | State' header"
}

# 6) No-data fallback message
if ($content -match 'No queued work\. Type /go or /help\.') {
    Pass "No-data fallback shows helpful message"
} else {
    Fail "No-data fallback" "Expected 'No queued work. Type /go or /help.' message"
}

# 7) Does not crash for empty snapshot (null checks)
if ($content -match 'if \(-not \$lanes -or \$lanes\.Count -eq 0\)' -or
    $content -match 'if \(\$lanes -and \$lanes\.Count -gt 0\)') {
    Pass "Handles empty lane metrics gracefully"
} else {
    Fail "Empty snapshot handling" "Expected null checks for lanes"
}

# 8) Status text is human-readable (not just raw status)
if ($content -match '"Plan accepted"' -and
    $content -match '"Draft pending review"' -and
    $content -match '"Blocked - see alerts"') {
    Pass "Status uses human-readable text"
} else {
    Fail "Human-readable status" "Expected friendly status messages like 'Plan accepted', 'Draft pending review'"
}

# 9) Idle lane count is tracked
if ($content -match '\$idleLaneCount\+\+' -or $content -match '\$idleLaneCount\s*=\s*0') {
    Pass "Idle lane count tracked"
} else {
    Fail "Idle lane count" "Expected idleLaneCount tracking"
}

# 10) Alerts rendered with prefix for visibility
if ($content -match '"\!\s*\$alert"' -or $content -match '\$message = "\! \$alert"') {
    Pass "Alerts have visibility prefix (!)"
} else {
    Fail "Alert prefix" "Expected '!' prefix on alert messages"
}

Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
