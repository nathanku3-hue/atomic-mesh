#!/usr/bin/env pwsh
# Test the before/after /init flow
# Verifies: ForceDataRefresh flag bypasses interval check after /init
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot/..

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-init-test-$([guid]::NewGuid().ToString('N').Substring(0,8))"
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "=== Test dir: $tempDir ===" -ForegroundColor Cyan
Write-Host ""

# Before /init
Write-Host "=== Before /init (no DB) ===" -ForegroundColor Yellow
$result1 = python tools/snapshot.py $tempDir 2>&1 | ConvertFrom-Json
Write-Host "ReadinessMode: $($result1.ReadinessMode)"
Write-Host "DbPresent: $($result1.DbPresent)"

# Simulate /init by creating DB with proper schema
Write-Host ""
Write-Host "=== Creating DB (simulating /init) ===" -ForegroundColor Yellow
$dbPath = Join-Path $tempDir "tasks.db"
# Use forward slashes for Python
$dbPathPy = $dbPath -replace '\\', '/'
$createSql = @"
import sqlite3
c = sqlite3.connect('$dbPathPy')
c.execute('''CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    lane TEXT,
    status TEXT,
    type TEXT,
    risk TEXT,
    entropy_marker TEXT
)''')
c.close()
"@
python -c $createSql
Write-Host "Created: $dbPath"
Write-Host "Exists: $(Test-Path $dbPath)"

# After /init
Write-Host ""
Write-Host "=== After /init (DB exists) ===" -ForegroundColor Yellow
$result2 = python tools/snapshot.py $tempDir 2>&1 | ConvertFrom-Json
Write-Host "ReadinessMode: $($result2.ReadinessMode)"
Write-Host "DbPresent: $($result2.DbPresent)"

# Test UI logic
Write-Host ""
Write-Host "=== UI Hint Logic ===" -ForegroundColor Yellow

. ./src/AtomicMesh.UI/Private/Models/PlanState.ps1
. ./src/AtomicMesh.UI/Private/Models/LaneMetrics.ps1
. ./src/AtomicMesh.UI/Private/Models/SchedulerDecision.ps1
. ./src/AtomicMesh.UI/Private/Models/UiAlerts.ps1
. ./src/AtomicMesh.UI/Private/Models/UiSnapshot.ps1
. ./src/AtomicMesh.UI/Private/Render/Console.ps1
. ./src/AtomicMesh.UI/Private/Reducers/ComputeNextHint.ps1
. ./src/AtomicMesh.UI/Private/Reducers/ComputePlanState.ps1
. ./src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1
. ./src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1
. ./src/AtomicMesh.UI/Private/Layout/LayoutConstants.ps1
. ./src/AtomicMesh.UI/Private/Helpers/InitHelpers.ps1

$snapshot = Convert-RawSnapshotToUi -Raw $result2
Write-Host "Snapshot.ReadinessMode: $($snapshot.ReadinessMode)"

$directives = Get-DocsRightColumn -Snapshot $snapshot
Write-Host "UI Directives:"
foreach ($d in $directives) {
    Write-Host "  $($d.Text) [$($d.Color)]"
}

# Check if still showing /init
$lastHint = $directives[-1].Text
if ($lastHint -match "/init") {
    Write-Host ""
    Write-Host "[FAIL] Still showing '/init' after DB created!" -ForegroundColor Red
} else {
    Write-Host ""
    Write-Host "[PASS] Correct hint after DB created: $lastHint" -ForegroundColor Green
}

# ============================================================================
# Test: Initialized but no DB shows docs hint, not /init
# ============================================================================
Write-Host ""
Write-Host "=== Initialized + No DB Test ===" -ForegroundColor Yellow

# Use a fresh temp dir for this test (no DB)
$tempDir2 = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-init-test2-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir2 -Force | Out-Null

# Create marker file to simulate /init without DB
$markerDir = Join-Path $tempDir2 "control\state"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
"" | Set-Content -Path (Join-Path $markerDir ".mesh_initialized") -Encoding UTF8
Write-Host "Test dir: $tempDir2"
Write-Host "Created marker: control\state\.mesh_initialized"

