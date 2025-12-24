# Migration Audit (Golden Parity)

Summary block
- Verified parity areas: header layout with mode + health dot + lane counts mirrors golden (`reference/golden/control_panel_6990922.ps1:1114-1183` vs `src/AtomicMesh.UI/Private/Render/RenderCommon.ps1:6-109`; covered by `tests/test_pre_ship_sanity.ps1:333-380`). Ctrl+C double-press guard present (`reference/golden/control_panel_6990922.ps1:9006-9037` vs `src/AtomicMesh.UI/Public/Start-ControlPanel.ps1:1-41,362-371`; tested at `tests/test_pre_ship_sanity.ps1:618-676`).
- Suspected gaps: snapshot fail-open semantics depend on real `tools/snapshot.py` responses; module uses timeouts but tests only exercise stub data (`src/AtomicMesh.UI/Private/Adapters/SnapshotAdapter.ps1:4-51`, `tests/test_golden_parity.ps1:158-242`). Needs live check to confirm parity with golden fail-open messaging.
- Confirmed missing items (with evidence):
  1) Slash command surface truncated to 11 commands (no task mgmt, ops, agents, context, router debug, refresh-plan, etc.). Golden registry `reference/golden/control_panel_6990922.ps1:44-142`; module registry/router `src/AtomicMesh.UI/Private/Render/CommandPicker.ps1:13-23` and `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1:10-157`.
  2) History mode behaviors (Tab cycles subviews, Enter toggles details, F3 toggle, D/I/S/V hotkeys, history data + hints) absent. Golden input loop `reference/golden/control_panel_6990922.ps1:9026-9795` and renderer `reference/golden/control_panel_6990922.ps1:7053-7435`; module only placeholder overlay `src/AtomicMesh.UI/Private/Render/Overlays/RenderHistory.ps1:1-68` with limited keys `src/AtomicMesh.UI/Public/Invoke-KeyRouter.ps1:1-45`.
  3) Pipeline panel + snapshot logging missing: golden renders reasons/hotkeys and writes non-green snapshots (`reference/golden/control_panel_6990922.ps1:5219-5572,6904-7193,8045`); module renders compact text only and has no snapshot writer (`src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1:1-175`, no `Write-PipelineSnapshotIfNeeded` in repo).

## Executive summary
- Current module implements header, boxed input, dropdown basics, and plan/go/bootstrap frame-fill matching golden fixtures, but major interaction and routing surfaces remain unmigrated.
- Highest gaps: missing 45+ slash commands (task lifecycle, ops/health, librarian/audit, refresh-plan), absent history workflow (navigation, hotkeys, ingest/verify actions), and no pipeline snapshot logging or reason/hotkey display.
- Test coverage focuses on static rendering and a few commands (/init,/draft-plan,/accept-plan,/go,/plan,/ship) leaving missing behaviors untested (`tests/test_golden_parity.ps1:158-350`, `tests/test_pre_ship_sanity.ps1:189-578`).

## Inventory – Commands
Golden registry: `reference/golden/control_panel_6990922.ps1:44-142` (56 commands). Module registry/router: `src/AtomicMesh.UI/Private/Render/CommandPicker.ps1:13-23`, `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1:10-157` (11 commands).

| Category | Golden commands (ref) | Module coverage | Status |
| --- | --- | --- | --- |
| Execution | go (`44`) | go routed (`Invoke-CommandRouter.ps1:84-115`) | Partial (present) |
| Task mgmt | add, skip, reset, drop, nuke (`47-51`) | none in registry/router | Missing |
| Agents | audit, lib (scan/status/mount/unmount/refs), ingest, snippets, dupcheck (`54-2189`) | none | Missing |
| Rigor/lock | rigor, unlock, lock (`61-65`) | none | Missing |
| Q&A/review | questions, answer, review, rules, kickback (`68-76,2446-2541`) | none | Missing |
| Streams/projects | stream, multi, projects (`80-84,2608-2691`) | none | Missing |
| Library/profile | init, profile, standard, standards (`87-90,2959-3047`) | init present; profile/standard(s) absent | Partial |
| Pre-flight/QA | ship, preflight, verify, simplify (`93-96,3208-3276`) | ship + simplify present; preflight/verify absent | Partial |
| Context notes | decide, note, blocker (`99-101,2615-2637`) | none | Missing |
| Mode/config | mode, milestone (`104-105,2649-2667`) | none | Missing |
| Session/navigation | status, plan, tasks, help, commands, refresh, clear, quit (`108-115,3568-3587`) | status/help/plan/go/clear/quit present; tasks/commands/refresh absent | Partial |
| Diagnostics | doctor, refine (`118-121,3388-3502`) | none | Missing |
| View toggles | dash, compact (`124-125,3575-3580`) | none | Missing |
| Ops suite | ops, health, drift, work (`128-131,3587-3711`) | none | Missing |
| Debug/TDD | router-debug, scaffold-tests (`134-137`) | none | Missing |
| Plan-as-code | refresh-plan, draft-plan, accept-plan (`140-142,3736-3874`) | draft-plan/accept-plan present; refresh-plan missing | Partial |

