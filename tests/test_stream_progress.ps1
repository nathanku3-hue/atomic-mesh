$ErrorActionPreference = "Stop"

$modulePath = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "src") "AtomicMesh.UI") "AtomicMesh.UI.psd1"
$module = Import-Module -Name $modulePath -Force -PassThru

$failures = 0
function Pass([string]$name) { Write-Host "[PASS] $name" -ForegroundColor Green }
function Fail([string]$name, [string]$reason) { Write-Host "[FAIL] $name" -ForegroundColor Red; Write-Host "       $reason" -ForegroundColor Yellow; $script:failures++ }

# 40% progress -> 2/5 blocks
$lanesForty = & $module {
    Compute-LaneMetrics -RawSnapshot @{
        active_task = @{ lane = "backend"; progress = 40 }
        LaneCounts = @(
            @{ Lane = "backend"; Status = "in_progress"; Count = 1 }
        )
    }
}
if ($lanesForty[0].Bar -eq "■■□□□") { Pass "Progress 40% maps to 2 filled blocks" } else { Fail "Progress 40% maps to 2 filled blocks" "$($lanesForty[0].Bar)" }
if ($lanesForty[0].Reason -match "40%") { Pass "Reason shows percent when available" } else { Fail "Reason shows percent when available" "$($lanesForty[0].Reason)" }

# 10% progress -> minimum 1 block when active
$lanesTen = & $module {
    Compute-LaneMetrics -RawSnapshot @{
        active_task = @{ lane = "backend"; progress = 10 }
        LaneCounts = @(
            @{ Lane = "backend"; Status = "in_progress"; Count = 1 }
        )
    }
}
if ($lanesTen[0].Bar -eq "■□□□□") { Pass "Progress floor to 1 block when started" } else { Fail "Progress floor to 1 block when started" "$($lanesTen[0].Bar)" }

if ($failures -gt 0) { exit 1 }
Write-Host "Stream progress tests passed" -ForegroundColor Green
