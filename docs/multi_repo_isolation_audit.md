# Multi-Repo Isolation Audit

## Executive Summary

The current architecture **does support clean multi-repo operation**, but has some subtle risks documented below. The "1 pending | 2 active" issue was NOT caused by cross-project contamination - it was caused by a stale control panel session or the hardcoded stub adapter (now fixed).

## Architecture Analysis

### 1. Python Backend Isolation ✅ SAFE

Each Python call (`snapshot.py`, `mesh_server.py`) runs as a **new subprocess**:

```powershell
# From MeshServerAdapter.ps1 / RealAdapter.ps1
$psi.WorkingDirectory = $ProjectPath
$proc = [System.Diagnostics.Process]::Start($psi)
```

**Why this is safe:**
- Fresh Python interpreter per call
- Module imported fresh each time
- `BASE_DIR = os.getenv("MESH_BASE_DIR", os.getcwd())` picks up correct `WorkingDirectory`
- No shared state between calls

### 2. PowerShell Module-Level Variables

| Variable | Location | Risk | Mitigation |
|----------|----------|------|------------|
| `$script:ModuleRoot` | AtomicMesh.UI.psm1 | LOW | Static module location, doesn't change |
| `$script:Icons` | Invoke-CommandRouter.ps1 | NONE | UI constants only |
| `$script:CtrlCState` | Start-ControlPanel.ps1 | LOW | Reset on each `Start-ControlPanel` call |
| `$script:PickerState` | CommandPicker.ps1 | LOW | Reset on each `Start-ControlPanel` call |
| `$script:FrameState` | Console.ps1 | LOW | Per-frame, reset each render |
| `$script:CaptureMode` | Console.ps1 | LOW | Testing only, default false |

### 3. Per-Session State (`UiState` class) ✅ SAFE

Each `Start-ControlPanel` call creates a new `UiState` instance:

```powershell
$state = [UiState]::new()
$state.Cache.Metadata["ProjectPath"] = $projectPath  # Project-specific
$state.Cache.Metadata["ModuleRoot"] = $moduleRoot    # Module location
$state.Cache.Metadata["RepoRoot"] = $repoRoot        # Legacy alias
```

**Why this is safe:**
- `$state` is a local variable, scoped to the function
- All project-specific paths stored in `$state.Cache.Metadata`
- Commands extract paths from state, not module-level variables

### 4. Module Import Behavior ✅ SAFE

```powershell
# control_panel.ps1
Import-Module -Name $modulePath -Force
```

The `-Force` flag ensures:
- Module is re-imported even if already loaded
- All `$script:` variables are re-initialized
- No stale state from previous sessions

## Identified Risks

### Risk 1: Fallback to `(Get-Location).Path`

Several places fall back to current directory if path not provided:

```powershell
# Get-LatestDraftPlan
$baseDir = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }

# Invoke-CommandRouter
$projectPath = if ($state.Cache -and $state.Cache.Metadata) {
    $state.Cache.Metadata["ProjectPath"]
} else {
    (Get-Location).Path  # FALLBACK
}
```

**Risk Level:** LOW
**Mitigation:** `Start-ControlPanel` always sets `ProjectPath` in metadata. Fallback only triggers if metadata is corrupted.

### Risk 2: Stub Adapter with Hardcoded Data (FIXED)

`SnapshotAdapter.ps1` had hardcoded `queued = 1`:

```powershell
# BEFORE (caused confusion)
@{ name = "BACKEND"; queued = 1; active = 0; tokens = 0 }

# AFTER (fixed)
@{ name = "BACKEND"; queued = 0; active = 0; tokens = 0 }
```

**Risk Level:** NONE (after fix)
**Mitigation:** Production uses `Get-RealSnapshot`, stub is deprecated.

### Risk 3: No Explicit Project ID in Logs

Pipeline logs (`control/state/pipeline_snapshots.jsonl`) don't include project identifier:

```powershell
# LoggingHelpers.ps1
$logDir = Join-Path $ProjectPath "control\state"
```

**Risk Level:** LOW
**Mitigation:** Logs are written to project-specific directory, natural isolation.

## Verification Test

To verify multi-repo isolation, run this test:

```powershell
# Terminal 1: Project A (with tasks)
cd E:\Code\project-a
.\control_panel.ps1

# Terminal 2: Project B (empty)
cd E:\Code\project-b
.\control_panel.ps1

# Expected: Each shows correct counts for its own project
```

## Root Cause of "1 pending | 2 active"

**FOUND: Database Path Mismatch (Fixed)**

| Component | Database Used | Issue |
|-----------|---------------|-------|
| `mesh_server.py` | `mesh.db` | Writes tasks here |
| `snapshot.py` (before fix) | `tasks.db` (priority 1) | Read from empty DB |
| `snapshot.py` (after fix) | `mesh.db` (priority 1) | Reads same DB as writes |

The control panel was reading from `tasks.db` (empty) while `/accept-plan` wrote to `mesh.db` (with tasks). This caused a split-brain where:
- Commands created tasks in `mesh.db`
- Header showed counts from `tasks.db` (always 0)

**Fix applied:** `tools/snapshot.py` now prioritizes `mesh.db` to match `mesh_server.py`.

Secondary causes (also fixed):
1. **Stub adapter data** - `SnapshotAdapter.ps1` had `queued = 1` (now 0)

## Recommendations

1. **Add project identifier to header** (optional enhancement)
   - Show project path more prominently
   - Helps user confirm they're viewing the right project

2. **Consider adding startup diagnostic**
   - Log "Starting control panel for: <project-path>"
   - Helps debugging "wrong project" issues

3. **Remove stub adapter entirely** (optional cleanup)
   - `SnapshotAdapter.ps1` is unused in production
   - Keeping it risks future confusion

## Conclusion

The multi-repo architecture is sound. Each project operates in isolation through:
- Subprocess-per-call Python backend
- Per-session `UiState` with project paths
- `-Force` module reimport
- Project-specific working directories

The "1 pending | 2 active" issue was a rendering artifact, not an isolation failure.
