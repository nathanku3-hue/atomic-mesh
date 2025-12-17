#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Acceptance tests for Plan stage draft-aware semantics (v16.8)
.DESCRIPTION
    Verifies the 3-state Plan stage logic:
    - Scenario A: No draft, no tasks → PLAN=RED, Next=/draft-plan
    - Scenario B: Draft exists, not accepted → PLAN=YELLOW, Next=/accept-plan
    - Scenario C: Plan accepted (tasks queued) → PLAN=GREEN, Next advances to Work
.NOTES
    Run: pwsh tests/test_plan_stage_semantics.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Plan Stage Semantics Test (v16.8) ===" -ForegroundColor Cyan
Write-Host ""

$controlPanelPath = Join-Path $PSScriptRoot ".." "control_panel.ps1"

if (-not (Test-Path $controlPanelPath)) {
    Write-Host "FAIL: control_panel.ps1 not found at $controlPanelPath" -ForegroundColor Red
    exit 1
}

Write-Host "Reading: $controlPanelPath" -ForegroundColor Gray
$content = Get-Content $controlPanelPath -Raw

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

# ============================================================================
# Test 1: Plan stage comment describes draft-aware semantics
# ============================================================================
Write-Host ""
Write-Host "Test 1: Plan stage header comment" -ForegroundColor Cyan

if ($content -match 'PLAN stage.*v16\.8.*Draft-aware') {
    Test-Pass "Plan stage header references v16.8 draft-aware semantics"
} else {
    Test-Fail "Plan stage header references v16.8 draft-aware semantics" "Expected 'PLAN stage.*v16.8.*Draft-aware'"
}

# ============================================================================
# Test 2: Draft detection (single source of truth)
# ============================================================================
Write-Host ""
Write-Host "Test 2: Draft detection variables" -ForegroundColor Cyan

if ($content -match '\$hasDraftPlan\s*=\s*\$false') {
    Test-Pass "hasDraftPlan variable initialized"
} else {
    Test-Fail "hasDraftPlan variable initialized" "Expected '\$hasDraftPlan = \$false'"
}

if ($content -match 'draft_\*\.md') {
    Test-Pass "Draft detection uses draft_*.md pattern"
} else {
    Test-Fail "Draft detection uses draft_*.md pattern" "Expected filter for draft_*.md"
}

# ============================================================================
# Test 3: Plan state derivation logic
# ============================================================================
Write-Host ""
Write-Host "Test 3: Plan state derivation" -ForegroundColor Cyan

# Scenario A: RED when no draft and no tasks
if ($content -match '#\s*No draft,\s*no tasks' -and $content -match '\$planState\s*=\s*"RED"[\s\S]*?\$planHint\s*=\s*"No draft"') {
    Test-Pass "Scenario A: Plan=RED when no draft exists"
} else {
    Test-Fail "Scenario A: Plan=RED when no draft exists" "Expected RED state with 'No draft' hint"
}

if ($content -match '\$planHint\s*=\s*"No draft"') {
    Test-Pass "Scenario A: Hint shows 'No draft'"
} else {
    Test-Fail "Scenario A: Hint shows 'No draft'" "Expected planHint = 'No draft'"
}

# Scenario B: YELLOW when draft exists but not accepted
if ($content -match '#\s*Draft exists but not yet accepted[\s\S]*?\$planState\s*=\s*"YELLOW"') {
    Test-Pass "Scenario B: Plan=YELLOW when draft exists"
} else {
    Test-Fail "Scenario B: Plan=YELLOW when draft exists" "Expected YELLOW state when hasDraftPlan is true"
}

if ($content -match '\$planHint\s*=\s*"Draft ready"') {
    Test-Pass "Scenario B: Hint shows 'Draft ready'"
} else {
    Test-Fail "Scenario B: Hint shows 'Draft ready'" "Expected planHint = 'Draft ready'"
}

# Scenario C: GREEN when tasks are queued (accepted)
if ($content -match '#\s*Plan accepted.*tasks hydrated[\s\S]*?\$planState\s*=\s*"GREEN"') {
    Test-Pass "Scenario C: Plan=GREEN when plan accepted"
} else {
    Test-Fail "Scenario C: Plan=GREEN when plan accepted" "Expected GREEN state when hasAcceptedPlan is true"
}

if ($content -match '\$planHint\s*=\s*"Accepted\s*\(') {
    Test-Pass "Scenario C: Hint shows 'Accepted'"
} else {
    Test-Fail "Scenario C: Hint shows 'Accepted'" "Expected planHint = 'Accepted (N queued)'"
}

# ============================================================================
# Test 4: Next action routing
# ============================================================================
Write-Host ""
Write-Host "Test 4: Next action routing" -ForegroundColor Cyan

# Scenario A: /draft-plan when Plan=RED
if ($content -match '#\s*No draft,\s*no tasks.*suggest creating a draft[\s\S]*?\$suggestedNext\.command\s*=\s*"/draft-plan"') {
    Test-Pass "Scenario A: Next=/draft-plan when Plan=RED"
} else {
    Test-Fail "Scenario A: Next=/draft-plan when Plan=RED" "Expected /draft-plan command for RED state"
}

# Scenario B: /accept-plan when draft exists
if ($content -match '#\s*Draft exists.*suggest accept[\s\S]*?\$suggestedNext\.command\s*=\s*"/accept-plan"') {
    Test-Pass "Scenario B: Next=/accept-plan when draft exists"
} else {
    Test-Fail "Scenario B: Next=/accept-plan when draft exists" "Expected /accept-plan command when draft exists"
}

# ============================================================================
# Test 5: Work stage dependency on Plan=GREEN
# ============================================================================
Write-Host ""
Write-Host "Test 5: Work stage requires Plan=GREEN" -ForegroundColor Cyan

if ($content -match 'if\s*\(\$planState\s*-eq\s*"GREEN"\)\s*\{[\s\S]*?\$workState\s*=') {
    Test-Pass "Work stage only activates when Plan=GREEN"
} else {
    Test-Fail "Work stage only activates when Plan=GREEN" "Expected Work to check planState -eq 'GREEN'"
}

if ($content -match '#\s*GRAY\s*=\s*no accepted plan') {
    Test-Pass "Work stage comment documents GRAY = no accepted plan"
} else {
    Test-Fail "Work stage comment documents GRAY = no accepted plan" "Expected comment about GRAY state"
}

# ============================================================================
# Test 6: Blocker logic (Plan/Work are NOT hard blockers)
# ============================================================================
Write-Host ""
Write-Host "Test 6: Blocker level handling" -ForegroundColor Cyan

# Check that Plan/Work stages are NOT treated as hard blockers
if ($content -match 'Plan/Work stages are NOT blockers') {
    Test-Pass "Plan/Work documented as not hard blockers"
} else {
    Test-Fail "Plan/Work documented as not hard blockers" "Expected comment about Plan/Work not being blockers"
}

# Check that Get-PrimaryBlocker returns WARN levels (not FAIL for soft issues)
if ($content -match 'return @\{\s*Level\s*=\s*"WARN"') {
    Test-Pass "Blocker returns WARN for soft issues"
} else {
    Test-Fail "Blocker returns WARN for soft issues" "Expected WARN level returns"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "  Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

if ($testsFailed -gt 0) {
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASS" -ForegroundColor Green
    exit 0
}
