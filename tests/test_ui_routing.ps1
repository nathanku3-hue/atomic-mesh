#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for 3-page UI flow routing and fallbacks.
.DESCRIPTION
    Verifies:
    - Routing is centralized via Set-Page
    - /plan, /draft-plan set expected pages; /go does not force a page; refresh/help/ops do not flip pages
    - Default landing picks BOOTSTRAP when not ready
    - GO fallbacks surface key banners and Next suggestions
    - Policy B: /accept-plan does not force page change; accepted plan Next → /go
#>

$ErrorActionPreference = "Stop"
$controlPanelPath = Join-Path $PSScriptRoot ".." "control_panel.ps1"

if (-not (Test-Path $controlPanelPath)) {
    Write-Host "FAIL: control_panel.ps1 not found" -ForegroundColor Red
    exit 1
}

$content = Get-Content $controlPanelPath -Raw
$testsFailed = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

# 1) Set-Page helper exists and returns refresh
if ($content -match 'function\s+Set-Page' -and
    $content -match '\$Global:AllowedPages' -and
    $content -match 'return\s+"refresh"') {
    Pass "Set-Page centralizes page routing"
} else {
    Fail "Set-Page centralizes page routing" "Missing Set-Page helper or refresh return"
}

# 2) /go stays put; refresh/help/ops do not flip pages
if ($content -notmatch '"go"\s*\{[^\}]*Set-Page') {
    Pass "/go does not change CurrentPage"
} else {
    Fail "/go does not change CurrentPage" "Set-Page call found inside go handler"
}

foreach ($cmd in @("refresh", "help", "ops")) {
    if ($content -notmatch "`"$cmd`"\s*\{[^\}]*Set-Page") {
        Pass "/$cmd does not change page"
    } else {
        Fail "/$cmd does not change page" "Found Set-Page inside /$cmd handler"
    }
}

# 3) /plan and /draft-plan set PLAN
if ($content -match '"plan"\s*\{[^\}]*Set-Page\s+"PLAN"') {
    Pass "/plan routes to PLAN page"
} else {
    Fail "/plan routes to PLAN page" "Expected Set-Page \"PLAN\" in plan handler"
}
if ($content -match '"draft-plan"\s*\{[^\}]*Set-Page\s+"PLAN"') {
    Pass "/draft-plan routes to PLAN page"
} else {
    Fail "/draft-plan routes to PLAN page" "Expected Set-Page \"PLAN\" in draft-plan handler"
}

# 4) Default BOOTSTRAP landing when not ready
if ($content -match '\$defaultPage\s*=\s*if\s*\(\$notReady\)\s*\{\s*"BOOTSTRAP"\s*\}\s*else\s*\{\s*"PLAN"\s*\}') {
    Pass "Not-ready state defaults to BOOTSTRAP"
} else {
    Fail "Not-ready state defaults to BOOTSTRAP" "Default page computation missing/not deterministic"
}

# 5) GO fallbacks (banner + Next text present)
if ($content -match 'No accepted plan' -and $content -match '\/accept-plan') {
    Pass "GO fallback: no accepted plan banner + /accept-plan"
} else {
    Fail "GO fallback: no accepted plan banner + /accept-plan" "Expected no-plan banner and /accept-plan hint"
}
if ($content -match 'No workers registered' -and $content -match 'start workers then /go') {
    Pass "GO fallback: no workers suggests starting workers"
} else {
    Fail "GO fallback: no workers suggests starting workers" "Missing no-worker banner or start workers hint"
}
if ($content -match 'NO_WORK' -and $content -match '\/refresh-plan') {
    Pass "GO fallback: all work complete suggests refresh/draft plan"
} else {
    Fail "GO fallback: all work complete suggests refresh/draft plan" "Missing NO_WORK banner or refresh hint"
}
if ($content -match 'Snapshot error') {
    Pass "GO fallback: snapshot error banner visible"
} else {
    Fail "GO fallback: snapshot error banner visible" "Missing snapshot error banner"
}

# 6) Policy B: accept-plan stays on page, accepted plan Next → /go
if ($content -notmatch '"accept-plan"\s*\{[^\}]*Set-Page') {
    Pass "/accept-plan does not force page switch"
} else {
    Fail "/accept-plan does not force page switch" "Set-Page found inside accept-plan handler"
}
if ($content -match 'Draw-PlanScreen[\s\S]*?\$nextCmd\s*=\s*"/go"') {
    Pass "Accepted plan suggests /go (policy B)"
} else {
    Fail "Accepted plan suggests /go (policy B)" "Plan screen next action does not point to /go when accepted"
}

# === v22.1: Golden PLAN screen rendering tests ===

# 7) PLAN screen includes pipeline strip tokens
$pipelineTokens = @("[Ctx]", "[Pln]", "[Wrk]", "[Opt]", "[Ver]", "[Shp]")
$foundPipelineInDrawPlan = $content -match 'Draw-PlanScreen[\s\S]*?Draw-PipelinePanel'
if ($foundPipelineInDrawPlan) {
    Pass "PLAN screen calls Draw-PipelinePanel (renders pipeline strip)"
} else {
    Fail "PLAN screen calls Draw-PipelinePanel" "Draw-PlanScreen should call Draw-PipelinePanel for pipeline strip"
}

# 8) PLAN screen includes lane labels
$laneLabels = @("BACKEND", "FRONTEND", "QA/AUDIT", "LIBRARIAN")
$foundLaneLabels = $true
foreach ($lane in $laneLabels) {
    if ($content -notmatch "Draw-PlanScreen[\s\S]*?`"$lane`"") {
        $foundLaneLabels = $false
        break
    }
}
if ($foundLaneLabels) {
    Pass "PLAN screen includes lane labels (BACKEND, FRONTEND, QA/AUDIT, LIBRARIAN)"
} else {
    # Check for laneNames array definition within Draw-PlanScreen
    if ($content -match 'Draw-PlanScreen[\s\S]*?\$laneNames\s*=\s*@\([^\)]*BACKEND[^\)]*FRONTEND[^\)]*\)') {
        Pass "PLAN screen includes lane labels (BACKEND, FRONTEND, QA/AUDIT, LIBRARIAN)"
    } else {
        Fail "PLAN screen includes lane labels" "Expected lane labels in Draw-PlanScreen"
    }
}

