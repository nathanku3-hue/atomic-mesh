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

## Governance Rules (v13.0.1)

✅ **Static Safety Check** passes (no unsafe status mutations)
✅ **One Gavel Rule** enforced (only reviewer sets COMPLETED)
✅ **Single-Writer Discipline** (only `update_task_state()` modifies status)
✅ **Health + Drift Sentinels** passing
✅ **CI Golden Thread** isolated from production state

---

*Quick Start v13.0.1 - Ready for production governance*
