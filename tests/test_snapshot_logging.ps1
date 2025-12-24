# Snapshot logging tests (opt-in)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = "$RepoRoot\src\AtomicMesh.UI"

# Load dependencies
$files = @(
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiCache.ps1',
    'Private/Models/UiToast.ps1',
    'Private/Models/UiEvent.ps1',
    'Private/Models/UiEventLog.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Models/UiState.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1',
    'Private/Helpers/LoggingHelpers.ps1'
)
foreach ($file in $files) {
    $fullPath = Join-Path $ModuleRoot $file
    if (Test-Path $fullPath) { . $fullPath }
}

function New-TestSnapshot {
    $s = [UiSnapshot]::new()
    $s.PlanState = [PlanState]::new()
    $s.PlanState.Status = "DRAFT"
    $s.PlanState.HasDraft = $true
    return $s
}

function Test-Check {
    param([string]$Name, [scriptblock]$Block)
    Write-Host "CHECK: $Name ... " -NoNewline
    try {
        $result = & $Block
        if ($result -eq $true) {
            Write-Host "PASS" -ForegroundColor Green
        } else {
            Write-Host "FAIL ($result)" -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$tmpRoot = Join-Path $env:TEMP ("mesh_log_test_" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$logPath = Join-Path $tmpRoot "control\state\pipeline_snapshots.jsonl"

Test-Check "Logging disabled by default" {
    if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot | Out-Null }
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

    $state = [UiState]::new()
    $state.EnableSnapshotLogging = $false
    $snap = New-TestSnapshot

    Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snap -ProjectPath $tmpRoot
    if (Test-Path $logPath) {
        return "Log file should not exist when logging disabled"
    }
    return $true
}

Test-Check "Logging enabled writes once per change" {
    if (Test-Path $tmpRoot) { Remove-Item -Recurse -Force $tmpRoot | Out-Null }
    New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

    $state = [UiState]::new()
    $state.EnableSnapshotLogging = $true
    $snap = New-TestSnapshot

    # First write
    Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snap -ProjectPath $tmpRoot
    if (-not (Test-Path $logPath)) {
        return "Expected log file to be created"
    }
    $lines = Get-Content -Path $logPath
    if ($lines.Count -ne 1) { return "Expected 1 line after first write, got $($lines.Count)" }

    # Duplicate write should not append
    Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snap -ProjectPath $tmpRoot
    $lines = Get-Content -Path $logPath
    if ($lines.Count -ne 1) { return "Duplicate snapshot should not append" }

    # Change snapshot (ACCEPTED) should append second line
    $snap.PlanState.Status = "ACCEPTED"
    $snap.PlanState.Accepted = $true
    Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snap -ProjectPath $tmpRoot
    $lines = Get-Content -Path $logPath
    if ($lines.Count -ne 2) { return "Expected second line after change, got $($lines.Count)" }

    # Transition to non-green (PRE_INIT) should append third line and set any_non_green=true
    $snap.PlanState.Status = "PRE_INIT"
    $snap.PlanState.Accepted = $false
    Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snap -ProjectPath $tmpRoot
    $lines = Get-Content -Path $logPath
    if ($lines.Count -ne 3) { return "Expected third line for non-green transition, got $($lines.Count)" }

    # Validate schema keys
    $parsed = $lines | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($p in $parsed) {
        if (-not $p.ts -or -not $p.stages -or -not $p.next -or -not $p.reason -or -not $p.source -or ($null -eq $p.any_non_green)) {
            return "Missing expected keys in record"
        }
    }

    # Last record should mark non-green
    $last = $parsed[-1]
    if (-not $last.any_non_green) { return "Expected any_non_green flag to be true on non-green transition" }

    return $true
}

Write-Host "All snapshot logging checks passed." -ForegroundColor Green
exit 0
