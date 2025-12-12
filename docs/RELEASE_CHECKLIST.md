# Atomic Mesh Release Checklist (v13.0.1)

**Purpose:** Pre-production gate before deploying to production.
**Rule:** All P0 items must be GREEN. Any RED = NO DEPLOY.

---

## P0 - Production Blockers (MUST BE GREEN)

### 0. Static Safety Check
```bash
python tests/static_safety_check.py
```
- [ ] Exit code = 0
- [ ] No unsafe status mutations outside `update_task_state()`
- [ ] All SAFETY-ALLOW markers are audited

### 1. CI Sandbox Isolation
```bash
python tests/run_ci.py
```
- [ ] Exit code = 0
- [ ] Golden Thread uses sandboxed MESH_BASE_DIR (temp dir)
- [ ] Zero writes to real: `control/state/`, `mesh.db`, `release_ledger.jsonl`

### 2. One Gavel Enforcement
```bash
# In mesh_server.py, verify:
grep -n "via_gavel" mesh_server.py
```
- [ ] `update_task_state` blocks 'completed' unless `via_gavel=True` (line ~545)
- [ ] Only `submit_review_decision` calls with `via_gavel=True` (line ~5960)

### 3. Sentinel Truth
```
/ops
/health
/drift
```
- [ ] `/health` shows real DB path check
- [ ] `/drift` shows real review packet check
- [ ] Negative test: Rename DB file -> `/health` shows FAIL

### 4. Snapshot + Restore Fire Drill
```
/snapshot pre_release_test
/snapshots
/restore <snapshot_name.zip>
/restore_confirm <snapshot_name.zip>
```
- [ ] Snapshot creates valid .zip
- [ ] `/restore` shows preview + warning
- [ ] `/restore_confirm` re-validates before executing
- [ ] Restored state is correct

---

## P1 - Critical End-to-End

### 5. /ship Preflight Fusion
```
/ship
/ship --confirm "test"
```
- [ ] Dashboard shows 5-point preflight
- [ ] `--confirm` runs Health check (ABORTS on FAIL)
- [ ] `--confirm` runs Drift check (ABORTS on FAIL)
- [ ] `--confirm` runs CI gate (ABORTS on failure)

---

## P2 - Data Integrity

### 6. Migration Lock Behavior
```
/migrate_timestamps
/migrate_timestamps_apply
/migrate_timestamps_apply  # Second time
```
- [ ] Dry run shows preview
- [ ] Apply creates stamp file
- [ ] Second apply returns ABORT with friendly message

### 7. State/SQLite Alignment
```
/sync_db
```
- [ ] JSON statuses are UPPERCASE
- [ ] DB statuses match normalization convention

---

## P3 - Contract Tests

### 8. Registry Alignment
```python
python -c "from mesh_server import validate_registry_alignment; print(validate_registry_alignment())"
```
- [ ] Returns OK or lists specific missing IDs
- [ ] SOURCE_REGISTRY.json exists and is readable

---

## Final Release Run Order

```
1.  /ops                           # Check pulse
2.  python tests/run_ci.py         # CI gate
3.  /health                        # Full health
4.  /drift                         # Staleness check
5.  /snapshot pre_prod_final       # Safety backup
6.  /ship                          # Preflight dashboard
7.  /ship --confirm "v1.0.0"       # Execute release
8.  /snapshot v1.0_gold_master     # Seal the release
9.  git tag v1.0.0                 # Tag commit
```

---

## STOP CONDITIONS (NO DEPLOY IF ANY TRUE)

- [ ] CI writes to real prod state
- [ ] Any path can set COMPLETE without gavel
- [ ] `/health` or `/drift` crashes on real timestamps
- [ ] CLI and server disagree on snapshot location
- [ ] `/restore_confirm` doesn't re-check safety
- [ ] Ledger missing actor or decision metadata

---

*Checklist updated: 2025-12-09 (v13.0.1 Governance Lock)*
