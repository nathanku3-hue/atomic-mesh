#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Acceptance tests for Doc Readiness Panel (P8) - Rated Bars
.DESCRIPTION
    Verifies the rated doc readiness panel in pre-draft state:
    - Format-ProgressBar computes correct MicroBar/percentage/color
    - Get-DocsDirectives returns bars with DocScores
    - Next: /draft-plan only when DocsAllPassed = true
    - Reducer does not call Test-Path or Get-ChildItem (no file I/O)
    - Fail-open behavior works correctly
.NOTES
    Run: pwsh tests/test_doc_readiness.ps1
    Exit 0 = pass, Exit 1 = fail
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Doc Readiness Panel Test (P8 - Rated Bars) ===" -ForegroundColor Cyan
Write-Host ""

# Dot-source the required files directly (internal classes not exported by module)
# PS5-compatible path joining (no multi-arg Join-Path)
$moduleRoot = Join-Path $PSScriptRoot ".."
$moduleRoot = Join-Path $moduleRoot "src"
$moduleRoot = Join-Path $moduleRoot "AtomicMesh.UI"
$files = @(
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Render/Console.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1'
)

foreach ($file in $files) {
    $fullPath = Join-Path $moduleRoot $file
    if (-not (Test-Path $fullPath)) {
        Write-Host "FAIL: Required file not found: $fullPath" -ForegroundColor Red
        exit 1
    }
    . $fullPath
}
Write-Host "Files loaded from: $moduleRoot" -ForegroundColor Gray

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
# Test 1: Format-ProgressBar computes correct bar for 60%
# ============================================================================
Write-Host ""
Write-Host "Test 1: Format-ProgressBar returns correct bar for 60%" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 60 -Threshold 80 -Exists $true
    # 60% of 5 = 3 filled blocks (Floor(60/100*5) = 3)
    $expectedBar = "■■■□□"
    $expectedPercent = " 60%"

    if ($bar.MicroBar -eq $expectedBar -and $bar.Percentage -eq $expectedPercent -and $bar.Color -eq "Yellow") {
        Test-Pass "Format-ProgressBar returns correct bar for 60%"
    } else {
        Test-Fail "Format-ProgressBar returns correct bar for 60%" "Got: bar='$($bar.MicroBar)', pct='$($bar.Percentage)', color='$($bar.Color)'"
    }
} catch {
    Test-Fail "Format-ProgressBar for 60%" $_.Exception.Message
}

# ============================================================================
# Test 2: Format-ProgressBar color: GREEN if score >= threshold
# ============================================================================
Write-Host ""
Write-Host "Test 2: Format-ProgressBar color: GREEN if score >= threshold" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 80 -Threshold 80 -Exists $true
    if ($bar.Color -eq "Green") {
        Test-Pass "80/80 threshold = Green"
    } else {
        Test-Fail "80/80 threshold = Green" "Got: $($bar.Color)"
    }
} catch {
    Test-Fail "Format-ProgressBar Green threshold" $_.Exception.Message
}

# ============================================================================
# Test 3: Format-ProgressBar color: RED if score < 50
# ============================================================================
Write-Host ""
Write-Host "Test 3: Format-ProgressBar color: RED if score < 50" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 30 -Threshold 80 -Exists $true
    if ($bar.Color -eq "Red") {
        Test-Pass "30/80 = Red"
    } else {
        Test-Fail "30/80 = Red" "Got: $($bar.Color)"
    }
} catch {
    Test-Fail "Format-ProgressBar Red" $_.Exception.Message
}

# ============================================================================
# Test 4: Format-ProgressBar 0% shows all empty blocks
# ============================================================================
Write-Host ""
Write-Host "Test 4: Format-ProgressBar 0% shows all empty blocks" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 0 -Threshold 80 -Exists $false
    $expectedBar = "□□□□□"
    if ($bar.MicroBar -eq $expectedBar -and $bar.StateLabel -eq "MISS") {
        Test-Pass "0% shows □□□□□ with MISS label"
    } else {
        Test-Fail "0% shows □□□□□ with MISS label" "Got: bar='$($bar.MicroBar)', label='$($bar.StateLabel)'"
    }
} catch {
    Test-Fail "Format-ProgressBar 0%" $_.Exception.Message
}

