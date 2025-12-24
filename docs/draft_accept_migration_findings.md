# Draft-Plan / Accept-Plan Migration Findings

**Date**: 2025-12-21
**Purpose**: Document golden reference behavior vs. current module to enable parity migration

---

## 1. Golden Reference Analysis

### 1.1 `/draft-plan` Command (Golden: lines 3775-3872)

**Location**: `reference/golden/control_panel_6990922.ps1:3775-3872`

**What It Actually Does**:
1. Sets page to PLAN: `Set-Page "PLAN"`
2. Checks for existing draft via `Get-LatestDraftPlan`
3. If no draft exists, calls Python backend:
   ```powershell
   $pyCode = "import sys, logging; logging.disable(logging.INFO); sys.path.insert(0, r'$RepoRoot'); from mesh_server import draft_plan; print(draft_plan())"
   ```
4. Uses `ProcessStartInfo` for proper stdout/stderr capture with timeout
5. Parses response via `ConvertFrom-SafeJson`
6. Handles response statuses:
   - `OK`: Opens draft in editor (`cmd /c start "" "$draftPath"`)
   - `BLOCKED`: Shows blocking files in error message
   - `ERROR`: Shows error message
   - Parse error: Shows cause from `_parseError`
7. Updates "Next:" hint to `/accept-plan` or `/draft-plan`
8. Displays result below prompt (Green=success, Red=error)

**Helper Functions Used**:
- `Get-LatestDraftPlan` (line 9976): Finds most recent `draft_*.md` in `docs/PLANS/`
- `Test-DraftPlanExists` (line 9993): Boolean wrapper
- `ConvertFrom-SafeJson` (line 792): Safe JSON parsing with diagnostic logging

**Response Format from Python** (from mesh_server.py:3705-3714):
```json
{
  "status": "OK | BLOCKED | ERROR",
  "path": "/path/to/draft_20241221_1430.md",
  "message": "Draft created: ...",
  "plan_quality": "OK | INSUFFICIENT_CONTEXT",
  "task_count": 5,
  "lane_count": 2,
  "blocking_files": ["PRD", "SPEC"]  // only when BLOCKED
}
```

---

### 1.2 `/accept-plan` Command (Golden: lines 3874-3968)

**Location**: `reference/golden/control_panel_6990922.ps1:3874-3968`

**What It Actually Does**:
1. Gets plan path from args, or defaults to `Get-LatestDraftPlan`
2. If no draft found: Shows "No draft plan found. Run /draft-plan first."
3. Calls Python backend with FULL ABSOLUTE PATH:
   ```powershell
   $escapedPath = $planPath -replace "'", "''"
   $rawResult = python -c "import sys, logging; logging.disable(logging.INFO); sys.path.insert(0, r'$RepoRoot'); from mesh_server import accept_plan; print(accept_plan(r'$escapedPath'))"
   ```
4. Handles response statuses:
   - `OK`: Shows "Accepted: N task(s) created from $planPath" + returns "refresh"
   - `BLOCKED`: Shows blocking message + files
   - `ALREADY_ACCEPTED`: Shows "Plan already accepted"
   - `ERROR`: Shows error message
5. On success, returns `"refresh"` to trigger data refresh

**Critical v20.0 Fix**:
- Uses **raw string `r'...'`** for Windows paths to avoid backslash escape issues
- Uses **full absolute path**, not just filename (avoids DOCS_DIR mismatch)

**Response Format from Python** (from mesh_server.py:4113-4118):
```json
{
  "status": "OK | BLOCKED | ALREADY_ACCEPTED | ERROR",
  "created_count": 5,
  "skipped_duplicates": 0,
  "plan_hash": "abc123",
  "tasks": [...],
  "message": "..."  // for errors
}
```

---

## 2. Current Module Behavior

### 2.1 Current `/draft-plan` (Invoke-CommandRouter.ps1:89-119)

**What It Does Now**:
1. Calls `Test-CanDraftPlan` guard
2. If blocked: Shows toast with guard message
3. If passed:
   - Sets page to PLAN
   - Shows toast "Drafting plan..." for 3 seconds
   - **DOES NOTHING ELSE** - no backend call

