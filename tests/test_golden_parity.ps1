# Golden Parity Tests for AtomicMesh.UI Module
# Compares module render output against golden fixtures from control_panel.ps1

param(
    [switch]$UpdateFixtures,
    [string]$Filter = "*"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

# Import test harness
Import-Module "$PSScriptRoot\GoldenTestHarness.psm1" -Force

# Source all module files directly to get access to types and capture functions
# This mirrors the module loader but gives us direct access to classes
$ModuleRoot = "$RepoRoot\src\AtomicMesh.UI"
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
    'Private/Reducers/ComputePlanState.ps1',
    'Private/Reducers/ComputeLaneMetrics.ps1',
    'Private/Reducers/ComputeNextHint.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1',
    'Private/Layout/LayoutConstants.ps1',
    'Private/Render/Console.ps1',
    'Private/Render/RenderCommon.ps1',
    'Private/Render/RenderPlan.ps1',
    'Private/Render/RenderGo.ps1',
    'Private/Render/RenderBootstrap.ps1',
    'Private/Render/CommandPicker.ps1',
    'Private/Render/Overlays/RenderHistory.ps1'
    # NON-GOLDEN: RenderStreamDetails and RenderStats removed
)
foreach ($file in $files) {
    $fullPath = Join-Path $ModuleRoot $file
    if (Test-Path $fullPath) {
        . $fullPath
    }
}

$FixturesPath = Join-Path $PSScriptRoot "fixtures"
$GoldenPath = Join-Path $FixturesPath "golden"
$ActualPath = Join-Path $FixturesPath "_actual"

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
    Details = @()
}

function Test-GoldenFixture {
    param(
        [string]$Name,
        [scriptblock]$RenderBlock,
        [int]$Width = 80,
        [int]$Height = 24
    )

    if ($Name -notlike $Filter) {
        $script:TestResults.Skipped++
        return
    }

    Write-Host "Testing: $Name ... " -NoNewline

    try {
        # Enable capture mode
        Enable-CaptureMode -Width $Width -Height $Height
        Begin-ConsoleFrame

        # Execute render block
        & $RenderBlock

        # Get captured output
        $actual = Get-CapturedOutput
        Disable-CaptureMode

        # Compare against fixture
        $result = Assert-GoldenMatch -FixtureName "$Name.txt" -ActualFrame $actual -RepoRoot $RepoRoot -FixturesPath $FixturesPath

        if ($result.Pass) {
            Write-Host "PASS" -ForegroundColor Green
            $script:TestResults.Passed++
        } else {
            Write-Host "FAIL ($($result.Reason))" -ForegroundColor Red
            $script:TestResults.Failed++
        }

        $script:TestResults.Details += @{
            Name = $Name
            Pass = $result.Pass
            Reason = $result.Reason
        }
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $script:TestResults.Failed++
        $script:TestResults.Details += @{
            Name = $Name
            Pass = $false
            Reason = "ERROR: $($_.Exception.Message)"
        }
    }
}

# =============================================================================
# SPINE FIXTURES (implement first)
# =============================================================================

# Create test state/snapshot helpers
function New-EmptySnapshot {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "UNKNOWN"
    $snapshot.PlanState.HasDraft = $false
    $snapshot.PlanState.Accepted = $false
    $snapshot.LaneMetrics = @()
    $snapshot.SchedulerDecision = [SchedulerDecision]::new()
    $snapshot.Alerts = [UiAlerts]::new()
    return $snapshot
}

function New-EmptyState {
    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    $state.OverlayMode = "None"
    $state.InputBuffer = ""
    return $state
}

# Full-frame render helper: header (rows 0-3) + content (rows 4+)
function Render-FullFrame {
    param(
        [UiSnapshot]$Snapshot,
        [UiState]$State,
        [scriptblock]$ContentRenderer,
        [int]$Width = 80
    )

    # Golden layout: Header at row 0-3, content at row 4+
    Render-Header -StartRow 0 -Width $Width -Snapshot $Snapshot -State $State
    & $ContentRenderer
}

# -----------------------------------------------------------------------------
# TEST: plan_empty
# PLAN page with no draft, no tasks, repo initialized
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "plan_empty" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "UNKNOWN"

    $state = New-EmptyState
    $state.CurrentPage = "PLAN"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: bootstrap
# BOOTSTRAP page, repo not initialized
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "bootstrap" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "BOOTSTRAP"  # Set BOOTSTRAP status for header
    $state = New-EmptyState
    $state.CurrentPage = "BOOTSTRAP"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Bootstrap -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: plan_with_draft
# PLAN page with draft exists but not accepted
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "plan_with_draft" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true
    $snapshot.PlanState.Accepted = $false
    $snapshot.PlanState.Summary = "3 tasks planned"

    $state = New-EmptyState
    $state.CurrentPage = "PLAN"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: exec_running
# GO/EXEC page with workers active
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "exec_running" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.PlanState.Accepted = $true

    # Add some lane metrics
    $lane1 = [LaneMetrics]::new()
    $lane1.Name = "BACKEND"
    $lane1.Queued = 2
    $lane1.Active = 1
    $lane1.State = "RUNNING"

    $lane2 = [LaneMetrics]::new()
    $lane2.Name = "FRONTEND"
    $lane2.Queued = 1
    $lane2.Active = 0
    $lane2.State = "QUEUED"

    $snapshot.LaneMetrics = @($lane1, $lane2)

    $state = New-EmptyState
    $state.CurrentPage = "GO"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Go -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: history_tasks
