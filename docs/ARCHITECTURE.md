# Atomic Mesh Architecture (v13.1.0)

**Purpose:** System architecture documentation for the unified mesh system.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     ATOMIC MESH SYSTEM                       │
└─────────────────────────────────────────────────────────────┘

┌────────────────┐
│  Unified Start │  ← start_mesh.ps1 / mesh.bat
└────────┬───────┘
         │
    ┌────┴────┬─────────────────────┐
    │         │                     │
┌───▼────┐ ┌──▼─────────────────┐   │
│Mesh    │ │Control Panel       │   │
│Server  │ │(Unified CLI + TUI) │   │  ← v13.1: Single Surface
└───┬────┘ └──┬─────────────────┘   │
    │         │                     │
    └─────────┴─────────────────────┘
              │
         ┌────▼────┐
         │mesh.db  │  ← Single Source of Truth
         │(SQLite) │
         └─────────┘
```

### v13.1 Unified TUI

The Control Panel now integrates the dashboard with health-based view switching:

```
┌─────────────────────────────────────────────────────────────┐
│                     VIEW MODE SWITCHING                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  HEALTHY (OK status):                                       │
│    🟢 OK | pending: 3 | reviewing: 0 | workers: 2 | /ops   │
│    > _                           ← Compact status + prompt  │
│                                                             │
│  UNHEALTHY (FAIL status):                                   │
│    ┌───────────────────────────────────────────────────┐   │
│    │ Full Dashboard (EXEC + COGNITIVE columns)         │   │
│    │ Recommendations section                           │   │
│    │ [Use /compact to return]                         │   │
│    └───────────────────────────────────────────────────┘   │
│                                                             │
│  WARN (persistent or blocking):                            │
│    🟡 WARN | ... | ⚠️ Drift WARN (persistent)              │
│    > _                    ← Escalates to full after 3 checks│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**View Commands:**
- `/dash` - Toggle to full dashboard view (30s override)
- `/compact` - Toggle to compact status bar (30s override)
- Auto-switches based on health after override expires

---

## Component Responsibilities

### 1. Mesh Server (`mesh_server.py`)

**Role:** State Machine Authority

**Responsibilities:**
- Task lifecycle management (PENDING → IN_PROGRESS → REVIEWING → COMPLETED)
- Enforcement of governance rules:
  - Single-Writer Discipline (only `update_task_state()` mutates status)
  - One Gavel Rule (only reviewer sets COMPLETED)
  - Gatekeeper checks (authority validation)
- MCP tool hosting for AI agents
- Background worker coordination
- Review packet generation
- Ledger writing (audit trail)

**Critical Functions:**
```python
update_task_state(task_id, new_status, via_gavel=False)  # Single Writer
submit_review_decision(task_id, decision, notes, actor)  # One Gavel
check_gatekeeper(task_id)                                # Authority Check
```

**Database Access:**
- **Write:** Tasks, Decisions, Audit Log, Ledger
- **Read:** All tables

### 2. Control Panel (`control_panel.ps1`)

**Role:** Human Interface (Unified CLI + TUI)

**Responsibilities:**
- Slash command execution (`/go`, `/ship`, `/approve`, etc.)
- Natural language routing to AI
- Interactive dashboards and reports
- Human decision gate (approve/reject)
- Snapshot management (backup/restore)
- **v13.1:** Health-based view switching (compact vs full dashboard)

**Database Access:**
- **Write:** Via Python function calls (routes through server)
- **Read:** Direct SQLite queries for display

**Key Features:**
- Command registry with 50+ slash commands
- Auto-completion and command picker
- Two-column TUI dashboard (execution vs cognitive state)
- Real-time status indicators
- **v13.1:** Unified TUI with view modes:
  - Compact status bar when healthy
  - Full dashboard when unhealthy or on `/dash`
  - WARN persistence tracking (escalates after 3 checks)
  - Flap guard (2s debounce on view switches)
  - Override precedence (30s manual override window)

**View Mode Commands:**
- `/dash` - Toggle full dashboard view
- `/compact` - Toggle compact status bar
- `-DashboardMode` flag for always-dashboard mode

### 3. Dashboard (`dashboard.ps1`)

**Role:** Backwards Compatibility Shim (DEPRECATED)

**v13.1 Note:** The standalone dashboard is deprecated. It now launches `control_panel.ps1 -DashboardMode`.

**Original Responsibilities (now in Control Panel):**
- Auto-refreshing TUI (default 5s)
- Worker status monitoring
- Live agent event log display
- Audit log streaming
- Phase indicators (VIBE/CONVERGE/SHIP)

