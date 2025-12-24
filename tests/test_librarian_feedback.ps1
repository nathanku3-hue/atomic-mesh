#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests for Librarian feedback integration
.DESCRIPTION
    Verifies:
    - Librarian one_liner preferred over readiness hint
    - Missing cache falls back to readiness hint
    - Invalid JSON ignored safely (no crash)
    - Stale cache still shown but marked stale
    - /d command doesn't trigger doc details toggle
.NOTES
    Run: pwsh tests/test_librarian_feedback.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Librarian Feedback Tests ===" -ForegroundColor Cyan
Write-Host ""

Set-Location $PSScriptRoot/..

# Source module files for UiSnapshot type (needed for Test 13)
$ModuleRoot = "$PSScriptRoot/../src/AtomicMesh.UI"
$files = @(
    'Private/Models/UiToast.ps1',
    'Private/Models/UiEvent.ps1',
    'Private/Models/UiEventLog.ps1',
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/WorkerInfo.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Models/UiCache.ps1',
    'Private/Models/UiState.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1',
    'Private/Render/Console.ps1'
)
foreach ($f in $files) {
    . (Join-Path $ModuleRoot $f)
}

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

function New-TestDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-lib-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Get-SnapshotData($dir) {
    $result = python tools/snapshot.py $dir 2>&1 | ConvertFrom-Json
    return $result
}

# ============================================================================
# Test 1: Missing cache returns empty defaults
# ============================================================================
Write-Host "Test 1: Missing cache returns empty defaults" -ForegroundColor Cyan