**Problem**: Shows "Drafting plan..." but never calls Python. User sees optimistic toast, then nothing happens.

### 2.2 Current `/accept-plan` (Invoke-CommandRouter.ps1:120-147)

**What It Does Now**:
1. Calls `Test-CanAcceptPlan` guard
2. If blocked: Shows toast with guard message
3. If passed:
   - **Mutates local state directly**: `$snapshotRef.PlanState.Accepted = $true`
   - Shows toast "Plan accepted - Created N task(s)"
   - **DOES NOT call Python** - no actual task creation in DB

**Problem**: Pretends to accept but only changes local UI state. Database unchanged, tasks not created.

---

## 3. Delta Summary

| Aspect | Golden | Current | Gap |
|--------|--------|---------|-----|
| `/draft-plan` backend call | `python -c "from mesh_server import draft_plan"` | None | **Critical** |
| `/draft-plan` response handling | OK/BLOCKED/ERROR with messages | Fake "Drafting plan..." toast | **Critical** |
| `/draft-plan` opens editor | `cmd /c start "" "$path"` | None | Missing |
| `/accept-plan` backend call | `python -c "from mesh_server import accept_plan"` | None | **Critical** |
| `/accept-plan` path handling | Full absolute path with `r'...'` escape | N/A | N/A |
| `/accept-plan` refresh | Returns "refresh" for data reload | Mutates local state directly | **Wrong** |
| Timeout/error handling | ProcessStartInfo + timeout + try/catch | None | Missing |
| JSON parsing safety | `ConvertFrom-SafeJson` with logs | None | Missing |

---

## 4. Proposed Minimal Parity Port

### 4.1 New Adapter: `MeshServerAdapter.ps1`

Create: `src/AtomicMesh.UI/Private/Adapters/MeshServerAdapter.ps1`

Functions:
```powershell
function Invoke-DraftPlan {
    param([string]$ProjectPath, [int]$TimeoutMs = 2000)
    # Returns: @{ Ok; Status; Path; Message; BlockingFiles; TaskCount }
}

function Invoke-AcceptPlan {
    param([string]$ProjectPath, [string]$PlanPath, [int]$TimeoutMs = 2000)
    # Returns: @{ Ok; Status; CreatedCount; Message }
}

function Get-LatestDraftPlan {
    param([string]$ProjectPath)
    # Returns: full path or $null
}
```

Implementation pattern (from golden + RealAdapter.ps1):
1. Locate `mesh_server.py` via ModuleRoot
2. Build python -c command with:
   - `logging.disable(logging.INFO)` to suppress log pollution
   - `sys.path.insert(0, r'$ModuleRoot')` for import
   - `print(draft_plan())` or `print(accept_plan(r'$path'))`
3. Use `ProcessStartInfo` with:
   - `RedirectStandardOutput/Error = $true`
   - `CreateNoWindow = $true`
   - `WaitForExit($TimeoutMs)`
4. Parse JSON, handle parse errors with fallback structure
5. Return structured result (never throw to router)

### 4.2 Router Updates: `Invoke-CommandRouter.ps1`

**`/draft-plan` case**:
```powershell
$result = Invoke-DraftPlan -ProjectPath $projectPath
if ($result.Ok) {
    $state.Toast.Set("$($script:Icons.Success) Draft: $($result.Path)", "info", 5)
    $state.ForceDataRefresh = $true
} elseif ($result.Status -eq "BLOCKED") {
    $files = $result.BlockingFiles -join ", "
    $state.Toast.Set("$($script:Icons.Warning) BLOCKED: $files", "warning", 6)
} else {
    $state.Toast.Set("$($script:Icons.Error) $($result.Message)", "error", 5)
}
```

**`/accept-plan` case**:
```powershell
$planPath = Get-LatestDraftPlan -ProjectPath $projectPath
if (-not $planPath) {
    $state.Toast.Set("$($script:Icons.Warning) No draft. Run /draft-plan first", "warning", 4)
    break
}
$result = Invoke-AcceptPlan -ProjectPath $projectPath -PlanPath $planPath
if ($result.Ok) {
    $state.Toast.Set("$($script:Icons.Success) Accepted: $($result.CreatedCount) task(s)", "info", 4)
    $state.ForceDataRefresh = $true
} else {
    $state.Toast.Set("$($script:Icons.Error) $($result.Message)", "error", 5)
}
```

