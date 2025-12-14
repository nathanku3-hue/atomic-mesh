#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression test: QA count query must use COUNT(*), not LIMIT with .Count
.DESCRIPTION
    Guards against bug where QA shows wrong count when >5 HIGH risk tasks exist.
    Bug pattern: LIMIT 5 followed by $result.Count (caps count at 5)
    Correct pattern: COUNT(*) query for accurate count
.NOTES
    Run: pwsh tests/test_qa_count_regression.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== QA Count Query Regression Test ===" -ForegroundColor Cyan
Write-Host ""

$controlPanelPath = Join-Path $PSScriptRoot ".." "control_panel.ps1"

if (-not (Test-Path $controlPanelPath)) {
    Write-Host "❌ FAIL: control_panel.ps1 not found at $controlPanelPath" -ForegroundColor Red
    exit 1
}

Write-Host "Reading: $controlPanelPath" -ForegroundColor Gray
$content = Get-Content $controlPanelPath -Raw

# Find the Get-StreamStatusLine function and QA section
$qaSection = $content | Select-String -Pattern '(?s)"QA"\s*\{.*?catch\s*\{.*?\}.*?\}' -AllMatches |
    Select-Object -ExpandProperty Matches |
    Select-Object -ExpandProperty Value -First 1

if (-not $qaSection) {
    Write-Host "❌ FAIL: Could not find QA section in Get-StreamStatusLine" -ForegroundColor Red
    exit 1
}

Write-Host "Found QA section (length: $($qaSection.Length) chars)" -ForegroundColor Gray
Write-Host ""

# Test 1: Must have COUNT(*) query
$hasCountQuery = $qaSection -match 'COUNT\(\*\)'
if (-not $hasCountQuery) {
    Write-Host "❌ FAIL: QA section does not use COUNT(*) query" -ForegroundColor Red
    Write-Host "   Expected: SELECT COUNT(*) ... FROM tasks WHERE risk = 'HIGH'" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ PASS: QA section uses COUNT(*) query" -ForegroundColor Green

# Test 2: Must use the count result (not .Count property)
$usesCountResult = $qaSection -match '\$countResult\[0\]\.cnt|\$countResult\.cnt'
if (-not $usesCountResult) {
    Write-Host "❌ FAIL: QA section does not extract count from COUNT(*) result" -ForegroundColor Red
    Write-Host "   Expected: \$count = [int]\$countResult[0].cnt" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ PASS: QA section extracts count from COUNT(*) result" -ForegroundColor Green

# Test 3: Must NOT use problematic pattern (LIMIT with .Count)
$hasBugPattern = $qaSection -match 'LIMIT\s+\d+.*?\.Count\s*-gt\s*0'
if ($hasBugPattern) {
    Write-Host "❌ FAIL: QA section uses buggy pattern: LIMIT followed by .Count" -ForegroundColor Red
    Write-Host "   This bug causes incorrect count when >LIMIT tasks exist" -ForegroundColor Yellow
    Write-Host "   Use COUNT(*) query instead" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ PASS: QA section does not use buggy LIMIT + .Count pattern" -ForegroundColor Green

# Test 4: Must have separate query for first task (for example)
$hasFirstTaskQuery = $qaSection -match 'LIMIT\s+1' -and $qaSection -match 'firstTask'
if (-not $hasFirstTaskQuery) {
    Write-Host "⚠️  WARN: QA section may not fetch first task for example display" -ForegroundColor Yellow
    Write-Host "   Expected: Separate query with LIMIT 1 to get example task ID" -ForegroundColor Gray
} else {
    Write-Host "✅ PASS: QA section fetches first task separately (for example)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== All Critical Tests Pass ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  ✅ Uses COUNT(*) for accurate count" -ForegroundColor Gray
Write-Host "  ✅ Extracts count from result properly" -ForegroundColor Gray
Write-Host "  ✅ Does NOT use buggy LIMIT + .Count pattern" -ForegroundColor Gray
Write-Host "  ✅ Fetches example task separately" -ForegroundColor Gray
Write-Host ""

exit 0
