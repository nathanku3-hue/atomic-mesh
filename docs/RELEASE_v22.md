# Release v22.0 - Golden Parity + P7 Optimize Stage

**Date:** 2025-12-19
**Commit:** `508d859`
**Test Results:** 62/62 PASS

---

## Summary

Major release achieving 100% golden parity with reference implementation. Adds the Optimize stage to the 6-stage pipeline and completes all Core Nuances (1-6).

---

## Pipeline Changes

### 6-Stage Pipeline
```
[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]
```

| Stage | GREEN | YELLOW | RED | GRAY |
|-------|-------|--------|-----|------|
| Context | EXECUTION | BOOTSTRAP | PRE_INIT | unknown |
| Plan | ACCEPTED | DRAFT | ERROR/BLOCKED | Context blocked |
| Work | active > 0 | queued > 0 | blocked > 0 | Plan blocked |
| Optimize | has entropy proof | tasks but no proof | - | Work blocked |
| Verify | no HIGH risk | - | HIGH risk unverified | no tasks |
| Ship | git clean | uncommitted | Verify=RED | Verify=GRAY |

### Entropy Proof Markers (P7)

The Optimize stage checks task notes for these patterns:

| Marker | Purpose |
|--------|---------|
| `Entropy Check: Passed` | Standard optimization verification |
| `OPTIMIZATION WAIVED` | Explicitly skipped (approved) |
| `CAPTAIN_OVERRIDE: ENTROPY` | Manual override by authorized user |

**Important:** Partial matches do NOT count. `Entropy Check: Failed` is NOT a valid marker.

When Optimize is YELLOW, the hint suggests `/simplify <task-id>`.

---

## Core Nuances Complete (1-6)

| Nuance | Description | Implementation |
|--------|-------------|----------------|
| 1 | Header Path | Shows `ProjectPath` (launch cwd), not `RepoRoot` |
| 2 | Source Display | `snapshot.py (live)` or `(fail-open)` mode |
| 3 | Stage Colors | 6 stages with orthogonal dependency chain |
| 4 | Next Hints | 13-step priority chain with task IDs |
| 5 | Lane Counts | Distinct lanes from snapshot, not total tasks |
| 6 | Health Dot | Color from system status (OK/WARN/FAIL) |

---

## Test Coverage

### Pre-Ship Sanity Checks (62 total)

| Range | Category |
|-------|----------|
| 1-17 | Frame layout, input handling, navigation |
| 18-29 | Header path alignment at w60/w80/w120 |
| 30-33 | Command dropdown behavior |
| 34-35 | Pipeline panel rendering |
| 36-37 | History overlay details toggle |
| 38-39 | Help system (/help, /help --all) |
| 40-41 | ProjectPath provenance (not RepoRoot) |
| 42-50 | Core Nuances 2-6 |
| 51-57 | Command feedback (P1-P6) |
| 58-60 | Optimize stage (P7) |
| 61 | Slow snapshot regression (fail-open) |
| 62 | False positive guard (entropy markers) |

### Golden Fixtures (10 total)

- `plan_empty.txt`, `plan_with_draft.txt`, `plan_accepted.txt`, `plan_adapter_error.txt`
- `exec_running.txt`, `exec_empty.txt`
- `bootstrap.txt`
- `history_tasks.txt`, `history_docs.txt`, `history_ship.txt`

---

## Git Availability Behavior

The Ship stage uses `git status --porcelain` to detect uncommitted changes.

| Scenario | Behavior |
|----------|----------|
| Git available, clean | Ship = GREEN |
| Git available, dirty | Ship = YELLOW |
| Git unavailable/error | Ship = GREEN (fail-open default) |

This ensures the UI never crashes due to git issues.

---

## Files Changed

| Category | Files |
|----------|-------|
| New Models | 10 (LaneMetrics, PlanState, UiSnapshot, etc.) |
| New Reducers | 4 (ComputePipelineStatus, ComputeLaneMetrics, etc.) |
| New Renderers | 6 (RenderPlan, RenderGo, RenderBootstrap, etc.) |
| New Adapters | 4 (DbAdapter, RealAdapter, SnapshotAdapter, etc.) |
| New Tests | 12 (test_pre_ship_sanity, test_golden_parity, etc.) |
| Documentation | 3 (GOLDEN_PARITY_PLAN, OPTIMIZE_MARKERS, RELEASE_v22) |

**Total:** 81 files changed, 31,754 insertions, 10,483 deletions

---

## Manual Smoke Checklist

For final verification before shipping:

1. **Launch-path correctness** - Header shows launch directory, not module location
2. **Performance** - 60s run, no hitches, Source shows `(live)` not `(fail-open)`
3. **Git dirty detection** - `echo x >> foo.txt` flips Ship to YELLOW
4. **Dropdown + commands** - `/` opens, Tab completes with space, ESC closes
5. **Optimize markers** - Add task note with marker, Optimize turns GREEN
6. **Fail-open behavior** - Rename DB, UI stays alive with `(fail-open)`
7. **Resize stress test** - Rapid resize, no crash or smear

---

## Breaking Changes

None. This release is backwards compatible.

---

## Next Steps (Out of Scope for v22)

Nuances 7-24 remain for future work:
- Command feedback patterns (icons, retry logic)
- `/ship` HIGH risk blocking
- Toast message formatting
- Advanced error handling