## Inventory – Keys
Golden handler: `reference/golden/control_panel_6990922.ps1:9006-9846`. Module handler: `src/AtomicMesh.UI/Public/Invoke-KeyRouter.ps1:1-45` + input loop `src/AtomicMesh.UI/Public/Start-ControlPanel.ps1:362-486`.

| Key/Behavior | Golden evidence | Module behavior | Status |
| --- | --- | --- | --- |
| Enter | Submit; in History toggles details (`9026-9045`) | Only submits; toggles details only when overlay already open (`Invoke-KeyRouter.ps1:17-24`) | Partial |
| Escape | Resets buffer + placeholder + lookup; exits History if empty (`9114-9127`) | Clears buffer or closes overlay; no placeholder/lookup handling (`Invoke-KeyRouter.ps1:25-45`) | Missing nuance |
| Tab | Placeholder advance; History subview cycle; mode toggle when idle (`9131-9175`) | History subview cycle when overlay; else mode cycle when buffer empty (`Invoke-KeyRouter.ps1:5-16`) | Partial (no placeholder flow) |
| F2/F3 | History toggle (F2/F3) + placeholder option toggle (`9214-9227`) | F2 toggles overlay; no F3 or placeholder toggle (`Invoke-KeyRouter.ps1:17-23`) | Missing F3/placeholder |
| Up/Down | Lookup navigation and History row nav (`9233-9268`) | Only picker navigation when dropdown active (`Start-ControlPanel.ps1:379-404`) | Missing History/lookup |
| Backspace/Delete | Resets lookup/placeholder + ESC-equivalent when buffer empty (`9283-9357`) | Simple delete only (`Start-ControlPanel.ps1:464-478`) | Missing |
| Slash first char | Opens command picker with template insertion (`9428-9485`) | Opens picker whenever buffer starts with "/" (no first-char gate, no template placeholders) (`Start-ControlPanel.ps1:486-504`) | Different |
| RightArrow in picker | Inserts template, keeps picker open (`9731-9767`) | Autocomplete command text only (`Start-ControlPanel.ps1:404-415`) | Partial |
| History hotkeys D/I/S/V | Ingest, simplify, verify, next hint (`6747-7015`, `9428-9450`) | No binding | Missing |

## Inventory – Screens & overlays
| Screen/Overlay | Golden reference | Module reference | Status |
| --- | --- | --- | --- |
| Plan screen | `reference/golden/control_panel_6990922.ps1:7520-7578` | `src/AtomicMesh.UI/Private/Render/RenderPlan.ps1:42-121` | Present (simplified) |
| Exec/Go screen | `reference/golden/control_panel_6990922.ps1:7580-7824` | `src/AtomicMesh.UI/Private/Render/RenderGo.ps1:19-111` | Present (simplified) |
| Bootstrap screen | `reference/golden/control_panel_6990922.ps1:7439-7518` | `src/AtomicMesh.UI/Private/Render/RenderBootstrap.ps1:1-79` | Present (minimal messaging only) |
| History overlay | `reference/golden/control_panel_6990922.ps1:7053-7420` (data rows, details pane, hints) | `src/AtomicMesh.UI/Private/Render/Overlays/RenderHistory.ps1:1-68` (static placeholder rows) | Missing data/logic |
| Command picker dropdown | `reference/golden/control_panel_6990922.ps1:9639-9795` (multi-column, template insertion) | `src/AtomicMesh.UI/Private/Render/CommandPicker.ps1:30-190` (single column, no templates) | Partial |
| Pipeline panel | `reference/golden/control_panel_6990922.ps1:5336-5572` (reasons, hotkeys, suggested next) | Right-column directives only (`src/AtomicMesh.UI/Private/Reducers/ComputePipelineStatus.ps1:1-175`) | Missing depth |

## Inventory – Snapshot fields & nuances
| Item | Golden evidence | Module status |
| --- | --- | --- |
| ReadinessMode/HealthStatus fail-open defaults | `reference/golden/control_panel_6990922.ps1:1186-1207,5160-5190` | Fields exist in model (`src/AtomicMesh.UI/Private/Models/UiSnapshot.ps1:9-38`) but SnapshotAdapter returns stub data; no explicit fail-open messaging in UI |
| DistinctLaneCounts for header | `reference/golden/control_panel_6990922.ps1:891-919,1114-1183` | Implemented (`RenderCommon.ps1:41-56`) |
| Pipeline snapshot logging (logs/pipeline_snapshots.jsonl) | `reference/golden/control_panel_6990922.ps1:5219-5319`, invoked `6904-7193,8045` | Not implemented anywhere in module (no writer function) |
| Next hint priority chain incl. Optimize | `reference/golden/control_panel_6990922.ps1:4938-5040,4731-4734` | Simplified: stage-based hint only (`ComputePipelineStatus.ps1:140-166`) |
| Recommended actions/hotkeys display | `reference/golden/control_panel_6990922.ps1:5480-5555` | Not rendered (no actions in directives) |
| Readiness gate for strategic commands | `reference/golden/control_panel_6990922.ps1:1778-1817` | Absent from router (`Invoke-CommandRouter.ps1:10-157`) |

