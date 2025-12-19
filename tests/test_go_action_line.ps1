#!/usr/bin/env pwsh
# Regression tests for /go action line formatting helpers.

param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot ".." "control_panel.ps1")
)

$ErrorActionPreference = "Stop"

$content = Get-Content $ScriptPath -Raw

# Extract only the helper functions (avoid running main loop)
$start = $content.IndexOf("function Format-GoActionLine")
$end = $content.IndexOf("function Invoke-Continue")

if ($start -lt 0 -or $end -le $start) {
    Write-Host "FAIL: formatting helpers not found" -ForegroundColor Red
    exit 1
}

$helpers = $content.Substring($start, $end - $start)

try {
    Invoke-Expression $helpers
}
catch {
    Write-Host "FAIL: could not load formatting helpers: $_" -ForegroundColor Red
    exit 1
}

$testsFailed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Name,
        [string]$Message = ""
    )

    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        if ($Message) { Write-Host "       $Message" -ForegroundColor Yellow }
        $script:testsFailed++
    }
}

$pickedLine = Format-GoActionLine -Status "OK" -Data @{ id = 12; lane = "backend"; reason = "rotation"; pointer = 5 }
Assert-True ($pickedLine -eq "Picked #12 lane=backend reason=rotation ptr=5 (try /explain 12)") "Picked line format" $pickedLine

$noWorkLine = Format-GoActionLine -Status "NO_WORK" -Data @{ reason = "deps" }
Assert-True ($noWorkLine -eq "NO_WORK (reason=deps)") "NO_WORK line format" $noWorkLine

$blockedLine = Format-GoActionLine -Status "BLOCKED" -Data @{ reason = "read-only"; next = "disable read_only_mode" }
Assert-True ($blockedLine -eq "BLOCKED (read-only) Next: disable read_only_mode") "Blocked line format" $blockedLine

$reasonLane = Get-GoNoWorkReason -Result ([pscustomobject]@{ no_work_reason = "blocked_by_lanes"; pending_total = 0 }) -TotalTasks 5
Assert-True ($reasonLane -eq "lane") "Get-GoNoWorkReason lane" $reasonLane

$reasonDeps = Get-GoNoWorkReason -Result ([pscustomobject]@{ pending_total = 3 }) -TotalTasks 10
Assert-True ($reasonDeps -eq "deps") "Get-GoNoWorkReason deps" $reasonDeps

$reasonEmpty = Get-GoNoWorkReason -Result ([pscustomobject]@{ pending_total = 0 }) -TotalTasks 0
Assert-True ($reasonEmpty -eq "empty") "Get-GoNoWorkReason empty" $reasonEmpty

$reasonNone = Get-GoNoWorkReason -Result ([pscustomobject]@{ pending_total = 0 }) -TotalTasks 2
Assert-True ($reasonNone -eq "none") "Get-GoNoWorkReason none" $reasonNone

if ($testsFailed -gt 0) {
    Write-Host "Result: FAIL ($testsFailed failing test(s))" -ForegroundColor Red
    exit 1
}

Write-Host "Result: PASS" -ForegroundColor Green
exit 0