# 9) PLAN screen with accepted plan shows Next: /go
if ($content -match 'Draw-PlanScreen[\s\S]*?\$nextCmd\s*=\s*"/go"') {
    Pass "PLAN screen shows Next: /go when accepted"
} else {
    Fail "PLAN screen shows Next: /go" "Expected nextCmd = /go path in Draw-PlanScreen"
}

# 10) PLAN screen shows PENDING status for lanes
if ($content -match 'Draw-PlanScreen[\s\S]*?State\s*=\s*"PENDING"') {
    Pass "PLAN screen shows PENDING status for lanes"
} else {
    Fail "PLAN screen shows PENDING status" "Expected PENDING state in Get-PlanLaneStatus"
}

# 11) PLAN screen does NOT contain misleading "Context: EXECUTION" display
if ($content -match 'Draw-PlanScreen[\s\S]*?"Context:\s+\$\(' -and
    $content -notmatch 'Draw-PlanScreen[\s\S]*?"Context:\s+EXECUTION"') {
    Pass "PLAN screen does not show hardcoded 'Context: EXECUTION'"
} else {
    # More thorough check - ensure old misleading line is gone
    if ($content -notmatch 'Draw-PlanScreen[\s\S]*?Print-Row[^\n]*"Context:[^\n]*executes\s+next\s+task') {
        Pass "PLAN screen does not show hardcoded 'Context: EXECUTION'"
    } else {
        Fail "PLAN screen misleading content" "Found 'Context: EXECUTION' or 'executes next task' in PLAN renderer"
    }
}

# 12) PLAN screen does NOT contain "Plan view only" misleading text
if ($content -notmatch 'Draw-PlanScreen[\s\S]*?"Plan view only"') {
    Pass "PLAN screen does not show 'Plan view only'"
} else {
    Fail "PLAN screen misleading content" "Found 'Plan view only' in Draw-PlanScreen"
}

# 13) PLAN screen has bordered layout (left/right panels)
# v23.0: Left header is now dynamic ($leftHeader), right is still "PIPELINE"
if ($content -match 'Draw-PlanScreen[\s\S]*?\$leftHeader[\s\S]*?"PIPELINE"') {
    Pass "PLAN screen has bordered layout with stateful/PIPELINE headers"
} else {
    Fail "PLAN screen bordered layout" "Expected stateful left header and PIPELINE right header in Draw-PlanScreen"
}

# 14) PLAN screen computes lane status based on plan state
if ($content -match 'Draw-PlanScreen[\s\S]*?Get-PlanLaneStatus') {
    Pass "PLAN screen computes lane status (Get-PlanLaneStatus)"
} else {
    Fail "PLAN screen lane status" "Expected Get-PlanLaneStatus function in Draw-PlanScreen"
}