$dir1 = New-TestDir
try {
    $result = Get-SnapshotData $dir1
    $prdOneLiner = $result.LibrarianDocFeedback.PRD.one_liner
    $present = $result.LibrarianDocFeedbackPresent

    if ($prdOneLiner -eq "" -and $present -eq $false) {
        Test-Pass "Missing cache returns empty defaults"
    } else {
        Test-Fail "Missing cache returns empty defaults" "one_liner='$prdOneLiner', present=$present"
    }
} finally {
    Remove-Item -Path $dir1 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 2: Valid cache returns Librarian feedback
# ============================================================================
Write-Host ""
Write-Host "Test 2: Valid cache returns Librarian feedback" -ForegroundColor Cyan

$dir2 = New-TestDir
try {
    # Create cache file
    $stateDir = Join-Path $dir2 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $cacheContent = @{
        version = 1
        generated_at = "2025-12-20T10:00:00Z"
        docs = @{
            PRD = @{
                one_liner = "add goals section"
                paragraph = "The PRD needs a clear goals section with measurable outcomes."
            }
            SPEC = @{
                one_liner = "ready"
                paragraph = ""
            }
            DECISION_LOG = @{
                one_liner = "add decisions"
                paragraph = "Document key architectural decisions."
            }
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value $cacheContent -Encoding UTF8

    $result = Get-SnapshotData $dir2
    $prdOneLiner = $result.LibrarianDocFeedback.PRD.one_liner
    $prdParagraph = $result.LibrarianDocFeedback.PRD.paragraph
    $present = $result.LibrarianDocFeedbackPresent

    if ($prdOneLiner -eq "add goals section" -and $prdParagraph -match "goals section" -and $present -eq $true) {
        Test-Pass "Valid cache returns Librarian feedback"
    } else {
        Test-Fail "Valid cache returns Librarian feedback" "one_liner='$prdOneLiner', present=$present"
    }
} finally {
    Remove-Item -Path $dir2 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 3: Invalid JSON ignored safely (no crash)
# ============================================================================
Write-Host ""
Write-Host "Test 3: Invalid JSON ignored safely" -ForegroundColor Cyan

$dir3 = New-TestDir
try {
    # Create invalid cache file
    $stateDir = Join-Path $dir3 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value "{ invalid json }" -Encoding UTF8

    $result = Get-SnapshotData $dir3
    $present = $result.LibrarianDocFeedbackPresent

    if ($present -eq $false) {
        Test-Pass "Invalid JSON ignored safely"
    } else {
        Test-Fail "Invalid JSON ignored safely" "present=$present (expected false)"
    }
} finally {
    Remove-Item -Path $dir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 4: Stale cache marked as stale (>10 min old)
# ============================================================================
Write-Host ""
Write-Host "Test 4: Stale cache marked as stale" -ForegroundColor Cyan

$dir4 = New-TestDir
try {
    # Create cache file with old mtime
    $stateDir = Join-Path $dir4 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $cacheContent = @{
        version = 1
        docs = @{
            PRD = @{ one_liner = "stale hint"; paragraph = "" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
    } | ConvertTo-Json -Depth 5

    $cachePath = Join-Path $stateDir "librarian_doc_feedback.json"
    Set-Content -Path $cachePath -Value $cacheContent -Encoding UTF8

    # Set mtime to 15 minutes ago
    $oldTime = (Get-Date).AddMinutes(-15)
    (Get-Item $cachePath).LastWriteTime = $oldTime

    $result = Get-SnapshotData $dir4
    $stale = $result.LibrarianDocFeedbackStale
    $present = $result.LibrarianDocFeedbackPresent

    if ($stale -eq $true -and $present -eq $true) {
        Test-Pass "Stale cache marked as stale"
    } else {
        Test-Fail "Stale cache marked as stale" "stale=$stale, present=$present"
    }
} finally {
    Remove-Item -Path $dir4 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 5: Fresh cache not marked as stale
# ============================================================================
Write-Host ""
Write-Host "Test 5: Fresh cache not marked as stale" -ForegroundColor Cyan

$dir5 = New-TestDir
try {
    # Create fresh cache file
    $stateDir = Join-Path $dir5 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $cacheContent = @{
        version = 1
        docs = @{
            PRD = @{ one_liner = "fresh hint"; paragraph = "" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value $cacheContent -Encoding UTF8

    $result = Get-SnapshotData $dir5
    $stale = $result.LibrarianDocFeedbackStale
    $present = $result.LibrarianDocFeedbackPresent

    if ($stale -eq $false -and $present -eq $true) {
        Test-Pass "Fresh cache not marked as stale"
    } else {
        Test-Fail "Fresh cache not marked as stale" "stale=$stale, present=$present"
    }
} finally {
    Remove-Item -Path $dir5 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 6: Librarian feedback is optional and does not change score math
# ============================================================================
Write-Host ""
Write-Host "Test 6: Librarian feedback does not affect scores" -ForegroundColor Cyan

$dir6 = New-TestDir
try {
    # Create docs to get a score
    $docsDir = Join-Path $dir6 "docs"
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
    "# PRD`n## Goals`nTest goal" | Set-Content -Path (Join-Path $docsDir "PRD.md") -Encoding UTF8

    # Get score without Librarian cache
    $result1 = Get-SnapshotData $dir6
    $score1 = $result1.DocScores.PRD.score

    # Add Librarian cache
    $stateDir = Join-Path $dir6 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $cacheContent = @{
        version = 1
        docs = @{
            PRD = @{ one_liner = "custom hint"; paragraph = "Custom feedback" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
    } | ConvertTo-Json -Depth 5
    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value $cacheContent -Encoding UTF8

    # Get score with Librarian cache
    $result2 = Get-SnapshotData $dir6
    $score2 = $result2.DocScores.PRD.score

    if ($score1 -eq $score2) {
        Test-Pass "Librarian feedback does not affect scores"
    } else {
        Test-Fail "Librarian feedback does not affect scores" "score1=$score1, score2=$score2"
    }
} finally {
    Remove-Item -Path $dir6 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 7: /d command does NOT toggle doc details (goes to input buffer)
# ============================================================================
Write-Host ""
Write-Host "Test 7: /d command does NOT toggle doc details" -ForegroundColor Cyan

# This is a code check - verify that the D key handler only fires when input is empty
$startControlPanel = Get-Content "$PSScriptRoot/../src/AtomicMesh.UI/Public/Start-ControlPanel.ps1" -Raw

# Check that D key handler has guard for empty input
# Use (?s) for singleline mode (. matches newlines)
if ($startControlPanel -match '(?s)\$inputEmpty.*\$state\.CurrentPage -eq "PLAN".*\$isPreDraft.*ToggleDocDetails') {
    Test-Pass "/d command guard: D key only toggles when input empty + PLAN + pre-draft"
} else {
    Test-Fail "/d command guard" "D key handler may not have proper guards"
}

# ============================================================================
# Test 8: Stale cache appends * to Librarian hints
# ============================================================================
Write-Host ""
Write-Host "Test 8: Stale cache appends * to Librarian hints" -ForegroundColor Cyan

# Code check - verify reducer appends * when stale
$reducerCode = Get-Content "$PSScriptRoot/../src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1" -Raw

if ($reducerCode -match 'LibrarianDocFeedbackStale' -and $reducerCode -match '\$hint = "\$hint\*"') {
    Test-Pass "Stale indicator: reducer appends * to hints when stale"
} else {
    Test-Fail "Stale indicator" "Reducer may not append * to stale Librarian hints"
}

# ============================================================================
# Test 9: Paragraph sanitization strips newlines/tabs
# ============================================================================
Write-Host ""
Write-Host "Test 9: Paragraph sanitization strips newlines/tabs" -ForegroundColor Cyan

# Code check - verify RenderPlan sanitizes paragraph
$renderPlanCode = Get-Content "$PSScriptRoot/../src/AtomicMesh.UI/Private/Render/RenderPlan.ps1" -Raw

if ($renderPlanCode -match '\[\\r\\n\\t\]' -and $renderPlanCode -match '\\s\+') {
    Test-Pass "Paragraph safety: newlines/tabs stripped before word-wrap"
} else {
    Test-Fail "Paragraph safety" "RenderPlan may not sanitize paragraph text"
}

# ============================================================================
# Test 10: Tier 2 fields default to 0 when cache missing
# ============================================================================
Write-Host ""
Write-Host "Test 10: Tier 2 fields default to 0 when cache missing" -ForegroundColor Cyan

$dir10 = New-TestDir
try {
    $result = Get-SnapshotData $dir10
    $quality = $result.LibrarianOverallQuality
    $confidence = $result.LibrarianConfidence
    $risks = $result.LibrarianCriticalRisksCount

    if ($quality -eq 0 -and $confidence -eq 0 -and $risks -eq 0) {
        Test-Pass "Tier 2 fields default to 0"
    } else {
        Test-Fail "Tier 2 fields default to 0" "quality=$quality, confidence=$confidence, risks=$risks"
    }
} finally {
    Remove-Item -Path $dir10 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 11: Tier 2 fields pass through when present
# ============================================================================
Write-Host ""
Write-Host "Test 11: Tier 2 fields pass through when present" -ForegroundColor Cyan

$dir11 = New-TestDir
try {
    # Create cache file with Tier 2 fields
    $stateDir = Join-Path $dir11 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $cacheContent = @{
        version = 1
        overall_quality = 4
        confidence = 85
        critical_risks = @("missing error handling")
        docs = @{
            PRD = @{ one_liner = "test"; paragraph = "" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value $cacheContent -Encoding UTF8

    $result = Get-SnapshotData $dir11
    $quality = $result.LibrarianOverallQuality
    $confidence = $result.LibrarianConfidence
    $risks = $result.LibrarianCriticalRisksCount

    if ($quality -eq 4 -and $confidence -eq 85 -and $risks -eq 1) {
        Test-Pass "Tier 2 fields pass through correctly"
    } else {
        Test-Fail "Tier 2 fields pass through" "quality=$quality, confidence=$confidence, risks=$risks"
    }
} finally {
    Remove-Item -Path $dir11 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 12: Tier 2 values are clamped to valid ranges
# ============================================================================
Write-Host ""
Write-Host "Test 12: Tier 2 values are clamped to valid ranges" -ForegroundColor Cyan

$dir12 = New-TestDir
try {
    # Create cache file with out-of-range values
    $stateDir = Join-Path $dir12 "control\state"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

    $cacheContent = @{
        version = 1
        overall_quality = 10  # Should clamp to 5
        confidence = 200      # Should clamp to 100
        critical_risks = @()
        docs = @{
            PRD = @{ one_liner = ""; paragraph = "" }
            SPEC = @{ one_liner = ""; paragraph = "" }
            DECISION_LOG = @{ one_liner = ""; paragraph = "" }
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path (Join-Path $stateDir "librarian_doc_feedback.json") -Value $cacheContent -Encoding UTF8

    $result = Get-SnapshotData $dir12
    $quality = $result.LibrarianOverallQuality
    $confidence = $result.LibrarianConfidence

    if ($quality -eq 5 -and $confidence -eq 100) {
        Test-Pass "Tier 2 values clamped correctly (quality=5, confidence=100)"
    } else {
        Test-Fail "Tier 2 clamping" "quality=$quality (expected 5), confidence=$confidence (expected 100)"
    }
} finally {
    Remove-Item -Path $dir12 -Recurse -Force -ErrorAction SilentlyContinue
}

# ============================================================================
# Test 13: Get-DocsReadinessLevel returns correct tiers
# ============================================================================
Write-Host ""
Write-Host "Test 13: Get-DocsReadinessLevel returns correct tiers" -ForegroundColor Cyan

# Test BLOCKED: DocsAllPassed = false
$snap1 = [UiSnapshot]::new()
$snap1.DocsAllPassed = $false
$level1 = Get-DocsReadinessLevel -Snapshot $snap1

# Test PASS: DocsAllPassed = true, no Librarian data
$snap2 = [UiSnapshot]::new()
$snap2.DocsAllPassed = $true
$snap2.LibrarianOverallQuality = 0
$snap2.LibrarianConfidence = 0
$level2 = Get-DocsReadinessLevel -Snapshot $snap2

# Test REVIEW: Has critical risks
$snap3 = [UiSnapshot]::new()
$snap3.DocsAllPassed = $true
$snap3.LibrarianOverallQuality = 3
$snap3.LibrarianConfidence = 70
$snap3.LibrarianCriticalRisksCount = 2
$level3 = Get-DocsReadinessLevel -Snapshot $snap3

# Test PASS+: High quality + high confidence
$snap4 = [UiSnapshot]::new()
$snap4.DocsAllPassed = $true
$snap4.LibrarianOverallQuality = 4
$snap4.LibrarianConfidence = 85
$snap4.LibrarianCriticalRisksCount = 0
$level4 = Get-DocsReadinessLevel -Snapshot $snap4

$allCorrect = ($level1 -eq "BLOCKED") -and ($level2 -eq "PASS") -and ($level3 -eq "REVIEW") -and ($level4 -eq "PASS+")

if ($allCorrect) {
    Test-Pass "Get-DocsReadinessLevel returns correct tiers"
} else {
    Test-Fail "Get-DocsReadinessLevel" "BLOCKED=$level1, PASS=$level2, REVIEW=$level3, PASS+=$level4"
}

# ============================================================================
# Test 14: B1 - DOCS header shows L:x/5 when Librarian data present
# ============================================================================
Write-Host ""
Write-Host "Test 14: DOCS header shows L:x/5 indicator when present" -ForegroundColor Cyan

# No Librarian data: header is just "DOCS"
$snap14a = [UiSnapshot]::new()
$snap14a.LibrarianOverallQuality = 0
$snap14a.LibrarianConfidence = 0
$directives14a = Get-DocsRightColumn -Snapshot $snap14a

# With Librarian data: header shows "DOCS L:4/5"
$snap14b = [UiSnapshot]::new()
$snap14b.LibrarianOverallQuality = 4
$snap14b.LibrarianConfidence = 85
$directives14b = Get-DocsRightColumn -Snapshot $snap14b

$header14a = $directives14a[0].Text
$header14b = $directives14b[0].Text

if ($header14a -eq "DOCS" -and $header14b -match "DOCS L:4/5") {
    Test-Pass "DOCS header shows L:x/5 when Librarian data present"
} else {
    Test-Fail "DOCS header L:x/5" "no-data='$header14a', with-data='$header14b'"
}

# ============================================================================
# Test 15: B1 - DOCS header shows ! for critical risks
# ============================================================================
Write-Host ""
Write-Host "Test 15: DOCS header shows ! for critical risks" -ForegroundColor Cyan

$snap15 = [UiSnapshot]::new()
$snap15.LibrarianOverallQuality = 3
$snap15.LibrarianConfidence = 70
$snap15.LibrarianCriticalRisksCount = 2
$directives15 = Get-DocsRightColumn -Snapshot $snap15
$header15 = $directives15[0].Text

if ($header15 -match "L:3/5!") {
    Test-Pass "DOCS header shows ! for critical risks"
} else {
    Test-Fail "DOCS header !" "Expected L:3/5!, got '$header15'"
}

# ============================================================================
# Test 16: B1 - DOCS header shows * for stale data
# ============================================================================
Write-Host ""
Write-Host "Test 16: DOCS header shows * for stale data" -ForegroundColor Cyan

$snap16 = [UiSnapshot]::new()
$snap16.LibrarianOverallQuality = 4
$snap16.LibrarianConfidence = 80
$snap16.LibrarianCriticalRisksCount = 0
$snap16.LibrarianDocFeedbackStale = $true
$directives16 = Get-DocsRightColumn -Snapshot $snap16
$header16 = $directives16[0].Text

if ($header16 -match "L:4/5\*") {
    Test-Pass "DOCS header shows * for stale data"
} else {
    Test-Fail "DOCS header *" "Expected L:4/5*, got '$header16'"
}

# ============================================================================
# Test 17: B2 - DOCS header shows (PASS+) for high quality + confidence
# ============================================================================
Write-Host ""
Write-Host "Test 17: DOCS header shows (PASS+) for high quality" -ForegroundColor Cyan

$snap17 = [UiSnapshot]::new()
$snap17.DocsAllPassed = $true
$snap17.LibrarianOverallQuality = 4
$snap17.LibrarianConfidence = 85
$snap17.LibrarianCriticalRisksCount = 0
$directives17 = Get-DocsRightColumn -Snapshot $snap17
$header17 = $directives17[0].Text

if ($header17 -match "L:4/5.*\(PASS\+\)") {
    Test-Pass "DOCS header shows (PASS+) for high quality"
} else {
    Test-Fail "DOCS header (PASS+)" "Expected L:4/5 (PASS+), got '$header17'"
}

# ============================================================================
# Test 18: B2 - DOCS header shows (REVIEW) when risks > 0
# ============================================================================
Write-Host ""
Write-Host "Test 18: DOCS header shows (REVIEW) when risks > 0" -ForegroundColor Cyan

$snap18 = [UiSnapshot]::new()
$snap18.DocsAllPassed = $true
$snap18.LibrarianOverallQuality = 3
$snap18.LibrarianConfidence = 70
$snap18.LibrarianCriticalRisksCount = 2
$directives18 = Get-DocsRightColumn -Snapshot $snap18
$header18 = $directives18[0].Text

if ($header18 -match "L:3/5!.*\(REVIEW\)") {
    Test-Pass "DOCS header shows (REVIEW) when risks > 0"
} else {
    Test-Fail "DOCS header (REVIEW)" "Expected L:3/5! (REVIEW), got '$header18'"
}

# ============================================================================
# Test 19: B2 - DOCS header shows (PASS) when confidence < 50
# ============================================================================
Write-Host ""
Write-Host "Test 19: DOCS header shows (PASS) when confidence < 50" -ForegroundColor Cyan

$snap19 = [UiSnapshot]::new()
$snap19.DocsAllPassed = $true
$snap19.LibrarianOverallQuality = 2
$snap19.LibrarianConfidence = 40  # Below 50 threshold
$snap19.LibrarianCriticalRisksCount = 0
$directives19 = Get-DocsRightColumn -Snapshot $snap19
$header19 = $directives19[0].Text

if ($header19 -match "L:2/5.*\(PASS\)") {
    Test-Pass "DOCS header shows (PASS) when confidence < 50"
} else {
    Test-Fail "DOCS header (PASS)" "Expected L:2/5 (PASS), got '$header19'"
}

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
