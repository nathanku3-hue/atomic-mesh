# Reality Alignment Report – Atomic Mesh UI Sandbox

## 1) Executive Summary
- Current experience: launches `control_panel.ps1` → renders header + two-column PLAN/GO/BOOTSTRAP layouts with a 6-stage pipeline strip and doc readiness bars sourced from `tools/snapshot.py` (see `Start-ControlPanel` loop `src/AtomicMesh.UI/Public/Start-ControlPanel.ps1:328`, pipeline reducer `src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1:254`).
- Users can: initialize docs from module templates (`Invoke-ProjectInit` `src/AtomicMesh.UI/Private/Helpers/InitHelpers.ps1:95`), flip between PLAN/GO/BOOTSTRAP via `/plan` and `/go` (router `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1:82`), see doc readiness microbars and blocking files in pre-draft state (docs panel `ComputePipelineStatus.ps1:166`), and toggle a placeholder History overlay with F2 (render `src/AtomicMesh.UI/Private/Render/Overlays/RenderHistory.ps1:1`).
- Operating model: PowerShell shell loop drives rendering; all data (lanes, docs, git, readiness) is pulled from the Python snapshot boundary (`tools/snapshot.py:418`) with a 500 ms timing guard and doc scoring delegated to `tools/readiness.py`. No PowerShell I/O occurs in renderers; adapters isolate file/DB access (`Convert-RawSnapshotToUi` `src/AtomicMesh.UI/Private/Adapters/RealAdapter.ps1:1`).
- Scope boundaries: command surface intentionally trimmed to 11 verbs (init/help/plan/go/draft-plan/accept-plan/status/simplify/ship/clear/quit) in picker and router (`src/AtomicMesh.UI/Private/Render/CommandPicker.ps1:13`, `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1:10`); no /commands registry or task/ops/agent commands from golden registry.
- Logging: optional pipeline snapshot logging to `control/state/pipeline_snapshots.jsonl` when `-Dev` or `MESH_LOG_SNAPSHOTS` is set (`Write-PipelineSnapshotIfEnabled` `src/AtomicMesh.UI/Private/Helpers/LoggingHelpers.ps1:25`); otherwise in-memory event/toast only.

## 2) Current State Inventory (facts)
- **Entry points:** `control_panel.ps1` loads the module and forwards LaunchPath to the module (`control_panel.ps1:1`); launcher helper exists (`launcher/mesh-test.ps1:1`) but main entry is `control_panel.ps1`.
- **Data flow & roots:** Start loop caches `ProjectPath`, `ModuleRoot`, `RepoRoot` separately (`Start-ControlPanel.ps1:348`) and refreshes snapshots via Python (`Invoke-DataRefreshTick` `Start-ControlPanel.ps1:255`). Doc readiness, git clean, health, and task hints all come from `tools/snapshot.py` (initial payload `tools/snapshot.py:418`, readiness block `tools/snapshot.py:564`). Init detection uses marker/2-of-3 docs every tick (`Update-AutoPageFromPlanStatus` `Start-ControlPanel.ps1:212`) and Python `check_initialized` (`tools/snapshot.py:495`).
- **UI screens/modes:** Header matches golden layout (mode + health dot + lane counts + path) (`Render-Header` `src/AtomicMesh.UI/Private/Render/RenderCommon.ps1:6`). Main pages: PLAN (`Render-Plan` `src/AtomicMesh.UI/Private/Render/RenderPlan.ps1:42`), GO (`Render-Go` `src/AtomicMesh.UI/Private/Render/RenderGo.ps1:19`), BOOTSTRAP (`Render-Bootstrap` `src/AtomicMesh.UI/Private/Render/RenderBootstrap.ps1:1`). History overlay is stub (static rows, no data) (`Render-HistoryOverlay` `src/AtomicMesh.UI/Private/Render/Overlays/RenderHistory.ps1:1`). Input/footer: boxed input + hint bar (`Render-InputBox` `RenderCommon.ps1:234`, `Render-HintBar` `RenderCommon.ps1:304`), command dropdown (`Render-CommandDropdown` `CommandPicker.ps1:163`).
- **Logging & caches:** Optional pipeline log at `control/state/pipeline_snapshots.jsonl` when enabled (`LoggingHelpers.ps1:25`); librarian feedback cache read from `docs/librarian_doc_feedback.json` if present (`tools/snapshot.py:501`). No other file writes during render.
- **Commands (implemented):** `/init`, `/help [--all]`, `/plan`, `/go`, `/draft-plan`, `/accept-plan`, `/status`, `/simplify [task]`, `/ship`, `/clear`, `/quit` (`CommandPicker.ps1:13`, `Invoke-CommandRouter.ps1:48`). No task mgmt (/add,/skip,/reset,/drop,/nuke), ops (/ops,/health,/drift,/doctor), agents (/audit,/lib,/ingest,/snippets,/dupcheck), history actions, or /refresh-plan.

