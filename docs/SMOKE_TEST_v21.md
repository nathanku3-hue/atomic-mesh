# v21.0 EXEC Dashboard - Manual Smoke Test Checklist

**Date**: _______________
**Tester**: _______________
**Environment**: Windows / PowerShell _____ / Terminal: _____

---

## Pre-flight

- [ ] Fresh database (delete `mesh.db` or use clean repo)
- [ ] No workers running initially
- [ ] Verify DB path alignment:
  - [ ] Control panel shows: `DB: <path>\mesh.db` at startup
  - [ ] Worker shows same path when started
  - [ ] Both point to SAME file

**DB Path Shown**: _______________

---

## SQL Helpers (for skipped test validations)

Use `tests/manual_validation_helpers.sql` for:
- RED decision insertion
- All-completed state setup
- Debug queries

---

## Step 1: Fresh Start - EXEC Renders Empty State

```powershell
.\control_panel.ps1
```

**Expected**:
- [ ] EXEC screen visible (not PLAN)
- [ ] "(no plan)" in right panel
- [ ] "(no active tasks)" in left panel
- [ ] "(no workers registered)" in right panel
- [ ] "(no alerts)" shows green
- [ ] "Next action: /accept-plan to load tasks"

**PASS / FAIL**: _____

---

## Step 2: /draft-plan Switches to PLAN Screen

```
/draft-plan
```

**Expected**:
- [ ] PLAN screen renders (stream slots, classic layout)
- [ ] Draft plan preview shows
- [ ] No EXEC elements visible

**PASS / FAIL**: _____

---

## Step 3: /accept-plan + /go Shows Plan Identity

```
/accept-plan
/go
```

**Expected**:
- [ ] EXEC screen returns after /go
- [ ] Plan name + hash visible in right panel
- [ ] Lane progress bars show task counts
- [ ] "Next action" updates to "/go to pick task"

**PASS / FAIL**: _____

---

## Step 4: Start Workers - Concurrency Sanity Check

### 4a. Single Worker First

**Terminal 1** (keep control panel running):
```powershell
# Start ONLY backend worker first
.\worker.ps1 -Type backend -Tool claude
```

**In control panel**:
```
/workers
```

**Expected**:
- [ ] Single worker appears in roster
- [ ] Worker claims ONE task (if pending backend tasks exist)
- [ ] `allowed_lanes: backend, qa, ops`
- [ ] Heartbeat updates (last_seen changes on refresh)

**PASS / FAIL**: _____

### 4b. Add Second Worker - Verify Parallelism

**Terminal 2**:
```powershell
# Start frontend worker
.\worker.ps1 -Type frontend -Tool claude
```

**In control panel, run**:
```
/workers
```

**Expected**:
- [ ] BOTH workers appear in roster
- [ ] `last_seen` shows recent (< 30s = green indicator)
- [ ] `allowed_lanes` matches worker type:
  - backend: `backend, qa, ops`
  - frontend: `frontend, docs`
- [ ] EXEC dashboard shows 2 workers in right panel
- [ ] Two active tasks (one per worker) if tasks exist in both lanes
- [ ] Lane rules hold: frontend worker does NOT claim backend tasks

**PASS / FAIL**: _____

---

## Step 5: Run 30-60s - Heartbeats + Task Flow

**Watch for**:
- [ ] Heartbeat `last_seen` updates (run `/workers` again)
- [ ] Active tasks appear in left panel when claimed
- [ ] Lane progress bars update as tasks complete
- [ ] CPU stays flat (no spin loops)
- [ ] "Next action" suggestions make sense

**PASS / FAIL**: _____

---

## Micro-Check A: Refresh Correctness

```
/refresh
/refresh
```

**Expected**:
- [ ] Still on EXEC screen (no flip to PLAN)
- [ ] No screen artifacts
- [ ] Timestamps/last_seen change between refreshes

**PASS / FAIL**: _____