# Get snapshot (no DB, but initialized via marker)
$result3 = python tools/snapshot.py $tempDir2 2>&1 | ConvertFrom-Json
Write-Host "ReadinessMode: $($result3.ReadinessMode)"
Write-Host "IsInitialized: $($result3.IsInitialized)"

$snapshot3 = Convert-RawSnapshotToUi -Raw $result3
$directives3 = Get-DocsRightColumn -Snapshot $snapshot3
$lastHint3 = $directives3[-1].Text

if ($lastHint3 -notmatch "/init") {
    Write-Host "[PASS] Initialized project shows '$lastHint3' (not /init)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Initialized project should NOT show /init" -ForegroundColor Red
}

# Cleanup temp dir 2
Remove-Item -Path $tempDir2 -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================================
# Test ForceDataRefresh flag
# ============================================================================
Write-Host ""
Write-Host "=== ForceDataRefresh Flag Test ===" -ForegroundColor Yellow

. ./src/AtomicMesh.UI/Private/Models/UiToast.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEvent.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEventLog.ps1
. ./src/AtomicMesh.UI/Private/Models/UiCache.ps1
. ./src/AtomicMesh.UI/Private/Models/UiState.ps1

$state = [UiState]::new()
Write-Host "Initial ForceDataRefresh: $($state.ForceDataRefresh)"
if ($state.ForceDataRefresh -eq $false) {
    Write-Host "[PASS] ForceDataRefresh defaults to false" -ForegroundColor Green
} else {
    Write-Host "[FAIL] ForceDataRefresh should default to false" -ForegroundColor Red
}

$state.ForceDataRefresh = $true
Write-Host "After setting: $($state.ForceDataRefresh)"
if ($state.ForceDataRefresh -eq $true) {
    Write-Host "[PASS] ForceDataRefresh can be set to true" -ForegroundColor Green
} else {
    Write-Host "[FAIL] ForceDataRefresh should be settable to true" -ForegroundColor Red
}

# ============================================================================
# Test: Test-RepoInitialized matches snapshot.py::check_initialized
# ============================================================================
Write-Host ""
Write-Host "=== Test-RepoInitialized vs snapshot.py ===" -ForegroundColor Yellow

$tempDir3 = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-init-test3-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir3 -Force | Out-Null
Write-Host "Test dir: $tempDir3"

# Before marker: Both should return not initialized
$psResult = Test-RepoInitialized -Path $tempDir3
$pyResult = python tools/snapshot.py $tempDir3 2>&1 | ConvertFrom-Json

Write-Host ""
Write-Host "Before marker:"
Write-Host "  PS Test-RepoInitialized: initialized=$($psResult.initialized), reason=$($psResult.reason)"
Write-Host "  Py check_initialized:    IsInitialized=$($pyResult.IsInitialized)"

if ($psResult.initialized -eq $false -and $pyResult.IsInitialized -eq $false) {
    Write-Host "[PASS] Both agree: not initialized before marker" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Mismatch before marker!" -ForegroundColor Red
}

# Create marker file
$markerDir = Join-Path $tempDir3 "control\state"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
$markerPath = Join-Path $markerDir ".mesh_initialized"
"" | Set-Content -Path $markerPath -Encoding UTF8
Write-Host ""
Write-Host "Created marker: $markerPath"
Write-Host "Marker exists: $(Test-Path $markerPath)"

# After marker: Both should return initialized
$psResult2 = Test-RepoInitialized -Path $tempDir3
$pyResult2 = python tools/snapshot.py $tempDir3 2>&1 | ConvertFrom-Json

Write-Host ""
Write-Host "After marker:"
Write-Host "  PS Test-RepoInitialized: initialized=$($psResult2.initialized), reason=$($psResult2.reason)"
Write-Host "  Py check_initialized:    IsInitialized=$($pyResult2.IsInitialized)"

if ($psResult2.initialized -eq $true -and $pyResult2.IsInitialized -eq $true) {
    Write-Host "[PASS] Both agree: initialized after marker" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Mismatch after marker!" -ForegroundColor Red
    Write-Host "  PS details: $($psResult2.details)"
}

# Cleanup temp dirs
Remove-Item -Path $tempDir3 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================================
# Test: /init → page transition flow (simulates Update-AutoPageFromPlanStatus)
# ============================================================================
Write-Host ""
Write-Host "=== /init Page Transition Flow ===" -ForegroundColor Yellow

