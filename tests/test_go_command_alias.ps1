#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression checks for the execution loop command (/go).
.DESCRIPTION
    - /go keeps the short alias (/g)
    - /accept-plan appears in Golden Path help
    - Suggested Next does not point to missing /unblock
    - Slash-command dispatch no longer blocks aliases at the top level
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

# 1) /go keeps /g alias
if ($content -match '"go"\s*=\s*@\{[^}]*Alias\s*=\s*@\([^\)]*\bg\b') {
    Pass "/go includes /g alias"
} else {
    Fail "/go includes /g alias" "Alias list missing 'g'"
}

# 2) Golden Path help shows /accept-plan
if ($content -match '\$goldenPath\s*=\s*@\([^)]*accept-plan') {
    Pass "/accept-plan included in Golden Path commands"
} else {
    Fail "/accept-plan included in Golden Path commands" "Golden Path list should contain accept-plan"
}

# 3) Suggested Next does not point to missing /unblock
if ($content -notmatch '/unblock') {
    Pass "Next hint no longer references /unblock"
} else {
    Fail "Next hint no longer references /unblock" "Found legacy /unblock suggestion"
}

# 4) Slash command dispatch runs through Invoke-SlashCommand (alias-friendly)
if ($content -match 'if\s*\(\s*\$userInput\.StartsWith\(\"/\"\)\s*\)\s*\{[\s\S]*Invoke-SlashCommand\s*-UserInput\s+\$userInput') {
    Pass "Slash input dispatches via Invoke-SlashCommand"
} else {
    Fail "Slash input dispatches via Invoke-SlashCommand" "Could not find alias-friendly dispatch"
}

# 5) No top-level /$cmdName unknown guard
if ($content -notmatch 'Unknown command: /\$cmdName') {
    Pass "Top-level unknown guard removed (aliases allowed)"
} else {
    Fail "Top-level unknown guard removed (aliases allowed)" "Found legacy /$cmdName unknown guard"
}

if ($testsFailed -gt 0) {
    Write-Host "`nResult: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "`nResult: PASS" -ForegroundColor Green
exit 0