# ============================================================================
# Test 5: Format-ProgressBar 100% shows all filled blocks
# ============================================================================
Write-Host ""
Write-Host "Test 5: Format-ProgressBar 100% shows all filled blocks" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 100 -Threshold 80 -Exists $true
    $expectedBar = "■■■■■"
    if ($bar.MicroBar -eq $expectedBar -and $bar.Color -eq "Green") {
        Test-Pass "100% shows ■■■■■ in Green"
    } else {
        Test-Fail "100% shows ■■■■■ in Green" "Got: bar='$($bar.MicroBar)', color='$($bar.Color)'"
    }
} catch {
    Test-Fail "Format-ProgressBar 100%" $_.Exception.Message
}

# ============================================================================
# Test 6: Get-DocsDirectives returns bars with DocScores
# ============================================================================
Write-Host ""
Write-Host "Test 6: Get-DocsDirectives returns bars with scores" -ForegroundColor Cyan

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.DocScores = @{
        PRD = @{ score = 60; exists = $true; threshold = 80 }
        SPEC = @{ score = 20; exists = $true; threshold = 80 }
        DECISION_LOG = @{ score = 40; exists = $true; threshold = 30 }
    }
    $directives = Get-DocsDirectives -Snapshot $snapshot

    # PRD: 60% = 3 filled, Yellow (below 80% threshold)
    $prdMatch = $directives[0].Text -match "PRD.*■■■□□.*60%" -and $directives[0].Color -eq "Yellow"
    # SPEC: 20% = 1 filled, Red (below 50)
    $specMatch = $directives[1].Text -match "SPEC.*■□□□□.*20%" -and $directives[1].Color -eq "Red"
    # DEC: 40% = 2 filled, Green (40% >= 30% threshold)
    $decMatch = $directives[2].Text -match "DEC.*■■□□□.*40%" -and $directives[2].Color -eq "Green"

    if ($prdMatch -and $specMatch -and $decMatch) {
        Test-Pass "Get-DocsDirectives returns bars with scores"
    } else {
        Test-Fail "Get-DocsDirectives returns bars with scores" "PRD='$($directives[0].Text)/$($directives[0].Color)', SPEC='$($directives[1].Text)/$($directives[1].Color)', DEC='$($directives[2].Text)/$($directives[2].Color)'"
    }
} catch {
    Test-Fail "Get-DocsDirectives with DocScores" $_.Exception.Message
}

# ============================================================================
# Test 7: Next shows /draft-plan when all docs pass thresholds
# ============================================================================
Write-Host ""
Write-Host "Test 7: Next: /draft-plan when all docs pass thresholds" -ForegroundColor Cyan

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.DocScores = @{
        PRD = @{ score = 80; exists = $true; threshold = 80 }
        SPEC = @{ score = 80; exists = $true; threshold = 80 }
        DECISION_LOG = @{ score = 40; exists = $true; threshold = 30 }
    }
    $snapshot.DocsAllPassed = $true
    $snapshot.ReadinessMode = "live"
    $rightCol = Get-DocsRightColumn -Snapshot $snapshot

    if ($rightCol[5].Text -eq "Next: /draft-plan" -and $rightCol[5].Color -eq "Cyan") {
        Test-Pass "Next: /draft-plan when all docs pass thresholds"
    } else {
        Test-Fail "Next: /draft-plan when all docs pass thresholds" "Got: $($rightCol[5].Text) / $($rightCol[5].Color)"
    }
} catch {
    Test-Fail "Get-DocsRightColumn with all docs passing" $_.Exception.Message
}

# ============================================================================
# Test 8: Next shows 'Complete docs first' when below threshold
# ============================================================================
Write-Host ""
Write-Host "Test 8: Next shows 'Complete docs first' when below threshold" -ForegroundColor Cyan

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.DocScores = @{
        PRD = @{ score = 60; exists = $true; threshold = 80 }
        SPEC = @{ score = 20; exists = $true; threshold = 80 }
        DECISION_LOG = @{ score = 40; exists = $true; threshold = 30 }
    }
    $snapshot.DocsAllPassed = $false
    $snapshot.ReadinessMode = "live"
    $rightCol = Get-DocsRightColumn -Snapshot $snapshot

    if ($rightCol[5].Text -match "Complete docs first") {
        Test-Pass "Next shows 'Complete docs first' when below threshold"
    } else {
        Test-Fail "Next shows 'Complete docs first' when below threshold" "Got: $($rightCol[5].Text)"
    }
} catch {
    Test-Fail "Get-DocsRightColumn with docs below threshold" $_.Exception.Message
}