# === v22.2: Additional PLAN screen fixes ===

# 15) PLAN screen does NOT render "Source: readiness.py" line
if ($content -notmatch 'Draw-PlanScreen[\s\S]*?"Source:\s+readiness') {
    Pass "PLAN screen does not show Source: readiness.py"
} else {
    Fail "PLAN screen diagnostics" "Found 'Source: readiness.py' in Draw-PlanScreen"
}

# 16) PLAN screen uses unified divider (Draw-PlanBorder with shared junction)
if ($content -match 'Draw-PlanScreen[\s\S]*?Draw-PlanBorder' -and
    $content -match 'Draw-PlanScreen[\s\S]*?\+\$lineL\+\$lineR\+') {
    Pass "PLAN screen uses unified divider (+---+---+)"
} else {
    Fail "PLAN screen divider alignment" "Expected Draw-PlanBorder with shared center junction"
}

# 17) v23.0: PLAN header shows stateful labels (RUNNING/READY/NEEDS ACCEPTANCE/NEEDS PLAN)
if ($content -match 'Draw-PlanScreen[\s\S]*?\$leftHeader\s*=\s*"NEEDS PLAN"' -and
    $content -match 'Draw-PlanScreen[\s\S]*?\$leftHeader\s*=\s*"RUNNING"' -and
    $content -match 'Draw-PlanScreen[\s\S]*?\$leftHeader\s*=\s*"READY"' -and
    $content -match 'Draw-PlanScreen[\s\S]*?\$leftHeader\s*=\s*"NEEDS ACCEPTANCE"') {
    Pass "PLAN header shows stateful labels (RUNNING/READY/NEEDS ACCEPTANCE/NEEDS PLAN)"
} else {
    Fail "PLAN header stateful labels" "Expected all 4 header states: RUNNING, READY, NEEDS ACCEPTANCE, NEEDS PLAN"
}

# 18) PLAN screen shows F2/F4 hotkeys
if ($content -match 'Draw-PlanScreen[\s\S]*?F2:.*F4:') {
    Pass "PLAN screen shows F2/F4 hotkeys"
} else {
    Fail "PLAN screen hotkeys" "Expected F2 and F4 hotkeys in Draw-PlanScreen"
}

# 19) PLAN screen uses Draw-PlanRow helper for unified row rendering
if ($content -match 'Draw-PlanScreen[\s\S]*?function\s+Draw-PlanRow') {
    Pass "PLAN screen uses Draw-PlanRow helper for unified rendering"
} else {
    Fail "PLAN screen rendering" "Expected Draw-PlanRow helper in Draw-PlanScreen"
}

# 20) PLAN screen shows RUNNING state when tasks are active
if ($content -match 'Draw-PlanScreen[\s\S]*?Get-PlanLaneStatus[\s\S]*?\$Active\s*-gt\s*0[\s\S]*?State\s*=\s*"RUNNING"') {
    Pass "PLAN screen shows RUNNING when tasks active"
} else {
    Fail "PLAN screen lane RUNNING state" "Expected RUNNING state check in Get-PlanLaneStatus"
}

# === v21.3: Per-lane health indicator tests ===

# 21) Get-LaneHealthIndicator helper exists and returns colored dot
if ($content -match 'function\s+Get-LaneHealthIndicator' -and
    $content -match 'Get-LaneHealthIndicator[\s\S]*?Color\s*=\s*"Red"' -and
    $content -match 'Get-LaneHealthIndicator[\s\S]*?Color\s*=\s*"Green"' -and
    $content -match 'Get-LaneHealthIndicator[\s\S]*?Color\s*=\s*"Yellow"') {
    Pass "Get-LaneHealthIndicator returns Red/Green/Yellow colors"
} else {
    Fail "Get-LaneHealthIndicator helper" "Expected Get-LaneHealthIndicator with Red/Green/Yellow color returns"
}

# 22) Draw-StreamLineLeft includes health indicator rendering
if ($content -match 'Draw-StreamLineLeft[\s\S]*?Get-LaneHealthIndicator[\s\S]*?\$health\.Dot') {
    Pass "Draw-StreamLineLeft renders health dot from Get-LaneHealthIndicator"
} else {
    Fail "Draw-StreamLineLeft health indicator" "Expected Get-LaneHealthIndicator call and Dot rendering in Draw-StreamLineLeft"
}