**Deprecation Timeline:**
- v13.1: Converted to shim
- v13.2: Planned removal

**Full Dashboard Layout (when in dashboard mode):**
```
┌─────────────────────────┬─────────────────────────┐
│ EXEC [VIBE 🟢] [🔒]     │ COGNITIVE | 🟢 READY   │
├─────────────────────────┼─────────────────────────┤
│ BACKEND  [UP]           │ PRODUCT OWNER           │
│   Task: [T-105] Auth... │   Status: 2 decisions   │
│                         │                         │
│ FRONTEND [IDLE]         │ RECENT DECISIONS        │
│   Task: (none)          │   • D-12: Use JWT       │
│                         │   • D-11: React Router  │
│ QA/AUDIT  Pending: 2    │ REASONING SUMMARY       │
│                         │   > Generating tests... │
│ LIBRARIAN [CLEAN]       │ LIVE AUDIT LOG          │
│                         │   T-105 APPROVED        │
└─────────────────────────┴─────────────────────────┘
```

---

## Data Flow

### Task Execution Flow

```
1. USER: /go
   ↓
2. Control Panel → Python call → Mesh Server
   ↓
3. Server: SELECT next pending task
   ↓
4. Server: update_task_state(T-123, 'in_progress')
   ↓
5. Worker picks up task
   ↓
6. Worker writes code
   ↓
7. Worker: update_task_state(T-123, 'reviewing')
   ↓
8. Server: generate_review_packet(T-123)
   ↓
9. Dashboard: Shows T-123 in REVIEWING status
   ↓
10. USER: /approve T-123 "looks good"
    ↓
11. Control Panel → submit_review_decision(T-123, APPROVE, via_gavel=True)
    ↓
12. Server: update_task_state(T-123, 'completed', via_gavel=True)
    ↓
13. Server: write_ledger_entry(T-123, APPROVE, HUMAN)
    ↓
14. Dashboard: Shows T-123 COMPLETED
```

### Governance Enforcement Points

**Static Safety Check** (Pre-commit)
```
Developer writes code
   ↓
python tests/static_safety_check.py
   ↓
Scans for unsafe patterns:
- task["status"] = ...           ← BLOCKED
- UPDATE tasks SET status = ...  ← BLOCKED
   ↓
Only update_task_state() allowed
```

**One Gavel Rule** (Runtime)
```
Worker tries: update_task_state(T-123, 'completed')
   ↓
Server checks: via_gavel == False
   ↓
⛔ BLOCKED: "Only reviewer can set COMPLETED"
   ↓
Correct path:
submit_review_decision(T-123, APPROVE, via_gavel=True)
```

**Gatekeeper Check** (Review Gate)
```
User: /approve T-123
   ↓
Server: check_gatekeeper(T-123)
   ↓
Load task sources: [HIPAA-SEC-01, STD-API-05]
   ↓
Check authority levels:
- HIPAA-SEC-01 → MANDATORY (must be implemented)
- STD-API-05 → DEFAULT (safe to auto-approve)
   ↓
Verify code exists for MANDATORY sources
   ↓
Pass → Allow approval
Fail → Block with specific error
```

---

## Database Schema (Key Tables)

### tasks
```sql
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY,
    type TEXT,                    -- 'backend' | 'frontend' | 'qa'
    desc TEXT,
    status TEXT,                  -- 'pending' | 'in_progress' | 'reviewing' | 'completed'
    archetype TEXT,               -- 'PLUMBING' | 'FEATURE' | 'SEC' | etc.
    source_ids TEXT,              -- JSON array: ["HIPAA-01", "STD-02"]
    override_justification TEXT,  -- Human override reason
    files_changed TEXT,           -- JSON array of modified files
    updated_at INTEGER            -- Unix timestamp
);
```

### review_packets
```sql
-- Stored as JSON files in control/state/reviews/
{
  "task_id": 123,
  "generated_at": "2025-12-09T12:00:00Z",
  "snapshot_hash": "abc123...",
  "claims": {
    "description": "...",
    "archetype": "SEC",
    "override_justification": null
  },
  "evidence": {
    "code_refs": {"HIPAA-01": ["auth.py:45"]},
    "paired_test": {"id": 124, "status": "completed"}
  },
  "gatekeeper": {
    "ok": true,
    "errors": [],
    "warnings": []
  }
}
```

