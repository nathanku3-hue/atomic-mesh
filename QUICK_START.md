# Atomic Mesh - Quick Start (v13.0.1)

## Launch Everything

```bash
.\mesh.bat              # Windows batch launcher
```

**OR**

```powershell
.\start_mesh.ps1        # PowerShell script
```

**What Starts:**
- ✅ Mesh Server (background)
- ✅ Control Panel (CLI)
- ✅ Dashboard (TUI)

---

## Server Only (Headless)

```powershell
.\start_mesh.ps1 -ServerOnly
```

---

## Control Panel Quick Commands

```
/ops        Operator dashboard (health, drift, backups)
/go         Execute next task
/status     System status
/ship       Pre-flight + release
/health     Health sentinel
/drift      Staleness check
/reviews    Pending review queue
/approve    Approve task
/ledger     Audit trail
```

---

## Governance Checklist (Before Deploy)

```powershell
# 1. Static safety check
python tests/static_safety_check.py

# 2. CI gate
python tests/run_ci.py

# 3. Health + Drift
# In Control Panel:
/health
/drift

# 4. Ship preflight
/ship                    # Dashboard view
/ship --confirm "v1.0"   # Execute if green
```

---

## Shutdown

```powershell
.\stop_mesh.ps1           # Clean shutdown using PID file
```

**Manual:**
```powershell
Stop-Process -Id <PID>    # Find PID from startup output
# Then close Control Panel + Dashboard windows
```

---

## Emergency Stop

```powershell
.\stop_mesh.ps1 -Force    # Force kill
# OR:
Get-Process python | Where-Object { $_.CommandLine -like "*mesh*" } | Stop-Process
```

---

## First-Time Setup

```
1. /init              # Auto-detect project profile
2. Edit docs/ACTIVE_SPEC.md
3. /plan_gaps         # Generate tasks from specs
4. /go                # Start execution
```

---

## Key Files

- `mesh.db` - Task database (state machine)
- `control/state/tasks.json` - JSON state backup
- `control/state/release_ledger.jsonl` - Audit trail
- `docs/RELEASE_CHECKLIST.md` - Pre-production gate

---

## Ops Knobs

- `MESH_STALE_IN_PROGRESS_SECS` - Crash recovery reaper window (default `1800`); tasks older than this are re-queued from `in_progress` → `pending`.
- `MESH_SQLITE_WAL_AUTOCHECKPOINT` - WAL auto-checkpoint pages (default `1000`); set `0` to disable auto-checkpointing.
- `MESH_REQUIRE_WORKER_ROLE` - When set (`1`/`true`/`yes`), deny scheduler picks unless a worker role can be inferred (fail-closed production mode).
- `LIBRARIAN_RECENT_TTL` - Seconds to cache recent-file/lock scans (default `13`); set lower for sub-second dashboard ticks, or bypass per-call with `bypass_cache=True`.
- `MESH_WORKER_HEARTBEAT_SECS` - Worker heartbeat interval for EXEC dashboard (default `30`; min `5`).
- `MESH_LEASE_RENEW_SECS` - Lease renewal interval while a task is running (default `30`; min `5`).

### Worker Leases (Operational Notes)

- Workers claim tasks with a `lease_id` (claim token) and periodically renew it via `renew_task_lease()` to keep `updated_at` fresh.
- Renewal is best-effort: if renewals fail long enough to exceed `MESH_STALE_IN_PROGRESS_SECS`, the stale reaper will re-queue the task back to `pending` for crash recovery.
- `complete_task()` is fail-closed: if `(worker_id, lease_id)` no longer matches (task reaped/reassigned), completion is rejected with `reason=LEASE_MISMATCH` (and logged as `COMPLETE_TASK_DENY`).

---

## Governance Rules (v13.0.1)

✅ **Static Safety Check** passes (no unsafe status mutations)
✅ **One Gavel Rule** enforced (only reviewer sets COMPLETED)
✅ **Single-Writer Discipline** (only `update_task_state()` modifies status)
✅ **Health + Drift Sentinels** passing
✅ **CI Golden Thread** isolated from production state

---

*Quick Start v13.0.1 - Ready for production governance*
