# Atomic Mesh Operations Truth Table (v12.2.1)

**Purpose:** Maps manual claims to actual code. If they disagree, this file is wrong.
**Last Verified:** 2025-12-09

---

## 1. /ship Preflight Sequence

| Manual Step | Command | Code Location | Expected Output |
|-------------|---------|---------------|-----------------|
| Health Check | `/ship --confirm` | `control_panel.ps1:1767-1776` | ABORTS if `HEALTH: FAIL` |
| Drift Check | `/ship --confirm` | `control_panel.ps1:1778-1788` | ABORTS if `DRIFT: FAIL` |
| CI Gate | `/ship --confirm` | `control_panel.ps1:1790-1801` | ABORTS if exit code != 0 |

**Order:** Health → Drift → CI (sequential, any FAIL stops)

---

## 2. Restore Workflow

| Manual Step | Command | Code Location | Validation |
|-------------|---------|---------------|------------|
| Preview | `/restore <zip>` | `control_panel.ps1:3461-3485` | Checks .zip extension, file existence |
| Confirm | `/restore_confirm <zip>` | `control_panel.ps1:3488-3528` | **Re-validates** extension + existence |
| Backend | `restore_snapshot()` | `mesh_server.py:1769-1786` | Validates zip format + structure |

**Defense in Depth:** CLI validates twice, backend validates format + contents.

---

## 3. Migration Lock

| Manual Step | Command | Code Location | Expected Output |
|-------------|---------|---------------|-----------------|
| Dry Run | `/migrate_timestamps` | `mesh_server.py:2120-2122` | If stamp exists: `✅ System is already migrated` |
| Apply | `/migrate_timestamps_apply` | `mesh_server.py:2116-2118` | If stamp exists: `⛔ ABORT: Migration already applied` |
| Stamp File | - | `control/state/_migrations/timestamps_v12_2.done` | Created on first successful apply |

**Idempotency:** Stamp file prevents re-run. Dry run is safe to repeat.

---

## 4. One Gavel Rule

| Manual Claim | Code Location | Enforcement |
|--------------|---------------|-------------|
| "COMPLETE only via Gavel" | `mesh_server.py:545-546` | `if new_status == "completed" and not via_gavel: return False` |
| Only caller with via_gavel=True | `mesh_server.py:5960` | `update_task_state(task_id, new_status, via_gavel=True)` |

**Warning:** Manual states "Never manually edit status in JSON or DB" - this bypasses timestamps AND audit trail.

---

## 5. Critical Paths

| Path | Purpose | Manual Reference |
|------|---------|------------------|
| `control/snapshots/` | Disaster recovery backups | Section 1, Section 5 |
| `control/state/tasks.json` | Task state machine (Source of Truth) | Section 1 |
| `control/state/release_ledger.jsonl` | Immutable audit trail | Section 1, Section 5 |
| `control/state/reviews/` | Review packets | Section 3 (Drift) |
| `mesh.db` | SQLite reporting layer | Section 3 (Health) |

---

## 6. Sentinel Thresholds

| Sentinel | Check | WARN | FAIL |
|----------|-------|------|------|
| `/health` | DB exists | - | File not found |
| `/health` | Ledger age | >24h | Read error |
| `/health` | Snapshots | Folder empty | - |
| `/drift` | Review packet age | >24h | >72h |
| `/drift` | Snapshot freshness | >168h | - |

---

## 7. Prerequisites (Not in Manual - ADD)

| Command | Prerequisite | Error if Missing |
|---------|--------------|------------------|
| `/work <PREFIX>` | PREFIX argument required | - |
| `/restore <zip>` | .zip extension required | `❌ Snapshot must be a .zip filename` |
| `/ship --confirm` | Git changes exist | `Nothing to commit` |

---

## Discrepancies Found (v12.2.1)

| Issue | Manual Says | Reality | Resolution |
|-------|-------------|---------|------------|
| Fresh system health | "Must be OK" | Shows WARN (no ledger, no registry) | CLARIFY: WARN acceptable during setup |
| DB missing detection | Sentinel shows FAIL | ~~Was auto-creating DB~~ | FIXED in v12.2.1 |

---

*Truth table verified via dry runs 2025-12-09*
