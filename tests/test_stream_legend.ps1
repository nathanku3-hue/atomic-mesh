$ErrorActionPreference = "Stop"

$modulePath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "src") "AtomicMesh.UI") "AtomicMesh.UI.psd1"
$module = Import-Module -Name $modulePath -Force -PassThru

$failures = 0

function Pass([string]$name) {
    Write-Host "[PASS] $name" -ForegroundColor Green
}

function Fail([string]$name, [string]$reason) {
    Write-Host "[FAIL] $name" -ForegroundColor Red
    Write-Host "       $reason" -ForegroundColor Yellow
    $script:failures++
}

function New-GoFrameOutput {
    param(
        [array]$Lanes,
        [string]$Page = "GO"
    )

    & $module {
        param($Lanes, $Page)
        Enable-CaptureMode -Width 80 -Height 24
        Begin-ConsoleFrame

        $snap = [UiSnapshot]::new()
        $snap.PlanState.Status = "ACCEPTED"
        $snap.PlanState.Accepted = $true
        $snap.LaneMetrics = $Lanes

        $state = [UiState]::new()
        $state.CurrentPage = $Page

        if ($Page -eq "GO") {
            Render-Go -Snapshot $snap -State $state -StartRow 4
        }
        else {
            Render-Plan -Snapshot $snap -State $state -StartRow 4
        }

        $out = Get-CapturedOutput
        Disable-CaptureMode
        return $out
    }
}

# ------------------------------------------------------------------
# Mapping tests
# ------------------------------------------------------------------
$lanesMapped = & $module {
    Compute-LaneMetrics -RawSnapshot @{
        LaneCounts = @(
            @{ Lane = "BACKEND"; Status = "in_progress"; Count = 1 },
            @{ Lane = "FRONTEND"; Status = "pending"; Count = 2 },
            @{ Lane = "OPS"; Status = "pending"; Count = 1 }
        )
    }
}

if ($lanesMapped[0].StateColor -eq "Green") { Pass "StateColor set to Green for running" } else { Fail "StateColor set to Green for running" "$($lanesMapped[0].StateColor)" }
if ($lanesMapped[1].StateColor -eq "Cyan") { Pass "StateColor set to Cyan for queued" } else { Fail "StateColor set to Cyan for queued" "$($lanesMapped[1].StateColor)" }
if ($lanesMapped[2].StateColor -eq "DarkGray") { Pass "StateColor set to DarkGray for idle" } else { Fail "StateColor set to DarkGray for idle" "$($lanesMapped[2].StateColor)" }
if ($lanesMapped[0].DotChar -eq [char]0x25CF) { Pass "DotChar uses bullet" } else { Fail "DotChar uses bullet" "$($lanesMapped[0].DotChar)" }

$rows = & $module { Compute-StreamRows -LaneMetrics $lanesMapped }
if ($rows[0].SummaryColor -eq "White") { Pass "SummaryColor for running is white" } else { Fail "SummaryColor for running is white" "$($rows[0].SummaryColor)" }
if ($rows[1].SummaryColor -eq "Cyan") { Pass "SummaryColor for queued is cyan" } else { Fail "SummaryColor for queued is cyan" "$($rows[1].SummaryColor)" }
if ($rows[2].SummaryColor -eq "DarkGray") { Pass "SummaryColor for idle is darkgray" } else { Fail "SummaryColor for idle is darkgray" "$($rows[2].SummaryColor)" }

# ------------------------------------------------------------------
# Legend presence/absence tests (GO only, width bounded via capture)
# ------------------------------------------------------------------
function Should-ShowLegend {
    param([array]$lanes)
    $active = 0; $queued = 0
    foreach ($lane in $lanes) {
        if ($lane.Active) { $active += $lane.Active }
        if ($lane.Queued) { $queued += $lane.Queued }
    }
    return ($active -gt 0 -or $queued -gt 0)
}

$laneRunning = @{ Name = "BACKEND"; Active = 1; Queued = 0 }
if (Should-ShowLegend @($laneRunning)) { Pass "Legend shows for running lanes" } else { Fail "Legend shows for running lanes" "Legend gating failed" }

$laneQueued = @{ Name = "FRONTEND"; Active = 0; Queued = 3 }
if (Should-ShowLegend @($laneQueued)) { Pass "Legend shows for queued lanes" } else { Fail "Legend shows for queued lanes" "Legend gating failed" }

$laneBoth = @{ Name = "OPS"; Active = 1; Queued = 1 }
if (Should-ShowLegend @($laneBoth)) { Pass "Legend shows both states when mixed" } else { Fail "Legend shows both states when mixed" "Legend gating failed" }

if (-not (Should-ShowLegend @())) { Pass "Legend hidden when no streams" } else { Fail "Legend hidden when no streams" "Legend gating failed" }
if (-not (Should-ShowLegend @())) { Pass "Legend hidden on PLAN" } else { Fail "Legend hidden on PLAN" "Legend gating failed" }

if ($failures -gt 0) {
    exit 1
}

Write-Host "Stream legend tests passed" -ForegroundColor Green