### release_ledger
```jsonl
-- Append-only JSONL in control/state/release_ledger.jsonl
{"timestamp": "2025-12-09T12:00:00Z", "task_id": 123, "decision": "APPROVE", "actor": "HUMAN", "notes": "...", "resolved_authority": [...]}
{"timestamp": "2025-12-09T12:05:00Z", "task_id": 124, "decision": "REJECT", "actor": "AUTO", "notes": "...", "resolved_authority": [...]}
```

---

## Governance Principles

### 1. Single-Writer Discipline

**Rule:** Only `update_task_state()` may modify task status.

**Enforcement:**
- Static: `tests/static_safety_check.py` scans for violations
- Runtime: All mutations route through single function
- Audit: Ledger records every state transition

**Violations:**
```python
# ❌ FORBIDDEN
task["status"] = "completed"
conn.execute("UPDATE tasks SET status='completed' WHERE id=?", (tid,))

# ✅ CORRECT
update_task_state(task_id, "completed", via_gavel=True)
```

### 2. One Gavel Rule

**Rule:** Only `submit_review_decision()` can set status to COMPLETED.

**Enforcement:**
- `update_task_state()` checks `via_gavel` parameter
- Only reviewer calls have `via_gavel=True`
- Worker cannot self-approve

**Flow:**
```python
# Worker finishes task
update_task_state(tid, "reviewing")  # ✅ Allowed

# Worker tries to complete
update_task_state(tid, "completed")  # ⛔ BLOCKED

# Reviewer approves
submit_review_decision(tid, "APPROVE", via_gavel=True)
  → update_task_state(tid, "completed", via_gavel=True)  # ✅ Allowed
```

### 3. Authority Hierarchy

**Levels:**
- **MANDATORY** (HIPAA, GDPR): Must be implemented, no override
- **STRONG** (PRO best practices): Override requires justification
- **DEFAULT** (STD engineering): Implicit, safe to auto-approve
- **ADVISORY**: Suggestions, can be ignored

**Gatekeeper Logic:**
```python
if source.authority == "MANDATORY":
    if not code_exists(source_id):
        return BLOCKED("MANDATORY source not implemented")

if source.authority == "STRONG":
    if not code_exists(source_id) and not has_justification(task):
        return BLOCKED("STRONG source not implemented or justified")

if source.authority == "DEFAULT":
    return PASS  # Safe to auto-approve
```

---

## Startup Sequence

### 1. Pre-Flight Checks

```powershell
start_mesh.ps1
   ↓
Check for existing server
   ↓
If exists → Prompt to kill
   ↓
Verify mesh_server.py exists
```

### 2. Server Launch

```powershell
Start-Process python mesh_server.py -WindowStyle Minimized
   ↓
Write PID to control/state/_runtime/mesh_server.pid
   ↓
Wait 3 seconds for initialization
   ↓
Check if server still running (not crashed)
   ↓
NOTE: This is a single-shot launch
      No auto-restart, no watchdog loop
      Server must pass /health and /drift before production use
```

### 3. Interface Launch

```powershell
Start control_panel.ps1 (new window)
   ↓
Wait 1 second
   ↓
Start dashboard.ps1 (new window)
```

### 4. Verification

```
Server PID displayed
Components listed
Shutdown instructions provided
```

---

## Shutdown Sequence

### Graceful Shutdown

**Recommended:**
```powershell
.\stop_mesh.ps1
   ↓
Read PID from control/state/_runtime/mesh_server.pid
   ↓
Stop-Process (graceful SIGTERM)
   ↓
Wait up to 5 seconds for clean exit
   ↓
Remove PID file
```

**Effect:**
```
1. Server receives stop signal
   → Triggers cleanup
   → Closes DB connections
   → Exits MCP server

2. Control Panel (manual close)
   → /quit or Ctrl+C
   → No state to save (read-only)

3. Dashboard (manual close)
   → Ctrl+C or close window
   → No state to save (read-only)
```

### Emergency Shutdown

**If graceful shutdown fails:**
```powershell
.\stop_mesh.ps1 -Force    # Force kill without waiting
```

**Nuclear option:**
```powershell
# Kill all python processes running mesh
Get-Process python | Where-Object { $_.CommandLine -like "*mesh*" } | Stop-Process -Force

# Kill all PowerShell instances running mesh UIs
Get-Process powershell | Where-Object { $_.CommandLine -like "*control_panel*" } | Stop-Process -Force
Get-Process powershell | Where-Object { $_.CommandLine -like "*dashboard*" } | Stop-Process -Force
```

---

## File Structure