## 3) Golden Parity Map
| Subsystem | Golden anchor | Module implementation | Status |
| --- | --- | --- | --- |
| Header/frame | `reference/golden/control_panel_6990922.ps1:1114` (`Show-Header`) | `src/AtomicMesh.UI/Private/Render/RenderCommon.ps1:6` (`Render-Header`) | MATCH (layout and counts tested in `tests/test_pre_ship_sanity.ps1:158`) |
| Input/picker/autocomplete | `reference/golden/control_panel_6990922.ps1:8962` (`Read-StableInput`), picker `:9639` | Input loop `Start-ControlPanel.ps1:422`, dropdown `CommandPicker.ps1:30` | PARTIAL (no placeholder/lookup logic, single-column picker, limited registry) |
| Pipeline panel (stages/reason/source) | `reference/golden/control_panel_6990922.ps1:5336` (`Draw-PipelinePanel`) | Right-column reducer `ComputePipelineStatus.ps1:254`, render `Render-Plan.ps1:169`/`Render-Go.ps1:69` | PARTIAL (reason line prefixed with stage, no hotkeys/source in live mode; fixture mismatches in `tests/test_golden_parity.ps1:189`) |
| History overlay | `reference/golden/control_panel_6990922.ps1:7053` (`Draw-HistoryScreen`) | Placeholder overlay `RenderHistory.ps1:1` | MISSING (static rows, no selection/navigation/data) |
| Init workflow | Init detection/gating `reference/golden/control_panel_6990922.ps1:1778` and `Test-RepoInitialized` refs | `Test-RepoInitialized` `InitHelpers.ps1:16`, auto-page `Start-ControlPanel.ps1:212`, router guards `Invoke-CommandRouter.ps1:48` | PARTIAL (init detection implemented; guards return generic “Run /init” even when plan state is ready) |
| Doc readiness scoring | Progress bars `reference/golden/control_panel_6990922.ps1:5621`, pre-draft panel `:7520` | Doc bars + hints `ComputePipelineStatus.ps1:47` and `ComputePipelineStatus.ps1:166`, render `Render-Plan.ps1:169` | PARTIAL (bars present; missing “create file” hints and stage-neutral reason text in fixtures `tests/test_golden_parity.ps1:158`) |

## 4) Test Reality
- Ran `tests/test_pre_ship_sanity.ps1` → 5 failures (e.g., `/go` left page on PLAN, `/accept-plan` toast missing task count, guards blocking with “Run /init” messages, RightArrow flow not executing) (`tests/test_pre_ship_sanity.ps1:158`, `:1879`, `:2087`, `:2116`, `:2346`).
- Ran `tests/test_golden_parity.ps1` → 5 fixture mismatches (doc panel missing “create file” hints, reason line prefixed with stage code) (`tests/test_golden_parity.ps1:161`, `:192`, `:211`, `:262`, `:281`).
- Additional suites present (not run here): command discovery (`tests/test_command_discovery.ps1`), command guards (`tests/test_command_guards.ps1`), snapshot logging (`tests/test_snapshot_logging.ps1`), doc readiness (`tests/test_doc_readiness.ps1`), history overlays (`tests/test_f2_event_log_overlay.py`), etc.