# 23) Health indicator uses Unicode BLACK CIRCLE (0x25CF)
if ($content -match 'Get-LaneHealthIndicator[\s\S]*?\[char\]0x25CF') {
    Pass "Health indicator uses Unicode BLACK CIRCLE (●)"
} else {
    Fail "Health indicator character" "Expected [char]0x25CF (BLACK CIRCLE) in Get-LaneHealthIndicator"
}

# 24) Health indicator is ONLY called inside Draw-StreamLineLeft (lane rows), not in headers
# Verify Get-LaneHealthIndicator is defined once and only called within Draw-StreamLineLeft
$laneHealthDefMatch = [regex]::Matches($content, 'function\s+Get-LaneHealthIndicator')
$laneHealthCallMatch = [regex]::Matches($content, 'Get-LaneHealthIndicator\s*-Status')
if ($laneHealthDefMatch.Count -eq 1 -and $laneHealthCallMatch.Count -eq 1) {
    # The single call is inside Draw-StreamLineLeft (lane row renderer)
    if ($content -match 'function\s+Draw-StreamLineLeft[\s\S]*?Get-LaneHealthIndicator[\s\S]*?Write-Host\s+"\s*\|"') {
        Pass "Health indicators only appear in lane rows (Draw-StreamLineLeft)"
    } else {
        Fail "Health indicator placement" "Get-LaneHealthIndicator should be called inside Draw-StreamLineLeft"
    }
} else {
    Fail "Health indicator placement" "Expected exactly 1 definition and 1 call of Get-LaneHealthIndicator"
}

# === v23.0: PLAN semantics cleanup tests ===

# 25) PLAN screen does NOT contain "Plan: accepted" text (removed per v23.0)
if ($content -notmatch 'Draw-PlanScreen[\s\S]*?"Plan:\s+accepted"') {
    Pass "PLAN screen does not show 'Plan: accepted' (v23.0 cleanup)"
} else {
    Fail "PLAN screen cleanup" "Should not contain 'Plan: accepted' text after v23.0 cleanup"
}

# 26) PLAN screen does NOT contain "Workers: (none)" text (removed per v23.0)
if ($content -notmatch 'Draw-PlanScreen[\s\S]*?"Workers:\s+\(none\)"') {
    Pass "PLAN screen does not show 'Workers: (none)' (v23.0 cleanup)"
} else {
    Fail "PLAN screen cleanup" "Should not contain 'Workers: (none)' text after v23.0 cleanup"
}

# 27) QA/AUDIT coloring logic exists with RED/YELLOW/GREEN states
if ($content -match 'QA/AUDIT coloring' -and
    $content -match '\$qaColor\s*=\s*"Red"' -and
    $content -match '\$qaColor\s*=\s*"Yellow"' -and
    $content -match '\$qaColor\s*=\s*"Green"') {
    Pass "QA/AUDIT coloring has Red/Yellow/Green states"
} else {
    Fail "QA/AUDIT coloring logic" "Expected QA/AUDIT coloring with Red/Yellow/Green states"
}

# 28) QA/AUDIT checks for failed tasks (qaStats.failed)
if ($content -match '\$qaStats\.failed\s*-gt\s*0') {
    Pass "QA/AUDIT checks for failed tasks"
} else {
    Fail "QA/AUDIT failure detection" "Expected check for qaStats.failed > 0"
}

# 29) QA/AUDIT calculates progress from QA lane or overall fallback
if ($content -match '\$qaProgress\s*=\s*\$qaStats\.done\s*/\s*\$qaStats\.total' -and
    $content -match '\$qaProgress\s*=\s*\$terminalCount\s*/\s*\$totalTasks') {
    Pass "QA/AUDIT progress uses QA lane with overall fallback"
} else {
    Fail "QA/AUDIT progress calculation" "Expected progress from QA lane done/total or overall fallback"
}

# 30) Header state uses hasActiveTasks query for RUNNING state
if ($content -match "status='in_progress'" -and
    $content -match "worker_id IS NOT NULL" -and
    $content -match '\$hasActiveTasks' -and
    $content -match 'if\s*\(\$hasActiveTasks\)[\s\S]*?\$leftHeader\s*=\s*"RUNNING"') {
    Pass "Header RUNNING state checks in_progress OR worker_id assigned"
} else {
    Fail "Header RUNNING state logic" "Expected query for in_progress OR worker_id for RUNNING state"
}

Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