```
atomic-mesh/
├── mesh_server.py               ← MCP server (Python)
├── start_mesh.ps1               ← Unified startup (PowerShell)
├── stop_mesh.ps1                ← Clean shutdown (PowerShell)
├── mesh.bat                     ← Quick launcher (Windows)
├── control_panel.ps1            ← Interactive CLI (PowerShell)
├── dashboard.ps1                ← Live TUI (PowerShell)
├── mesh.db                      ← SQLite database
│
├── control/
│   ├── state/
│   │   ├── tasks.json           ← JSON state backup
│   │   ├── provenance.json      ← Code provenance map
│   │   ├── coverage.json        ← Source coverage report
│   │   ├── release_ledger.jsonl ← Audit trail (append-only)
│   │   ├── reviews/
│   │   │   ├── T-123.json       ← Review packets
│   │   │   └── T-124.json
│   │   └── _runtime/
│   │       └── mesh_server.pid  ← Server PID for clean shutdown
│   │
│   └── snapshots/
│       ├── snapshot_20251209_120000_manual.zip
│       └── snapshot_20251209_130000_pre_release.zip
│
├── docs/
│   ├── STARTUP_GUIDE.md
│   ├── ARCHITECTURE.md          ← This file
│   ├── RELEASE_CHECKLIST.md
│   ├── INCIDENT_LOG.md
│   ├── OPERATIONS.md
│   └── sources/
│       ├── SOURCE_REGISTRY.json
│       ├── DOMAIN_RULES.md
│       └── STD_ENGINEERING.md
│
├── tests/
│   ├── static_safety_check.py   ← Governance enforcer
│   ├── run_ci.py                ← Golden Thread
│   └── test_constitution.py     ← Contract tests
│
└── logs/
    ├── mesh.log                 ← Worker chain-of-thought
    └── audit.log                ← System audit trail
```

---

## Extension Points

### Adding New Slash Commands

Edit `control_panel.ps1`:

```powershell
$Global:Commands = [ordered]@{
    "mycommand" = @{ Desc = "My custom command"; HasArgs = $true }
}

# Add switch case in Invoke-SlashCommand
"mycommand" {
    Write-Host "  Executing my command..." -ForegroundColor Cyan
    # Your logic here
}
```

### Adding New MCP Tools

Edit `mesh_server.py`:

```python
@mcp.tool()
def my_custom_tool(param: str) -> str:
    """
    My custom MCP tool.

    Args:
        param: Description

    Returns:
        Result description
    """
    # Your logic here
    return result
```

### Adding New Dashboard Panels

Edit `dashboard.ps1`, modify `Draw-Dashboard` function to add new rows.

---

## Monitoring and Observability

### Health Checks

```
/health → Runs 5 checks:
1. Database connectivity
2. Database schema integrity
3. State file consistency (JSON ↔ SQLite)
4. Review packet freshness
5. Timestamp migration status
```

### Drift Detection

```
/drift → Checks for staleness:
1. Review packets older than 24h
2. In-progress tasks stuck > 2h
3. Unresolved decisions > 7 days
```

### Audit Trail

```
/ledger → Shows:
- All review decisions (APPROVE/REJECT)
- Actor attribution (HUMAN/AUTO/BATCH)
- Authority snapshot at decision time
- Full forensic reconstruction
```

---

## Performance Considerations

### Database Locking

**Issue:** SQLite uses file-level locking.

**Mitigation:**
- WAL mode enabled (Write-Ahead Logging)
- Short transactions
- Read-mostly workload (Control Panel + Dashboard)
- Only Server writes to critical tables

### Startup Time

**Measured:**
- Server: ~3 seconds to initialize
- Control Panel: <1 second to display
- Dashboard: <1 second to first render

**Bottlenecks:**
- Python import time (~1s)
- SQLite connection (~0.5s)
- Initial schema validation (~0.5s)

---

*Architecture v13.0.1 - Governance Hardening Complete*

---

## v14.0 Cybernetic Loop Closure (Enforcement Matrix)

**Status:** ✅ Fully Closed-Loop System  
**Last Verified:** 2025-12-12 (v14.0.1 burn-in)

### The 6 Gates

| # | Gate Name | Purpose | UI Enforcement | Backend Enforcement |
|---|-----------|---------|----------------|---------------------|
| 1 | **Gavel Rule** | Only review process can complete tasks | N/A | mesh_server.py:546 |
| 2 | **Optimization Gate** | Entropy check required before approval | N/A | mesh_server.py:6762-6786 |
| 3 | **Risk Gate** | HIGH risk requires QA verification | control_panel.ps1:1886-1932 | mesh_server.py:4426-4618 |
| 4 | **Context Gate** | Strategic planning blocked in BOOTSTRAP | control_panel.ps1:717-747 | mesh_server.py:998,1074,1174 |
| 5 | **Router READONLY** | Status queries never create tasks | N/A | mesh_server.py:10661-10673 |
| 6 | **Kickback** | Clarity loop with audit trail | control_panel.ps1 | mesh_server.py (tool) |