## 5) Gap List (top 10)
1. `/go` does not switch to GO view in sanity fixture (stays PLAN) — user cannot reach exec dashboard; evidence `tests/test_pre_ship_sanity.ps1:158` result FAIL with state `page=PLAN`; router currently sets page but guards may block with generic init message (`Invoke-CommandRouter.ps1:145`). Fix: ensure `/go` success path advances page when plan accepted, and guards return specific hints; add fixture asserting `State.CurrentPage -eq "GO"`.
2. `/accept-plan` guard messages override plan-state feedback (returns “Run /init first” instead of task count or already-accepted message) — impacts plan lifecycle clarity; evidence `tests/test_pre_ship_sanity.ps1:1879`, `:2116`; command guard (`Invoke-CommandRouter.ps1:117`) prioritises init detection. Fix: gate on init once but surface plan/draft status; add tests for accepted/draft-none paths.
3. Command surface trimmed to 11 verbs — task mgmt, ops, agents, doc tools absent; evidence limited registry `CommandPicker.ps1:13` vs golden registry `reference/golden/control_panel_6990922.ps1:42`; users cannot perform queue mgmt/ops tasks. Fix: scoped parity restoration for P0/P1 commands or document intentional scope; expand picker/router plus guards and fixtures.
4. History overlay stub — no data rows, navigation, or hotkeys (D/I/S/V) compared to golden; evidence `RenderHistory.ps1:1` vs golden `reference/golden/control_panel_6990922.ps1:7053`; tests currently pass placeholder only. Fix: implement data fetch from snapshot History* fields and key routing; add fixtures covering TASKS/DOCS/SHIP tabs and details toggle.
5. Pipeline reason text deviates (stage prefixes like “PLN: Based on plan status”) and omits doc “create file” hints — golden parity fixtures fail (`tests/test_golden_parity.ps1:161`); reducer adds stage code in `ComputePipelineStatus.ps1:318`. Fix: align reason text with golden (no stage prefix for generic reasons, doc hints for missing files); update reducer and rerun fixtures.
6. `/go` readiness guard messaging lacks `/accept-plan` guidance — test expects hint to accept plan first (`tests/test_pre_ship_sanity.ps1:2087`); current guard surfaces init warning. Fix: adjust guard chain to check plan acceptance before init warning; add test coverage.
7. `/accept-plan` success toast omits task count when tasks exist — expected “5 task(s)” (P6) (`tests/test_pre_ship_sanity.ps1:1879`); router sets count only when lane metrics present but guard short-circuits. Fix: ensure snapshot lanes provided in tests, or mock fallback count; assert toast contains count.
8. RightArrow flow: after autocomplete, Enter does not execute selected command — stays on PLAN (`tests/test_pre_ship_sanity.ps1:2346`); input loop resets picker but may clear input; see `Start-ControlPanel.ps1:404`. Fix: ensure picker state/command buffer preserved on Enter after RightArrow; add integration test.
9. Doc readiness thresholds/hints mismatch with golden (missing “create file” callouts when docs absent) — evidence fixture deltas for `plan_empty` (`tests/test_golden_parity.ps1:161`); reducer `Get-DocsRightColumn` currently omits hint strings. Fix: add hint text when `exists` is false; update fixtures.
10. Pipeline snapshot logging is opt-in only — golden logged every non-green transition (`reference/golden/control_panel_6990922.ps1:5219`); module only logs when `-Dev` or env var set (`LoggingHelpers.ps1:25`). Impact: production sessions lack historical pipeline log unless opt-in. Fix: decide policy (enable by default or explicit config) and add a smoke test (`tests/test_snapshot_logging.ps1`) to enforce.

