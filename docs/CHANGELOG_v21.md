# v21.0 EXEC Dashboard - Changelog

## Summary

Rebuilt the `/go` EXEC dashboard to provide live execution monitoring without interfering with the existing `/draft-plan` PLAN dashboard.

## Features

### Phase 0: Screen Isolation
- Added `$Global:DashboardScreen` mode variable (`PLAN` | `EXEC`)
- `/draft-plan` switches to PLAN screen
- `/go` switches to EXEC screen
- `/clear`, `/refresh`, `/help` preserve current screen mode
- Screen mode persists across refreshes

### Phase 1: Telemetry & Commands

#### New MCP Tools (mesh_server.py)
- **`get_exec_snapshot()`**: Returns comprehensive JSON snapshot for EXEC dashboard
  - `plan`: hash, name, version, path
  - `stream`: current focus
  - `security`: read_only state
  - `scheduler`: rotation_ptr, last_pick decision
  - `lanes`: per-lane stats (active, pending, done, blocked)
  - `workers`: roster with heartbeat info
  - `active_tasks`: in-progress tasks with metadata
  - `alerts`: system alerts (WORKTREE_DIRTY, TASKS_BLOCKED, RED_DECISION)

- **`worker_heartbeat()`**: Worker registration and heartbeat tracking
  - Creates `worker_heartbeats` table on first call (idempotent)
  - Tracks worker_id, worker_type, allowed_lanes, task_ids, last_seen
  - Enables worker roster visibility in EXEC dashboard

#### New Commands (control_panel.ps1)
- **`/workers`**: Shows worker roster with heartbeat info
  - Worker ID, type, allowed lanes
  - Last seen with color coding (green < 60s, yellow < 300s, red otherwise)
  - Current task IDs
  - Falls back to inferring from active tasks if no heartbeats

- **`/explain <task_id>`**: Deep-dive task explanation
  - Identity: ID, lane, status, description
  - Worker: claimed by, claim age
  - Dependencies: list with status (blocking info)
  - Hierarchy: parent, children
  - Scheduler: pick reason, lane pointer

### Phase 2: EXEC Dashboard UI

Two-column layout answering operator questions:

**Left Column:**
- Lane progress bars with percentages
- Active tasks list (up to 5)
- System alerts

**Right Column:**
- Plan identity (name, hash, version)
- Scheduler state (last pick, rotation pointer)
- Worker roster (up to 5)
- "Next action" suggestions

### Worker Integration (worker.ps1)
- Heartbeat sent before polling (non-blocking)
- Heartbeat updated when task is picked
- Failure is non-fatal (worker continues)

## Test Coverage

### Automated Tests
- **test_exec_dashboard.py**: 14 tests (1 skipped)
  - Schema validation
  - Lane statistics computation
  - Active task population
  - Alert generation (blocked, RED decision)
  - Worker heartbeat CRUD
  - Worker visibility in snapshot
  - Scheduler state visibility

- **test_go_command.py**: 5 tests (1 skipped)
  - NO_WORK when empty
  - Task picking and IN_PROGRESS marking
  - Task details return
  - /g alias registration
  - URGENT priority preemption

### Skipped Tests (Manual Verification Required)
1. `test_alerts_for_red_decisions`: SQLite locking in parallel test runner
   - Manual: Create RED decision, verify alert in /status
2. `test_no_work_when_all_completed`: SQLite locking in parallel test runner
   - Manual: Complete all tasks, verify /go returns NO_WORK

## Database Changes

### New Table: `worker_heartbeats`
```sql
CREATE TABLE IF NOT EXISTS worker_heartbeats (
    worker_id TEXT PRIMARY KEY,
    worker_type TEXT,
    allowed_lanes TEXT,  -- JSON array
    task_ids TEXT,       -- JSON array
    status TEXT DEFAULT 'ok',
    last_seen INTEGER,
    created_at INTEGER
);
```

### Migration Safety
- `CREATE TABLE IF NOT EXISTS` - idempotent
- Table existence checked before queries
- Same WAL mode + busy_timeout as existing code
- No breaking changes to existing tables

## Null-Safety

All components handle missing data gracefully:
- `get_exec_snapshot()`: All fields have safe defaults, wrapped in try/except
- `Draw-ExecScreen`: Fallback snapshot, placeholder text for empty states
- `/workers`: Falls back to inferring from active tasks
- `/explain`: Handles missing deps, parent, children

## Non-Goals (Preserved)
- PLAN dashboard unchanged
- Scheduler behavior unchanged
- No new heavy dependencies

## Files Changed

### Modified
- `control_panel.ps1`: Screen mode, /workers, /explain, Draw-ExecScreen
- `mesh_server.py`: get_exec_snapshot, worker_heartbeat MCP tools
- `worker.ps1`: Heartbeat integration

### Added
- `tests/test_exec_dashboard.py`: 15 tests
- `docs/SMOKE_TEST_v21.md`: Manual verification checklist
- `docs/CHANGELOG_v21.md`: This file

## Test Results

```
tests/test_exec_dashboard.py: 14 passed, 1 skipped
tests/test_go_command.py: 5 passed, 1 skipped
run_ci.py: 12 passed, CI PASSED
Total: 31 passed, 2 skipped
```

## Manual Smoke Test

See `docs/SMOKE_TEST_v21.md` for comprehensive checklist covering:
- Fresh start empty state
- Screen switching (PLAN <-> EXEC)
- Worker roster updates
- Refresh correctness
- Resize handling
- NO_WORK semantics
- Skipped test validations
- Lane enforcement verification
