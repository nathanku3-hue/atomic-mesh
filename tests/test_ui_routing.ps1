#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for 3-page UI flow routing and fallbacks.
.DESCRIPTION
    Verifies:
    - Routing is centralized via Set-Page
    - /go, /plan, /draft-plan set expected pages; refresh/help/ops do not flip pages
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

# 2) /go sets GO; refresh/help/ops do not flip pages
if ($content -match '"go"\s*\{[^\}]*Set-Page\s+"GO"') {
    Pass "/go routes to GO page"
} else {
    Fail "/go routes to GO page" "Expected Set-Page \"GO\" in go handler"
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

Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