# History overlay with TASKS subview
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "history_tasks" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $state = New-EmptyState
    $state.OverlayMode = "History"
    $state.HistorySubview = "TASKS"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-HistoryOverlay -State $state -StartRow 4
    }
}

# =============================================================================
# EXPANSION FIXTURES
# =============================================================================

# -----------------------------------------------------------------------------
# TEST: plan_accepted
# PLAN page with plan accepted, ready to /go
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "plan_accepted" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.PlanState.HasDraft = $true
    $snapshot.PlanState.Accepted = $true
    $snapshot.PlanState.Summary = "5 tasks ready"

    $state = New-EmptyState
    $state.CurrentPage = "PLAN"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: exec_empty
# GO/EXEC page with no workers, no queued tasks
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "exec_empty" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.PlanState.Accepted = $true
    $snapshot.LaneMetrics = @()

    $state = New-EmptyState
    $state.CurrentPage = "GO"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Go -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: history_docs
# History overlay with DOCS subview
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "history_docs" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $state = New-EmptyState
    $state.OverlayMode = "History"
    $state.HistorySubview = "DOCS"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-HistoryOverlay -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: history_ship
# History overlay with SHIP subview
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "history_ship" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $state = New-EmptyState
    $state.OverlayMode = "History"
    $state.HistorySubview = "SHIP"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-HistoryOverlay -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: plan_adapter_error
# PLAN page with backend adapter error
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "plan_adapter_error" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "ERROR"
    $snapshot.PlanState.HasDraft = $false
    $snapshot.Alerts.AdapterError = "Connection failed: Backend unreachable"

    $state = New-EmptyState
    $state.CurrentPage = "PLAN"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    }
}

# -----------------------------------------------------------------------------
# TEST: plan_fail_open
# PLAN page in fail-open readiness mode showing source line
# -----------------------------------------------------------------------------
Test-GoldenFixture -Name "plan_fail_open" -RenderBlock {
    $snapshot = New-EmptySnapshot
    $snapshot.PlanState.Status = "UNKNOWN"
    $snapshot.ReadinessMode = "fail-open"
    $snapshot.IsInitialized = $false

    $state = New-EmptyState
    $state.CurrentPage = "PLAN"

    Render-FullFrame -Snapshot $snapshot -State $state -ContentRenderer {
        Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    }
}

# =============================================================================
# FIXTURE SANITY CHECK
# =============================================================================

# Track which fixtures we have tests for
$script:TestedFixtures = @(
    # Spine fixtures
    "plan_empty",
    "bootstrap",
    "plan_with_draft",
    "exec_running",
    "history_tasks",
    # Expansion fixtures
    "plan_accepted",
    "exec_empty",
    "history_docs",
    "history_ship",
    "plan_adapter_error",
    "plan_fail_open"
)

function Test-FixtureSanity {
    Write-Host ""
    Write-Host "Fixture sanity check..." -NoNewline

    $goldenFiles = Get-ChildItem -Path $GoldenPath -Filter "*.txt" -ErrorAction SilentlyContinue |
                   ForEach-Object { $_.BaseName }

    $orphans = @()
    $missing = @()

    # Check for orphan fixtures (fixture exists but no test)
    foreach ($fixture in $goldenFiles) {
        if ($fixture -notin $script:TestedFixtures) {
            $orphans += $fixture
        }
    }

    # Check for missing fixtures (test exists but no fixture)
    foreach ($tested in $script:TestedFixtures) {
        if ($tested -notin $goldenFiles) {
            $missing += $tested
        }
    }

    if ($orphans.Count -eq 0 -and $missing.Count -eq 0) {
        Write-Host " PASS" -ForegroundColor Green
        return $true
    }

    Write-Host " FAIL" -ForegroundColor Red
    if ($orphans.Count -gt 0) {
        Write-Host "  Orphan fixtures (no test): $($orphans -join ', ')" -ForegroundColor Yellow
    }
    if ($missing.Count -gt 0) {
        Write-Host "  Missing fixtures (test exists): $($missing -join ', ')" -ForegroundColor Yellow
    }
    return $false
}

$sanityPassed = Test-FixtureSanity

# =============================================================================
# RESULTS SUMMARY
# =============================================================================

Write-Host ""
Write-Host "=" * 60
Write-Host "GOLDEN PARITY TEST RESULTS"
Write-Host "=" * 60
Write-Host "Passed:  $($script:TestResults.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
Write-Host ""

if ($script:TestResults.Failed -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($detail in $script:TestResults.Details) {
        if (-not $detail.Pass) {
            Write-Host "  - $($detail.Name): $($detail.Reason)" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "Actual outputs written to: $ActualPath" -ForegroundColor Cyan
    Write-Host "To update fixtures, copy from _actual/ to golden/" -ForegroundColor Cyan
    exit 1
}

if (-not $sanityPassed) {
    Write-Host "Fixture sanity check failed!" -ForegroundColor Red
    exit 1
}

Write-Host "All tests passed!" -ForegroundColor Green
exit 0