## Gaps with evidence
- **Missing command surface (task/ops/agents/refresh-plan)**: Golden registry includes 56 commands (`reference/golden/control_panel_6990922.ps1:44-142`), but module picker/router expose only 11 (`src/AtomicMesh.UI/Private/Render/CommandPicker.ps1:13-23`, `src/AtomicMesh.UI/Public/Invoke-CommandRouter.ps1:10-157`). No coverage in tests (`tests/test_pre_ship_sanity.ps1:189-578` exercises only /init,/draft-plan,/accept-plan,/go,/plan,/ship).
- **Readiness gating for plan/draft/accept**: Golden blocks strategic commands when readiness.py reports BOOTSTRAP (`reference/golden/control_panel_6990922.ps1:1778-1817`). Module routes /draft-plan and /accept-plan without readiness check, only simple guards (`Invoke-CommandRouter.ps1:66-149`); risk of running in PRE_INIT with missing docs.
- **History workflow absent**: Golden History screen with subviews, selection, details, ingest/verify/simplify hotkeys, and pipeline-integrated hints (`reference/golden/control_panel_6990922.ps1:7053-7420,6747-7015,9026-9450`). Module overlay is static placeholder (`src/AtomicMesh.UI/Private/Render/Overlays/RenderHistory.ps1:1-68`) and keys ignore History navigation/hotkeys (`Invoke-KeyRouter.ps1:1-45`).
- **Key handling gaps (lookup/placeholder, F3, Backspace/Delete logic)**: Golden input loop handles placeholders, lookup panels, ESC hard reset, Backspace/Delete ESC-equivalence, F3 toggle, and slash-only picker trigger (`reference/golden/control_panel_6990922.ps1:9006-9485`). Module input loop lacks placeholder/lookup logic and opens picker on any slash prefix, missing F3 and Backspace/Delete nuances (`Start-ControlPanel.ps1:362-486`, `Invoke-KeyRouter.ps1:1-45`).
- **Pipeline panel + reasons/hotkeys missing**: Golden right panel shows stage colors, source, suggested next, reason line, and hotkeys, and writes snapshot logs for non-GREEN states (`reference/golden/control_panel_6990922.ps1:5219-5572,6904-7193`). Module reduces to compact stage text and hint (`ComputePipelineStatus.ps1:1-175`, `Render-Plan.ps1:42-118`) and never logs snapshots (no equivalent function).
- **Plan-as-code parity**: Golden /refresh-plan command and history hotkey auto-refresh plan (`reference/golden/control_panel_6990922.ps1:3736-3807,6945-6985`), but module lacks /refresh-plan route and picker entry (`CommandPicker.ps1:13-23`, `Invoke-CommandRouter.ps1:10-157`).
- **Ops/health/doctor drift views missing**: Golden ops/health/drift/doctor screens and commands (`reference/golden/control_panel_6990922.ps1:1681-1724,3587-3711,3388-3502`) have no module counterparts (no renders or routes).

## Backlog (priority, estimate, owner suggestion)
| Item | Priority | Estimate | Owner suggestion |
| --- | --- | --- | --- |
| Reconstitute full slash command registry and routing (task mgmt, ops, agents, plan-as-code) with readiness gate parity | P0 | 3-4d | UI platform |
| Implement History mode parity (data fetch + subviews + D/I/S/V hotkeys + Enter/Tab behaviors) | P0 | 4-5d | UI platform + backend signals |
| Restore pipeline panel depth (reason line, hotkeys, suggested next) and add snapshot logging (`logs/pipeline_snapshots.jsonl`) | P1 | 2-3d | UI platform |
| Add placeholder/lookup-aware input handling (ESC hard reset, Backspace/Delete parity, slash-first picker constraint, F3 toggle) | P1 | 2d | UI platform |
| Surface ops/health/drift/doctor renders and commands | P2 | 3d | UI platform |
| Expand tests to cover command surface, history actions, and pipeline snapshot writing | P1 | 2d | QA/Automation |

## Appendix: search notes
- Golden grep: `rg --line-number "Invoke-SlashCommand|Get-PickerCommands|Draw-|History" reference/golden/control_panel_6990922.ps1`, manual review around 44-142, 1052-1113, 1778-1817, 5219-5572, 6747-7435, 9006-9795.
- Module grep: `rg --line-number "CommandPicker|Invoke-CommandRouter|Invoke-KeyRouter|History|Pipeline" src/AtomicMesh.UI`, inspected `CommandPicker.ps1`, `Invoke-CommandRouter.ps1`, `Invoke-KeyRouter.ps1`, `Start-ControlPanel.ps1`, `RenderHistory.ps1`, `ComputePipelineStatus.ps1`.
- Tests reviewed: `tests/test_golden_parity.ps1`, `tests/test_pre_ship_sanity.ps1`.