. ./src/AtomicMesh.UI/Private/Models/UiToast.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEvent.ps1
. ./src/AtomicMesh.UI/Private/Models/UiEventLog.ps1
. ./src/AtomicMesh.UI/Private/Models/UiCache.ps1
. ./src/AtomicMesh.UI/Private/Models/UiState.ps1

$tempDir4 = Join-Path ([System.IO.Path]::GetTempPath()) "mesh-init-test4-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir4 -Force | Out-Null
Write-Host "Test dir: $tempDir4"

# Create fresh state with ProjectPath set (like Start-ControlPanel does)
$state = [UiState]::new()
$state.CurrentPage = "BOOTSTRAP"  # Start on BOOTSTRAP
$state.Cache.Metadata["ProjectPath"] = $tempDir4
Write-Host "Initial page: $($state.CurrentPage)"
Write-Host "ProjectPath: $($state.Cache.Metadata['ProjectPath'])"

# Simulate what Update-AutoPageFromPlanStatus does (BEFORE /init)
$projectPath = $state.Cache.Metadata["ProjectPath"]
$initStatus = Test-RepoInitialized -Path $projectPath
Write-Host ""
Write-Host "Before /init:"
Write-Host "  Test-RepoInitialized: initialized=$($initStatus.initialized)"
if (-not $initStatus.initialized -and $state.CurrentPage -eq "PLAN") {
    $state.SetPage("BOOTSTRAP")
    Write-Host "  Page switched to BOOTSTRAP"
} elseif ($initStatus.initialized -and $state.CurrentPage -eq "BOOTSTRAP") {
    $state.SetPage("PLAN")
    Write-Host "  Page switched to PLAN"
} else {
    Write-Host "  No page change (current: $($state.CurrentPage))"
}

# Simulate /init: create marker + set page to PLAN
$markerDir = Join-Path $tempDir4 "control\state"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
"" | Set-Content -Path (Join-Path $markerDir ".mesh_initialized") -Encoding UTF8
$state.SetPage("PLAN")
$state.ForceDataRefresh = $true
Write-Host ""
Write-Host "After /init command:"
Write-Host "  Marker created: $(Join-Path $markerDir '.mesh_initialized')"
Write-Host "  Page set to: $($state.CurrentPage)"
Write-Host "  ForceDataRefresh: $($state.ForceDataRefresh)"

# Simulate what Update-AutoPageFromPlanStatus does (AFTER /init, in next iteration)
$projectPath = $state.Cache.Metadata["ProjectPath"]
$initStatus2 = Test-RepoInitialized -Path $projectPath
Write-Host ""
Write-Host "Next iteration (Update-AutoPageFromPlanStatus):"
Write-Host "  ProjectPath: $projectPath"
Write-Host "  Test-RepoInitialized: initialized=$($initStatus2.initialized), reason=$($initStatus2.reason)"
Write-Host "  Current page: $($state.CurrentPage)"

# Apply the same logic as Update-AutoPageFromPlanStatus
$isInitialized = $initStatus2.initialized
if (-not $isInitialized -and $state.CurrentPage -eq "PLAN") {
    Write-Host "  [FAIL] Would switch PLAN → BOOTSTRAP!" -ForegroundColor Red
    $state.SetPage("BOOTSTRAP")
} elseif ($isInitialized -and $state.CurrentPage -eq "BOOTSTRAP") {
    Write-Host "  Would switch BOOTSTRAP → PLAN"
    $state.SetPage("PLAN")
} else {
    Write-Host "  [PASS] No page change (page stays $($state.CurrentPage))" -ForegroundColor Green
}

Write-Host ""
Write-Host "Final page: $($state.CurrentPage)"
if ($state.CurrentPage -eq "PLAN") {
    Write-Host "[PASS] Page correctly stayed on PLAN after /init" -ForegroundColor Green
} else {
    Write-Host "[FAIL] Page should be PLAN but is $($state.CurrentPage)" -ForegroundColor Red
}

# Cleanup
Remove-Item -Path $tempDir4 -Recurse -Force -ErrorAction SilentlyContinue