**Key Changes**:
- Remove direct mutation of `$snapshotRef.PlanState.Accepted`
- Use `ForceDataRefresh = $true` instead (golden: `return "refresh"`)
- All feedback based on actual backend response

### 4.3 No Python Changes Needed

The golden pattern uses:
```powershell
python -c "from mesh_server import draft_plan; print(draft_plan())"
```

This works without CLI modification. The functions `draft_plan()` and `accept_plan(path)` already exist and return JSON.

---

## 5. Test Plan

### 5.1 Unit Tests (Mock Process Runner)

**File**: `tests/test_mesh_server_adapter.ps1`

| Test | Input | Expected |
|------|-------|----------|
| `Invoke-DraftPlan` success | Mock returns `{"status":"OK","path":"..."}` | `Ok=$true, Status="OK"` |
| `Invoke-DraftPlan` blocked | Mock returns `{"status":"BLOCKED","blocking_files":["PRD"]}` | `Ok=$false, BlockingFiles=["PRD"]` |
| `Invoke-DraftPlan` timeout | Mock hangs | `Ok=$false, Message="Timeout"` |
| `Invoke-DraftPlan` parse error | Mock returns "Traceback..." | `Ok=$false, Message` contains cause |
| `Invoke-AcceptPlan` success | Mock returns `{"status":"OK","created_count":5}` | `Ok=$true, CreatedCount=5` |
| `Invoke-AcceptPlan` no draft | `PlanPath=$null` | Error before call |
| `Get-LatestDraftPlan` exists | `docs/PLANS/draft_*.md` present | Returns full path |
| `Get-LatestDraftPlan` empty | No drafts | Returns `$null` |

### 5.2 Integration Tests (Injected SnapshotLoader + Backend)

**File**: `tests/test_command_router_integration.ps1`

| Test | Setup | Action | Verify |
|------|-------|--------|--------|
| `/draft-plan` sets ForceDataRefresh | Mock backend OK | Router | `$state.ForceDataRefresh -eq $true` |
| `/draft-plan` blocked shows files | Mock backend BLOCKED | Router | Toast contains "PRD, SPEC" |
| `/accept-plan` sets ForceDataRefresh | Mock backend OK | Router | `$state.ForceDataRefresh -eq $true` |
| `/accept-plan` no draft | No draft file | Router | Toast contains "Run /draft-plan" |
| `/accept-plan` error shows message | Mock backend ERROR | Router | Toast contains error |

### 5.3 Reality Gate

- Run `python -c "from mesh_server import draft_plan; print(draft_plan())"` manually
- Run `/draft-plan` in UI, verify:
  - Toast shows actual path or error
  - `docs/PLANS/draft_*.md` created
  - Next snapshot poll shows draft exists
- Run `/accept-plan`, verify:
  - Tasks appear in `tasks.db`
  - LaneMetrics update in UI

---

## 6. Files to Create/Modify

| File | Action |
|------|--------|
| `src/AtomicMesh.UI/Private/Adapters/MeshServerAdapter.ps1` | **Create** |
| `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1` | Modify `/draft-plan` and `/accept-plan` cases |
| `src/AtomicMesh.UI/AtomicMesh.UI.psm1` | Add `. $PSScriptRoot\Private\Adapters\MeshServerAdapter.ps1` if not auto-loaded |
| `tests/test_mesh_server_adapter.ps1` | **Create** |
| `tests/test_command_router_integration.ps1` | **Create** or extend |

---

## 7. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Timeout blocks UI | Hard 2000ms timeout, fail-open with error toast |
| Python not found | Catch and show "Python not installed" toast |
| mesh_server.py import fails | Catch and show error with stderr snippet |
| JSON parse fails | Return structured error, never crash |
| Path escaping on Windows | Use `r'...'` pattern from golden |

---

**END OF STEP 1 FINDINGS**

Ready for "EXECUTE STEP 2" to implement.
