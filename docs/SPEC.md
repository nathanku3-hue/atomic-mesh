# Technical Specification: Atomic Mesh Control Panel

**Author**: Engineering Team | **Date**: 2025-12-14 | **Version**: 16.0

---

## Overview
The Atomic Mesh Control Panel is a PowerShell-based TUI that provides real-time visibility into the development pipeline, task management, and verification gates.

---

## Data Model

### Pipeline Status Model
```
PipelineStatus {
    stages: Stage[]           // Array of 6 stages
    immediate_next: string    // Suggested next action
    critical_missing: string[] // RED stage descriptions
    recommended_actions: Action[]
    suggested_next: { command, reason }
    source: string            // Data source attribution
}

Stage {
    name: string              // Context|Plan|Work|Optimize|Verify|Ship
    state: string             // GREEN|YELLOW|RED|GRAY
    hint: string              // Short action hint
    reason: string            // Detailed reason (empty if GREEN)
}
```

### Snapshot Model (JSONL)
```
Snapshot {
    ts: string                // ISO 8601 UTC timestamp
    mode: string              // EXECUTION|BOOTSTRAP|PRE_INIT
    stages: { [name]: { state, reason? } }
    selected_task: string|null
    source: string
}
```

### Task Model (existing)
Tasks are stored in SQLite with columns: id, status, risk, qa_status, notes, created_at, updated_at.

---

## API

### Internal Functions

**Build-PipelineStatus**
- Input: `$SelectedRow` (optional task row), `$RuntimeSignals` (optional cached signals)
- Output: `PipelineStatus` hashtable
- Behavior: Queries readiness.py, task DB, git status to derive stage states and reasons

**Write-PipelineSnapshotIfNeeded**
- Input: `$PipelineData`, `$SelectedTaskId` (optional)
- Output: None (side effect: appends to JSONL file)
- Behavior: Only writes when any stage is YELLOW/RED, dedupes via hash+2s debounce

**Draw-PipelinePanel**
- Input: `$StartRow`, `$HalfWidth`, `$PipelineData`
- Output: Next row number
- Behavior: Renders pipeline arrow display and reason lines

### Stage Derivation Rules

| Stage | GREEN | YELLOW | RED |
|-------|-------|--------|-----|
| Context | EXECUTION mode | BOOTSTRAP mode | PRE_INIT mode |
| Plan | Queued tasks exist | All tasks terminal | No tasks exist |
| Work | Active tasks running | Queued but none running | Blocked tasks only |
| Optimize | Entropy proof present | No proof on task | N/A (GRAY) |
| Verify | No HIGH risk unverified | N/A | HIGH risk unverified |
| Ship | Clean git + verify green | Dirty working tree | Verify RED |

---

## Security

### Data Handling
- No credentials or secrets stored in snapshot files
- Snapshot files contain only status metadata (state names, task IDs, timestamps)
- Reason strings are deterministic and derived from existing data

### File Permissions
- Snapshot directory: `logs/` created with standard user permissions
- No elevation required for any control panel operation

### Input Validation
- Task IDs are sanitized before SQL queries (parameterized via Invoke-Query)
- Git commands use `--porcelain` flag to avoid shell injection via status output

### Audit Trail
- All state changes logged to release_ledger.jsonl (existing)
- Pipeline snapshots provide additional debugging context for Yellow/Red states

---

## Performance

### Render Budget
- Target: Full dashboard render under 200ms
- Build-PipelineStatus: ~50ms (readiness.py + 5-6 DB queries)
- Draw-PipelinePanel: ~10ms (pure rendering)
- Snapshot write: ~5ms (append-only, no seek)

### Deduplication
- Hash-based dedupe prevents redundant writes
- 2-second debounce prevents spam during rapid redraws

---

## Dependencies
- PowerShell 5.1+
- Python 3.8+ (for readiness.py)
- SQLite (via System.Data.SQLite or built-in)
- Git CLI

---

*Specification version: 16.0*
