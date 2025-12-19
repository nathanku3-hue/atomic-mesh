#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Regression tests for screen routing UX improvements (v24.0)
.DESCRIPTION
    Verifies:
    - Tab key cycles between PLAN and GO screens
    - /accept-plan auto-switches to GO
    - Hint bar shows Tab for screen cycling
#>

$ErrorActionPreference = "Stop"
$testsFailed = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:testsFailed++
}

# Test KeyRouter
$keyRouterPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Public" "Invoke-KeyRouter.ps1"
if (Test-Path $keyRouterPath) {
    $keyRouterContent = Get-Content $keyRouterPath -Raw

    # 1) Tab key handled
    if ($keyRouterContent -match "'Tab'\s*\{") {
        Pass "Tab key handler exists in KeyRouter"
    } else {
        Fail "Tab key handler" "Expected 'Tab' case in KeyRouter switch"
    }

    # 2) Tab cycles PLAN <-> GO
    if ($keyRouterContent -match 'if \(\$State\.CurrentPage -eq "PLAN"\) \{ "GO" \} else \{ "PLAN" \}') {
        Pass "Tab cycles between PLAN and GO"
    } else {
        Fail "Tab cycling" "Expected PLAN/GO toggle logic for Tab"
    }
} else {
    Fail "KeyRouter file" "Invoke-KeyRouter.ps1 not found"
}

# Test CommandRouter
$cmdRouterPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Public" "Invoke-CommandRouter.ps1"
if (Test-Path $cmdRouterPath) {
    $cmdRouterContent = Get-Content $cmdRouterPath -Raw

    # 3) /accept-plan auto-switches to GO
    if ($cmdRouterContent -match '"accept-plan"\s*\{[\s\S]*?\$state\.CurrentPage = "GO"') {
        Pass "/accept-plan auto-switches to GO"
    } else {
        Fail "/accept-plan auto-switch" "Expected CurrentPage = 'GO' in accept-plan handler"
    }

    # 4) Toast confirms switch to GO
    if ($cmdRouterContent -match 'Plan accepted - switched to GO') {
        Pass "/accept-plan shows confirmation toast"
    } else {
        Fail "Accept-plan toast" "Expected 'Plan accepted - switched to GO' toast message"
    }
} else {
    Fail "CommandRouter file" "Invoke-CommandRouter.ps1 not found"
}

# Test Start-ControlPanel Tab handling
$controlPanelPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Public" "Start-ControlPanel.ps1"
if (Test-Path $controlPanelPath) {
    $panelContent = Get-Content $controlPanelPath -Raw

    # 5) Tab key in key dispatch list
    if ($panelContent -match '\[ConsoleKey\]::Tab') {
        Pass "Start-ControlPanel handles Tab key"
    } else {
        Fail "Tab in control panel" "Expected [ConsoleKey]::Tab in key dispatch"
    }
} else {
    Fail "ControlPanel file" "Start-ControlPanel.ps1 not found"
}

# Test hint bar - golden format uses mode badge and mode-specific hints
$renderCommonPath = Join-Path $PSScriptRoot ".." "src" "AtomicMesh.UI" "Private" "Render" "RenderCommon.ps1"
if (Test-Path $renderCommonPath) {
    $commonContent = Get-Content $renderCommonPath -Raw

    # 6) Hint bar uses golden format with mode badge
    if ($commonContent -match 'modeLabel' -and $commonContent -match '\[OPS\]|OPS.*Cyan') {
        Pass "Hint bar uses golden mode badge format"
    } else {
        Fail "Hint bar format" "Expected golden mode badge format in hint bar"
    }
} else {
    Fail "RenderCommon file" "RenderCommon.ps1 not found"
}

Write-Host ""
if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