# ============================================================================
# Test 9: Reducer does not call Test-Path or Get-ChildItem
# ============================================================================
Write-Host ""
Write-Host "Test 9: Reducer has no file I/O calls" -ForegroundColor Cyan

# PS5-compatible path
$reducerPath = Join-Path $PSScriptRoot ".."
$reducerPath = Join-Path $reducerPath "src\AtomicMesh.UI\Private\Reducers\ComputePipelineStatus.ps1"
if (Test-Path $reducerPath) {
    $content = Get-Content $reducerPath -Raw
    $hasTestPath = $content -match '\bTest-Path\b'
    $hasGetChildItem = $content -match '\bGet-ChildItem\b'

    if (-not $hasTestPath -and -not $hasGetChildItem) {
        Test-Pass "Reducer has no Test-Path or Get-ChildItem calls"
    } else {
        $issues = @()
        if ($hasTestPath) { $issues += "Test-Path" }
        if ($hasGetChildItem) { $issues += "Get-ChildItem" }
        Test-Fail "Reducer has no file I/O" "Found: $($issues -join ', ')"
    }
} else {
    Test-Fail "Reducer file exists" "Not found: $reducerPath"
}

# ============================================================================
# Test 10: Fail-open mode shows cautious message
# ============================================================================
Write-Host ""
Write-Host "Test 10: Fail-open shows cautious message" -ForegroundColor Cyan

try {
    $snapshot = [UiSnapshot]::new()
    $snapshot.DocScores = @{
        PRD = @{ score = 80; exists = $true; threshold = 80 }
        SPEC = @{ score = 80; exists = $true; threshold = 80 }
        DECISION_LOG = @{ score = 40; exists = $true; threshold = 30 }
    }
    $snapshot.DocsAllPassed = $true
    $snapshot.ReadinessMode = "fail-open"  # Fail-open mode
    $rightCol = Get-DocsRightColumn -Snapshot $snapshot

    if ($rightCol[5].Text -match "may fail" -and $rightCol[5].Color -eq "DarkGray") {
        Test-Pass "Fail-open shows cautious message"
    } else {
        Test-Fail "Fail-open shows cautious message" "Got: $($rightCol[5].Text) / $($rightCol[5].Color)"
    }
} catch {
    Test-Fail "Get-DocsRightColumn in fail-open mode" $_.Exception.Message
}

# ============================================================================
# Test 11: Fit-Text helper truncates correctly
# ============================================================================
Write-Host ""
Write-Host "Test 11: Fit-Text truncation" -ForegroundColor Cyan

try {
    $short = Fit-Text -Text "Hello" -Width 10
    $long = Fit-Text -Text "This is a very long string" -Width 10

    if ($short -eq "Hello" -and $long -eq "This is..." -and $long.Length -eq 10) {
        Test-Pass "Fit-Text truncates with ellipsis"
    } else {
        Test-Fail "Fit-Text truncates with ellipsis" "Got short='$short', long='$long'"
    }
} catch {
    Test-Fail "Fit-Text helper" $_.Exception.Message
}

# ============================================================================
# Test 12: "may fail" message ONLY appears in fail-open mode
# ============================================================================
Write-Host ""
Write-Host "Test 12: 'may fail' only in fail-open mode" -ForegroundColor Cyan

try {
    # Live mode should NOT show "may fail"
    $snapshot = [UiSnapshot]::new()
    $snapshot.DocScores = @{
        PRD = @{ score = 80; exists = $true; threshold = 80 }
        SPEC = @{ score = 80; exists = $true; threshold = 80 }
        DECISION_LOG = @{ score = 40; exists = $true; threshold = 30 }
    }
    $snapshot.DocsAllPassed = $true
    $snapshot.ReadinessMode = "live"
    $rightCol = Get-DocsRightColumn -Snapshot $snapshot
    $liveText = $rightCol[5].Text

    # Fail-open mode SHOULD show "may fail"
    $snapshot.ReadinessMode = "fail-open"
    $rightCol = Get-DocsRightColumn -Snapshot $snapshot
    $failOpenText = $rightCol[5].Text

    $liveOk = $liveText -notmatch "may fail"
    $failOpenOk = $failOpenText -match "may fail"

    if ($liveOk -and $failOpenOk) {
        Test-Pass "'may fail' only in fail-open mode"
    } else {
        Test-Fail "'may fail' only in fail-open mode" "live='$liveText', fail-open='$failOpenText'"
    }
} catch {
    Test-Fail "'may fail' mode check" $_.Exception.Message
}

