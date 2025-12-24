# Post-Modularization Optimization Status

## 1) Executive summary (≤5)
- Backend failures currently hammer the snapshot loader every ~50 ms because refresh timers are not updated on errors, risking runaway python/DB processes (Start-ControlPanel.ps1:260-329).
- The UI renders write to `$env:TEMP\mesh_toast_debug.log` on every toast render and `/draft-plan` call, adding synchronous disk I/O to the main loop (RenderCommon.ps1:179-207; Invoke-CommandRouter.ps1:96-140).
- Snapshot timing budgets are mismatched: PowerShell waits up to 2000 ms while `snapshot.py` declares a 500 ms guard and launches a 1 s readiness subprocess each tick, so slow runs can stall the loop or flip to fail-open unpredictably (RealAdapter.ps1:181-216; tools/snapshot.py:22,280-286).
- Reality gate only executes two suites, leaving new adapters/guards/readiness/snapshot-logging tests outside the merge guard (tests/run_reality_gate.ps1:4-7).

## 2) Current strengths
- Dirty-region rendering is in place; signature/hash checks avoid unnecessary redraws when data is unchanged (Start-ControlPanel.ps1:283-309).
- Layout constants and frame ownership are centralized, keeping renderers dumb and side-effect free (Layout/LayoutConstants.ps1:1-63; Render/RenderPlan.ps1:1-121).
- Snapshot conversion cleanly separates I/O from reducers/renderers and normalizes doc readiness, lane metrics, and librarian feedback (Adapters/RealAdapter.ps1:1-179; Reducers/ComputePipelineStatus.ps1:96-265).
- Optional pipeline snapshot logging is available behind a flag for dev sessions (Helpers/LoggingHelpers.ps1:1-77).

## 3) Findings table (prioritized)
| Priority | Area | Finding | Impact | Recommendation | Effort | Risk | Suggested tests |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P0 | Performance/Stability | Adapter error path ignores the refresh interval; after a failure the loop retries every render tick (~50 ms) because `LastDataRefreshUtc`/`DataRefreshes` are not updated in the catch block (Start-ControlPanel.ps1:260-329). | Can spawn dozens of python/DB processes per second when backend is down, causing UI stalls and masking root-cause toasts. | Set `LastDataRefreshUtc` and increment `DataRefreshes` in the catch path; optionally add a short backoff or cap retries until the next scheduled interval. | S | Low | Add a failing `SnapshotLoader` stub test to assert refresh cadence respects `DataIntervalMs` after errors. |
| P1 | Performance | `Render-ToastLine` and `/draft-plan` routing append to `$env:TEMP\mesh_toast_debug.log` on every call with no guard (RenderCommon.ps1:179-207; Invoke-CommandRouter.ps1:96-140). | Continuous synchronous disk writes in the render loop risk jitter and noisy temp growth during normal use. | Guard debug logging behind an env/config flag (e.g., `MESH_DEBUG_TOAST`), or disable outside `-Dev`; keep toast rendering side-effect free. | S | Low | Add a sanity test that render/picker paths do not create or grow the log file unless the debug flag is set. |
| P1 | Responsiveness | Snapshot budget misalignment: PowerShell waits up to 2000 ms for `snapshot.py` even though the Python guard is 500 ms; readiness subprocess runs with a 1 s timeout every tick (RealAdapter.ps1:181-216; tools/snapshot.py:22,280-286). | Hung snapshot calls can freeze the UI for 2 s; readiness calls can push runs past the guard, flipping to fail-open despite healthy backends. | Align timeouts (e.g., 600-750 ms cap) and make them env-configurable; cache readiness results for a short TTL to avoid per-tick subprocess cost. | M | Medium | Add a slow-snapshot test that asserts UI returns within the budget and marks fail-open; unit test readiness caching to ensure subsequent calls reuse cached scores. |
| P1 | Test hygiene | Reality gate runs only `test_pre_ship_sanity.ps1` and `test_golden_parity.ps1`, skipping newer suites (readiness thresholds, command guards, snapshot logging, doc readiness) (tests/run_reality_gate.ps1:4-7). | Regressions in adapters/guards/readiness can merge unnoticed; gate does not exercise the Python boundary. | Expand gate to include the lightweight PS/Python suites (`test_doc_readiness.ps1`, `test_command_guards.ps1`, `test_snapshot_logging.ps1`, `test_threshold_fallback.py`) or add a weekly extended run. | S | Low | Gate script verifies all selected suites run and fail the build on non-zero exit; add a CI log summary for quick triage. |

## 4) Do now (max 5)
- Add error-path refresh throttling/backoff in `Invoke-DataRefreshTick` to stop hammering the backend on failure.
- Gate or remove temp-file logging from the render loop and `/draft-plan` router.
- Tighten and make configurable snapshot/readiness timeouts; memoize readiness results per tick/second.
- Broaden `tests/run_reality_gate.ps1` to include key readiness/guard/logging suites.

## 5) Defer list
- History overlay parity and expanded command surface remain out of scope for this pass; handle after stability/perf fixes to avoid new UI churn.
- Default-on pipeline snapshot logging policy changes should wait until timeout/backoff work stabilizes to avoid masking perf regressions.

## 6) Notes
- Recommend updating merge gate docs to call `tests/run_reality_gate.ps1` after it is broadened, so post-modularization suites remain the default guard. 
