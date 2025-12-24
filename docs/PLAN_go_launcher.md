# Plan: /go "Pop and Watch" Launcher Pattern

## Problem
Current `/go` command calls `pick_task_braided()` which claims a task with `worker_id='control_panel'`, but the control panel never executes it. Result: zombie tasks.

## Solution
Change `/go` to spawn a **visible worker window** instead of claiming tasks directly.

```
BEFORE (Broken):
/go → pick_task_braided(worker_id='control_panel') → task stuck forever

AFTER (Pop and Watch):
/go → Start-Process worker.ps1 (visible window) → worker claims & executes
    → Switch to GO dashboard → show real-time progress
```

## Architecture

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│  Window A: Control Panel        │    │  Window B: Worker (spawned)     │
│  ─────────────────────────────  │    │  ─────────────────────────────  │
│  • Dashboard view               │    │  • pick_task_braided()          │
│  • Progress bars                │    │  • claude --model ... --print   │
│  • Lane status                  │    │  • complete_task()              │
│  • Command input                │    │  • Raw logs visible             │
│                                 │    │  • -NoExit: stays open on crash │
└─────────────────────────────────┘    └─────────────────────────────────┘
```

## Implementation Steps

### Step 1: Remove task claiming from /go handler
**File:** `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1`

Remove/replace the `Invoke-PickTask` call in the "go" case block. The control panel should NOT claim tasks.

### Step 2: Add worker spawning logic
**File:** `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1`

```powershell
# Inside "go" case, after guard checks pass:

# Get paths
$moduleRoot = $state.Cache.Metadata["ModuleRoot"]
$workerPath = Join-Path $moduleRoot "worker.ps1"
$projectPath = $state.Cache.Metadata["ProjectPath"]

# Spawn visible worker window
# -NoExit keeps window open on crash for error visibility
Start-Process pwsh -ArgumentList @(
    "-NoExit",
    "-File", $workerPath,
    "-ProjectPath", $projectPath,
    "-SingleShot"  # New flag: execute one task then exit
) -WorkingDirectory $projectPath

# Brief delay for worker to claim task
Start-Sleep -Milliseconds 500

# Switch to GO dashboard
$state.SetPage("GO")
$state.ForceDataRefresh = $true
$state.Toast.Set("Worker launched - check new window", "info", 3)
```

### Step 3: Add -SingleShot mode to worker.ps1
**File:** `worker.ps1`

Add parameter and logic:
```powershell
param(
    # ... existing params ...
    [switch]$SingleShot  # Exit after completing one task
)

# In main loop, after task completion:
if ($SingleShot) {
    Write-Host "`n✅ Task complete. Window will close in 5s..." -ForegroundColor Green
    Start-Sleep -Seconds 5
    exit 0
}
```

### Step 4: Handle "no tasks" case gracefully
If worker finds no pending tasks, it should show a message and exit cleanly:
```powershell
if ($pickResult.status -eq "NO_WORK") {
    Write-Host "No tasks available. Queue empty or blocked." -ForegroundColor Yellow
    if ($SingleShot) {
        Start-Sleep -Seconds 3
        exit 0
    }
}
```

## UX Flow

1. User types `/go`
2. **POOF**: New terminal window appears (Worker)
3. Worker window shows: `Picking task... Claimed T-42 [backend]... Executing...`
4. Main window: Switches to GO dashboard, shows lane activity updating
5. Worker completes: `Task complete. Window will close in 5s...`
6. Dashboard reflects task moved to 'reviewing'

## Fallback Behavior

| Scenario | Behavior |
|----------|----------|
| No pending tasks | Worker shows "Queue empty", closes after 3s |
| Worker crashes | Window stays open (-NoExit), error visible |
| Task fails | Worker logs error, marks task failed, closes |
| Multiple /go | Multiple workers spawn (parallel execution) |

## Files Changed

| File | Change |
|------|--------|
| `Invoke-CommandRouter.ps1` | Replace `Invoke-PickTask` with `Start-Process worker.ps1` |
| `worker.ps1` | Add `-SingleShot` parameter and exit logic |

## Testing

1. `/accept-plan` with 3 tasks
2. `/go` - verify worker window spawns
3. Observe task claimed and executed in worker window
4. Dashboard shows lane counts updating
5. Worker closes after completion
6. `/go` again - next task picked
7. `/go` when empty - "Queue empty" message

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| User closes worker window mid-task | Orphan reset on next startup handles it |
| pwsh not available | Fallback to `powershell` executable |
| Path issues on spawn | Use absolute paths from metadata |