## 6) Recommended Next Steps (scoped; respect no heavy render I/O)
1. Fix `/go` routing guard chain so accepted plans switch to GO; acceptance: pre-ship check 4 passes and `State.CurrentPage` becomes GO in golden fixtures; test: `tests/test_pre_ship_sanity.ps1` (checks 4, 63).
2. Refine `/accept-plan` guard messaging and task-count toast; acceptance: checks 57/64 in `tests/test_pre_ship_sanity.ps1` pass with accurate counts; add unit around `Invoke-CommandRouter.ps1` for accepted/draft-none paths.
3. Align pipeline reason text and doc hints with golden fixtures; acceptance: `tests/test_golden_parity.ps1` passes for plan_empty/with_draft/exec_*; update reducer only (no render-loop I/O).
4. Preserve RightArrow → Enter execution flow; acceptance: check 72 in `tests/test_pre_ship_sanity.ps1` passes; add regression test covering picker state after autocomplete.
5. Implement History overlay data binding (TASKS/DOCS/SHIP) using snapshot History* arrays; acceptance: new fixtures for populated history plus existing overlay sanity; keep rendering pure (no disk access).
6. Document current command scope and add curated `/commands` view to list supported verbs without expanding surface; acceptance: picker shows `/commands` output consistent with router; test: new small fixture.
7. Add readiness-aware guard ordering (/init vs /accept-plan) with specific toasts; acceptance: guards return action-specific guidance in pre-ship checks 63/64; unit tests for guard helpers.
8. Decide pipeline snapshot logging default (enable non-green transitions by default with env opt-out); acceptance: `tests/test_snapshot_logging.ps1` augmented to assert file writes on non-green; no render-loop I/O.
9. Enrich doc readiness panel with “create file” hints when docs missing; acceptance: `plan_empty` fixture matches golden; adjust `Get-DocsRightColumn`.
10. Add task mgmt/ops/agent parity plan (scoped P0 set) or mark out-of-scope explicitly in OPERATIONS; acceptance: explicit design note in docs plus skipped tests or added commands; avoid broad expansion until requested.
11. Ensure `/simplify` and Optimize hints respect snapshot fields; acceptance: pre-ship Optimize checks stay green; add unit around `Get-NextHintFromStages`.
12. Add failure-mode coverage for fail-open snapshot path (ReadinessMode=fail-open) to ensure header badge + source line match golden; acceptance: sanity test for source display when timing guard triggers.
13. Update HISTORY hotkeys (D/I/S/V) once overlay data exists; acceptance: map keys in `Invoke-KeyRouter.ps1` and extend pre-ship history checks; tests: new overlay integration fixture.

## Manual Smoke
- Status: FAIL (not run in this headless session; interactive TUI input not available).
- Checklist (to run locally from a non-repo folder):
  - Launch UI → `/init` → `/draft-plan` → `/accept-plan` → `/go` round-trip.
  - Type `/`, use dropdown RightArrow autocomplete, Enter executes.
  - Resize once to confirm layout stability.
- Manual smoke is required before merging to main (unless explicitly waived with reason).
- Record here with date/machine/shell and PASS/FAIL per step (include toast/error text if any step fails).

## RA Scope Boundaries
- **Out of scope (intentional):** full golden `/commands` surface (command set is limited to the implemented 11 verbs).
- **In progress:** 2-tier readiness schema work; history overlay/pipeline richness; doc readiness hint/template improvements.
- **Reality gate coverage:** `tests/test_pre_ship_sanity.ps1` + `tests/test_golden_parity.ps1` via `tests/run_reality_gate.ps1` (must be green before merges). Run and keep green in both pwsh and Windows PowerShell 5.1 (use `tests/run_reality_gate_ps51.ps1` for the latter).