### Enforcement Points (Code Locations)

#### Gate 1: The Gavel (mesh_server.py:546)
```python
if new_status == "completed" and not via_gavel:
    return "⛔ SECURITY VIOLATION: 'completed' status can only be set via submit_review_decision"
```

#### Gate 2: Optimization (mesh_server.py:6762-6786)
```python
if decision == "APPROVE":
    notes_lower = notes.lower()
    has_entropy_check = "entropy check:" in notes_lower and "passed" in notes_lower
    has_waiver = "optimization waived:" in notes_lower
    has_override = "captain_override:" in notes_lower and "entropy" in notes_lower
    
    if not (has_entropy_check or has_waiver or has_override):
        return "BLOCKED: MISSING_ENTROPY_CHECK"
```

#### Gate 3: Risk (control_panel.ps1:1886-1932)
```powershell
$query = "SELECT id, desc, risk, qa_status FROM tasks 
         WHERE risk = 'HIGH' AND qa_status != 'PASS'"
$highRiskTasks = Invoke-Query -Query $query

if ($highRiskTasks -and $highRiskTasks.Count -gt 0) {
    Write-Host "🛑 SHIP BLOCKED: HIGH RISK TASKS NOT VERIFIED"
    return  # Block ship unless --force
}
```

#### Gate 4: Context (mesh_server.py:998-1009)
```python
# In refresh_plan_preview, draft_plan, accept_plan
try:
    readiness = json.loads(get_context_readiness())
    if readiness.get("status") == "BOOTSTRAP":
        return json.dumps({
            "status": "BLOCKED",
            "reason": "BOOTSTRAP_MODE",
            "message": "Strategic planning blocked - complete PRD, SPEC, DECISION_LOG first"
        })
except Exception:
    pass  # Fail open if readiness check fails
```

#### Gate 5: Router READONLY (mesh_server.py:10661-10673)
```python
READONLY_PATTERNS = [
    (r"^(status|health|drift|ops|help|tasks|list|version|uptime)$", "/ops"),
    (r"^show\s+(me\s+)?(the\s+)?(status|health|drift|tasks|ops)", "/ops"),
    (r"^(what\s+is|what's)\s+(the\s+)?(status|health|drift)", "/status"),
    (r"^(check|show|list)\s+(status|health|tasks|drift|ops)", "/ops"),
]
# Checked FIRST before intent matching
```

### Escape Hatches (Logged Overrides)

| Gate | Override Mechanism | Logging | Location |
|------|-------------------|---------|----------|
| **Optimization** | `CAPTAIN_OVERRIDE: ENTROPY` in review notes | ✅ logs/decisions.log | mesh_server.py:6777-6786 |
| **Risk** | `/ship --force` flag | ✅ logs/decisions.log | control_panel.ps1:1925 |
| **Context** | None (fails open on check error) | ⚠️ Warning only | mesh_server.py:1008 |

### Fail-Open Philosophy

**Principle:** Gates fail gracefully to prevent deadlock, but safety-critical gates remain strict.

| Scenario | Behavior | Reason |
|----------|----------|--------|
| **Readiness check fails** | Allow operation | Prevents deadlock if check tool breaks |
| **BOOTSTRAP mode** | Block strategic, allow tactical | Maintains velocity for urgent fixes |
| **Missing entropy proof** | Block APPROVE (strict) | Safety-critical, must be explicit |
| **HIGH risk without QA** | Block /ship (strict) | Prevents production incidents |

**What Does NOT Fail-Open:**
- Gavel Rule (status=completed)
- Optimization Gate (approval without proof)
- Risk Gate (shipping HIGH risk without PASS)

### Burn-In Status

**Last Test:** 2025-12-12 (v14.0.1)  
**Results:** ✅ All 6 gates verified operational  
**Report:** docs/RELEASES/v14.0-burnin.md

| Gate | Test Method | Status |
|------|------------|--------|
| BOOTSTRAP | Live backend test | ✅ PASS |
| Router READONLY | Code review | ✅ PASS |
| Kickback | Code review | ✅ PASS |
| Optimization | Code review | ✅ PASS |
| Risk | Code review | ✅ PASS |
| Fail-Open | Code review | ✅ PASS |

---

**System Status:** 🔒 **Fully Closed-Loop Cybernetic**