# ============================================================================
# Test 13: DECISION_LOG threshold is 30%, not 80%
# ============================================================================
Write-Host ""
Write-Host "Test 13: DECISION_LOG threshold is 30%" -ForegroundColor Cyan

try {
    # DEC at 30% should be GREEN (meets threshold)
    $bar = Format-ProgressBar -Score 30 -Threshold 30 -Exists $true
    if ($bar.Color -eq "Green") {
        Test-Pass "DEC at 30% meets 30% threshold = Green"
    } else {
        Test-Fail "DEC at 30% meets 30% threshold = Green" "Got: $($bar.Color)"
    }
} catch {
    Test-Fail "DECISION_LOG threshold" $_.Exception.Message
}

# ============================================================================
# Test 14: Edge case - 99% shows ■■■■□ (Floor rounding)
# ============================================================================
Write-Host ""
Write-Host "Test 14: Edge case - 99% shows ■■■■□ (Floor)" -ForegroundColor Cyan

try {
    $bar = Format-ProgressBar -Score 99 -Threshold 80 -Exists $true
    # Floor(99/100*5) = Floor(4.95) = 4 filled blocks
    $expectedBar = "■■■■□"
    if ($bar.MicroBar -eq $expectedBar -and $bar.Color -eq "Green") {
        Test-Pass "99% shows ■■■■□ (Floor rounding)"
    } else {
        Test-Fail "99% shows ■■■■□ (Floor rounding)" "Got: bar='$($bar.MicroBar)', color='$($bar.Color)'"
    }
} catch {
    Test-Fail "99% edge case" $_.Exception.Message
}

# ============================================================================
# Test 15: exists=false still shows bar with score but MISS label
# ============================================================================
Write-Host ""
Write-Host "Test 15: exists=false shows bar with MISS label" -ForegroundColor Cyan

try {
    # File doesn't exist but has a score (e.g., cached or computed)
    $bar = Format-ProgressBar -Score 60 -Threshold 80 -Exists $false
    # Should show bar based on score, but label is MISS
    $expectedBar = "■■■□□"
    if ($bar.MicroBar -eq $expectedBar -and $bar.StateLabel -eq "MISS") {
        Test-Pass "exists=false: bar shows score, label is MISS"
    } else {
        Test-Fail "exists=false: bar shows score, label is MISS" "Got: bar='$($bar.MicroBar)', label='$($bar.StateLabel)'"
    }
} catch {
    Test-Fail "exists=false semantics" $_.Exception.Message
}

# ============================================================================
# Test 16: Get-DocsDirectives handles missing DocScores gracefully
# ============================================================================
Write-Host ""
Write-Host "Test 16: Get-DocsDirectives handles missing DocScores" -ForegroundColor Cyan

try {
    # Create snapshot WITHOUT DocScores (simulates old object or adapter error)
    $snapshot = [UiSnapshot]::new()
    # Don't set DocScores - let it use defaults
    $snapshot.DocScores = $null

    $directives = Get-DocsDirectives -Snapshot $snapshot

    # Should return 3 directives with 0% empty bars (fail-open defaults)
    $allEmpty = $true
    foreach ($d in $directives) {
        if ($d.Text -notmatch "□□□□□.*0%") {
            $allEmpty = $false
            break
        }
    }
    if ($allEmpty -and $directives.Count -eq 3) {
        Test-Pass "Missing DocScores defaults to 0% empty bars"
    } else {
        Test-Fail "Missing DocScores defaults to 0% empty bars" "Got: $($directives | ForEach-Object { $_.Text } | Join-String -Separator ', ')"
    }
} catch {
    Test-Fail "Missing DocScores handling" $_.Exception.Message
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