---

## Micro-Check B: Resize Torture

1. Make terminal narrower (< 80 cols)
2. Make terminal wider (> 120 cols)
3. Make terminal shorter (< 30 rows)

**Expected**:
- [ ] Text truncates gracefully (no overflow)
- [ ] No "leaked" rows from previous render
- [ ] No crashes or hangs
- [ ] Borders remain aligned

**PASS / FAIL**: _____

---

## Micro-Check C: "No Work" Semantics

**Setup**: Ensure all tasks are completed (or empty queue)

```
/go
```

**Expected**:
- [ ] Returns "NO_WORK" or friendly "No tasks available" message
- [ ] "Next action" updates to suggest next step (e.g., "/draft-plan")

**PASS / FAIL**: _____

---

## Skipped Test Validation 1: RED Decision Alert

**Setup**: Create a RED priority decision

```sql
-- Via sqlite3 or your preferred method
INSERT INTO decisions (question, status, priority) VALUES ('Critical question?', 'pending', 'red');
```

**Then run**:
```
/status
```
or check EXEC dashboard alerts panel

**Expected**:
- [ ] RED_DECISION alert appears with level "error"
- [ ] Alert text mentions critical/red decision

**PASS / FAIL**: _____

---

## Skipped Test Validation 2: All Completed -> NO_WORK

**Setup**: Complete all pending tasks

```sql
UPDATE tasks SET status='completed' WHERE status='pending';
```

**Then run**:
```
/go
```

**Expected**:
- [ ] Returns NO_WORK status
- [ ] Dashboard shows 100% progress
- [ ] "Next action" suggests appropriate next step

**PASS / FAIL**: _____

---

## Worker Lane Validation

**Test**: Lane rules are server-enforced

### Setup
1. With both workers running, identify:
   - A backend task ID: T-_____
   - A frontend task ID: T-_____

### Check 1: /workers shows correct allowed_lanes
```
/workers
```

**Expected**:
- [ ] Backend worker: `allowed_lanes: backend, qa, ops`
- [ ] Frontend worker: `allowed_lanes: frontend, docs`

### Check 2: /explain shows correct claim info
```
/explain <backend_task_id>
```

**Expected for backend task**:
- [ ] If claimed: worker_id starts with `backend_`
- [ ] If unclaimed: shows "(not claimed)"
- [ ] NEVER claimed by `frontend_*` worker

```
/explain <frontend_task_id>
```

**Expected for frontend task**:
- [ ] If claimed: worker_id starts with `frontend_`
- [ ] If unclaimed: shows "(not claimed)"
- [ ] NEVER claimed by `backend_*` worker

### Check 3: Lane enforcement holds
- [ ] Over 30-60s run, no lane violations observed
- [ ] Backend tasks only in backend worker's task_ids
- [ ] Frontend tasks only in frontend worker's task_ids

**PASS / FAIL**: _____

---

## Summary

| # | Check | Status |
|---|-------|--------|
| 0 | Pre-flight: DB path alignment | |
| 1 | Fresh start empty state | |
| 2 | /draft-plan -> PLAN screen | |
| 3 | /accept-plan + /go -> EXEC | |
| 4a | Single worker claims task | |
| 4b | Both workers + parallelism | |
| 5 | 30-60s run stability | |
| A | Refresh correctness | |
| B | Resize torture | |
| C | No work semantics | |
| S1 | RED decision alert (skipped test) | |
| S2 | All completed NO_WORK (skipped test) | |
| L | Worker lane validation | |

**Overall Result**: PASS / FAIL

**Notes**:
```
(Any issues, observations, or screenshots to attach)
```

---

## Screenshots to Capture

1. [ ] EXEC with active workers (both workers visible, tasks in progress)
2. [ ] `/workers` output showing roster with last_seen
3. [ ] `/explain <task_id>` output for a running task

---

*Checklist generated for v21.0 EXEC Dashboard verification*
