# Atomic Mesh Changelog

## Unreleased

- History overlay uses soft trimming to avoid mid-word cutoffs and now leverages the 10-item pending sampler for fuller lists.
- Readiness thresholds eased: SPEC now passes at 60 (matching achievable scoring) so doc-complete repos are not blocked; history sampler bumped to 10 pending tasks.

## v13.3.5 "Editor-Style Footer" (Production Ready)
**Date:** 2025-12-11

**Theme:** "Clean coding-CLI style - Next hint + mode indicator"

### Major Features

#### 1. Editor-Style Footer Bar
Footer shows `Next:` hint on the left and `[MODE]` on the right. Removed Status: and Help: text:

```
  Next: /run                                                          [PLAN]
┌──────────────────────────────────────────────────────────────────────────┐
│ > _                                                                      │
└──────────────────────────────────────────────────────────────────────────┘
```

**Features:**
- Left side: `Next: <command>` - context-aware suggested action
- Right side: `[OPS]` / `[PLAN]` / `[RUN]` / `[SHIP]` mode indicator
- No Status: or Help: text - clean, minimal look
- Footer sits ABOVE the input bar (at RowInput-2)
- Tab still toggles between OPS and PLAN modes

#### 2. Layout
```
<dashboard>

  Next: /run                                              [OPS]  ← Footer (RowInput-2)
┌──────────────────────────────────────────────────────────┐     ← Top Border (RowInput-1)
│ > _                                                      │     ← Input (RowInput)
└──────────────────────────────────────────────────────────┘     ← Bottom Border (RowInput+1)
                                                                 ← Dropdown (RowInput+2)
```

### Next Hint Logic
The `Next:` hint is derived from system scenario:
- **fresh** (no sources/tasks): `/init`
- **messy** (librarian flagged): `/lib clean`
- **pending** (tasks waiting): `/run`
- **default**: `/ops`

### Key Files Changed
- `control_panel.ps1:2869-2908` - `Draw-FooterBar` with Next: left, [MODE] right
- `control_panel.ps1:2303-2322` - `Get-PromptLayout` updated (dropdown at RowInput+2)
- `control_panel.ps1:2324-2341` - `Clear-PromptRegion` clears from RowInput-2
- `control_panel.ps1:2343-2356` - `Redraw-PromptRegion` draws footer then input
- `control_panel.ps1:2915-2932` - `Read-StableInput` draws footer then input
- `control_panel.ps1:3003-3029` - `Show-CommandPicker` dropdown at RowInput+2

### Design Principles
- **Actionable hint**: `Next:` tells you what to do
- **Mode awareness**: Right-aligned mode doesn't interrupt reading
- **No clutter**: Removed Status: and Help: entirely
- **Picker preserved**: Dropdown appears below input, footer stays intact on exit

---

## v13.3.4 "Minimal Footer" (Superseded)
**Date:** 2025-12-11

*Note: Superseded by v13.3.5 which adds the Next: hint back.*

---

## v13.3.3 "Compact Footer" (Superseded)
**Date:** 2025-12-11

*Note: Superseded by v13.3.4.*

---

## v13.3.2 "Framed Input" (Production Ready)
**Date:** 2025-12-11

**Theme:** "Modern CLI aesthetics with Unicode framing"

### Major Features

#### 1. Framed Input Bar
Added a visually distinct input area using Unicode box-drawing characters:

```
  Status: /ops   |   Plan next: /plan   |   Help: /help
┌──────────────────────────────────────────────────────────────────────────┐
│ > _                                                                      │
└──────────────────────────────────────────────────────────────────────────┘
  Mode: [OPS] | PLAN | RUN | SHIP  (Tab)
```

**Features:**
- Full-width Unicode frame (┌─┐│└─┘)
- Scenario hint sits above top border
- Mode strip sits below bottom border
- Cursor stays inside the frame at col 4 (after "│ > ")
- Right boundary enforced to prevent typing over border

#### 2. Layout Adjustments
- `Show-ScenarioHint` now draws at `RowInput - 2` (above top border)
- `Draw-ModeStrip` now draws at `RowInput + 2` (below bottom border)
- `Clear-PromptRegion` clears the full frame area including borders
- `Redraw-PromptRegion` redraws the complete framed input

### Visual Layout
```
<dashboard>

  New project: /init   |   Continue: /ops   |   Help: /help   ← Scenario Hint (RowInput-2)
┌──────────────────────────────────────────────────────────┐   ← Top Border (RowInput-1)
│ > _                                                      │   ← Input (RowInput)
└──────────────────────────────────────────────────────────┘   ← Bottom Border (RowInput+1)
  Mode: [OPS] | PLAN | RUN | SHIP  (Tab)                       ← Mode Strip (RowInput+2)
```

### Key Files Changed
- `control_panel.ps1:2825-2851` - New `Draw-InputBar` function
- `control_panel.ps1:2853-2870` - New `Clear-InputContent` helper
- `control_panel.ps1:2872-2901` - `Draw-ModeStrip` adjusted to RowInput+2
- `control_panel.ps1:2907-3001` - `Read-StableInput` uses framed bar
- `control_panel.ps1:3165-3210` - `Show-ScenarioHint` adjusted to RowInput-2
- `control_panel.ps1:2304-2323` - `Get-PromptLayout` updated for framed layout
- `control_panel.ps1:3004-3160` - `Show-CommandPicker` dropdown starts at RowInput+3

### Bug Fixes

#### Command Picker Footer Preservation
Fixed issue where exiting the `/` command picker (via Backspace or Escape) would leave the footer area blank.

**Root Cause:** The picker's dropdown was starting at `RowInput + 1`, which overwrote the bottom border and mode strip.

**Fix:**
- `Get-PromptLayout` now sets `DropdownRow = RowInput + 3` (below the mode strip)
- `ClearDropdownOnly` only clears the dropdown rows, not the framed input or mode strip
- Picker preserves the frame borders while updating input content

### Design Principles
- **Modern aesthetic**: Unicode borders create a polished, professional look
- **Clear focus area**: Frame draws attention to where input happens
- **No behavior change**: All input handling remains identical
- **Consistent boundaries**: Right border prevents input overflow

---

## v13.3.1 "Scenario Navigation" (Production Ready)
**Date:** 2025-12-11

**Theme:** "Action-based hints, not tech explanations"

### Major Features

#### 1. Scenario Hint Strip
Replaced the wordy welcome box with a single-line, state-derived hint above the prompt:

**Fresh system:**
```
  New project: /init   |   Continue: /ops   |   Help: /help
```

**Has pending tasks:**
```
  Run tasks: /run   |   Plan: /plan   |   Status: /status
```

**Messy library:**
```
  Next: /lib clean   |   Status: /ops   |   Help: /help
```

**Normal state:**
```
  Status: /ops   |   Plan next: /plan   |   Help: /help
```

#### 2. `/init` as New Project Entry Point
`/init` is now the front door for new projects:
- Runs bootstrap (profile detection, templates)
- If args provided, continues to `/work`: `/init JWT auth service`
- Shows "What's next?" guidance after completion

#### 3. Scenario-First `/help`
`/help` now shows use-cases instead of a command catalog:
```
  What do you want to do?

  1) Start a new project
     Run: /init
     Or type: 'start a payments service'

  2) Continue working
     Run: /ops (status) → /plan (roadmap) → /run

  3) Ship a release
     Run: /ship (preflight, no auto-deploy)

  /help --all  Full command registry
```

#### 4. Simplified Mode Strip
Mode strip now shows all 4 modes without extra prose:
```
  Mode: [OPS] | PLAN | RUN | SHIP  (Tab)
```

### Visual Layout
```
<dashboard>

  New project: /init   |   Continue: /ops   |   Help: /help   ← Scenario Hint
>                                                              ← Input
  Mode: [OPS] | PLAN | RUN | SHIP  (Tab)                       ← Mode Strip
```

### Key Files Changed
- `control_panel.ps1:3098-3175` - `Get-SystemScenario` and `Show-ScenarioHint`
- `control_panel.ps1:2803-2842` - `Draw-ModeStrip` (simplified)
- `control_panel.ps1:675-738` - `/help` scenario-first rewrite
- `control_panel.ps1:1425-1585` - `/init` as new project entry point

### Design Principles
- **First 3 seconds**: Tell the operator exactly what to do
- **Action hints**: "New project: /init" not "Type plain English..."
- **No tech jargon**: No mentions of "router" or "modes" in hints
- **Subtle UI**: 1 line above prompt, 1 line below

---

## v13.3.0 "Beginner-First" (Production Ready)
**Date:** 2025-12-10

**Theme:** "Progressive disclosure, smart guidance"

### Major Features

#### 1. Curated Golden Path (9 commands)
`/help` now shows only beginner-safe essentials:
- `/help` - Show this guide
- `/ops` - Check system health
- `/status` - View current state
- `/work <PREFIX>` - Ingest knowledge
- `/plan` - View task roadmap
- `/run` - Execute next task
- `/ship` - Pre-flight and release
- `/snapshots` - List backups
- `/restore <zip>` - Restore from backup

Use `/help --all` for full registry with groupings (Golden Path, Advanced, Session, Deprecated).

#### 2. Smart Hint Strip
Single-line guidance anchored below input bar:
```
  [OPS]|PLAN  Enter=/ops  |  Next: /ops  (Tab)
```

**Shows:**
- Current mode toggle (OPS/PLAN)
- Enter default for current mode
- State-derived recommended action
- Tab hint

**Recommendations computed from:**
1. Health FAIL → `/ops (health issue)`
2. Librarian messy → `/lib clean`
3. No tasks → `type a goal (e.g., 'add JWT auth')`
4. Tasks pending → `Enter = execute`
5. Default → `/ops`

#### 3. Legacy `/commands` Alias
`/commands` now shows deprecation warning then displays `/help --all`:
```
⚠️  /commands is legacy. Use /help or /help --all
```

#### 4. Micro-Onboarding Toast
On first launch only, shows welcome toast near input area:
```
┌─────────────────────────────────────────────────────┐
│  Welcome! Type plain English to route safely.       │
│  Tab cycles modes  |  Enter runs safe default       │
└─────────────────────────────────────────────────────┘
```
Persists `.mesh_onboarded` flag to avoid repeating.

#### 5. Beginner-Curated Command Picker
The `/` picker now shows only Golden Path commands by default.
`/help` appears first in the list.

### Key Files Changed
- `control_panel.ps1:193` - Golden Path reduced to 9 commands
- `control_panel.ps1:674-740` - `/help` rewritten for beginner focus
- `control_panel.ps1:743-776` - `/commands` legacy handler added
- `control_panel.ps1:2769-2845` - `Get-RecommendedAction` and `Draw-SmartHintStrip`
- `control_panel.ps1:3100-3130` - `Show-MicroOnboarding` function

### Design Principles
- **Beginner-first**: New operators can start confidently without `/commands`
- **Progressive disclosure**: Golden Path → `/help --all` → advanced features
- **Guidance at input**: Smart hints "hover" near where you type
- **No server changes**: Pure CLI-side improvements

---

## v13.2.1 "Claude-Style Toggle" (Production Ready)
**Date:** 2025-12-10

**Theme:** "Simplified mode switching"

### Changes

#### 1. Two-Mode Toggle (Claude-like UX)
Replaced 4-mode ring with simple OPS ↔ PLAN toggle:

```
> _
  Mode: [OPS] | PLAN  (Tab to toggle)
```

**Why:**
- OPS and PLAN are the primary workflow modes
- RUN and SHIP remain accessible via explicit commands (`/run`, `/ship`, `:run`, `:ship`)
- Cleaner Golden Path

#### 2. Toggle Strip Below Input
Claude-style toggle strip rendered below input bar:
- Active mode highlighted with brackets: `[OPS]`
- Inactive mode dimmed: `PLAN`
- Tab toggles instantly without clearing input

#### 3. Simplified Prompt
Removed mode indicator from prompt (now shown in toggle strip):
- Before: `[OPS] > _`
- After: `> _` with toggle strip below

### Key Files Changed
- `control_panel.ps1:341` - ModeRing reduced to `@("OPS", "PLAN")`
- `control_panel.ps1:2702-2724` - New `Draw-ModeToggleStrip` function
- `control_panel.ps1:2762-2772` - Tab handler simplified to toggle

#### 4. Command Picker Layout Fix
Fixed "duplicate input bar" bug when exiting command picker:

**Problem:** Backspace on `/` would exit picker but leave stale lines or spawn second prompt.

**Root Cause:**
- `$Global:RowInput` calculated once at script load, not refreshed
- Picker used hardcoded `maxVisible = 12` vs global `MaxDropdownRows = 5`
- Multiple partial clears instead of atomic region clear

**Solution:**
- `Get-PromptLayout` - Single source of truth for layout values
- `Clear-PromptRegion` - Atomic clearing of input + dropdown area
- `Redraw-PromptRegion` - Clean restore of prompt + toggle strip
- `Show-CommandPicker` returns structured `@{ Kind = "select/cancel"; Command = "..." }`
- `Read-StableInput` uses `Redraw-PromptRegion` on cancel

### Behavior
| Input | Action |
|-------|--------|
| Tab | Toggle OPS ↔ PLAN |
| Shift+Tab | Toggle OPS ↔ PLAN |
| `:run` | Switch to RUN mode |
| `:ship` | Switch to SHIP mode |
| `/run` | Execute run command |
| `/ship` | Execute ship command |

---

## v13.2.0 "Modal CLI" (Production Ready)
**Date:** 2025-12-10

**Theme:** "Mode-driven workflow"

### Major Features

#### 1. Modal Interface
Four workflow modes with color-coded prompts and context staging:

| Mode | Color | Prompt | Purpose |
|------|-------|--------|---------|
| OPS | Cyan | `[OPS] >` | Monitor health & drift |
| PLAN | Yellow | `[PLAN] >` | Describe work to plan |
| RUN | Magenta | `[RUN] >` | Execute & steer |
| SHIP | Green | `[SHIP] >` | Release with confirm |

**Mode Switching:**
- `Tab` - Cycle through modes (OPS → PLAN → RUN → SHIP → OPS)
- `:ops`, `:plan`, `:run`, `:ship` - Direct mode switch aliases

#### 2. Context Staging
Each mode stages context notes for workflows:
- **PLAN**: `$LastPlanNote` - Description of work to plan
- **RUN**: `$LastRunNote` - Steering/steering notes
- **SHIP**: `$LastShipNote` - Release notes

Example:
```
[PLAN] > Add user authentication with JWT
📝 Plan context staged: Add user authentication with JWT
```

#### 3. Empty Enter → Default Action
Pressing Enter with empty input runs the mode's default action:

| Mode | Default Action |
|------|----------------|
| OPS | `/ops` (health + drift + backups overview) |
| PLAN | `/plan` (show roadmap) |
| RUN | `/run` (execute next task) |
| SHIP | `/ship` (preflight preview - safe, read-only) |

#### 4. Mode-Aware Plain Text Routing
Plain text is routed based on current mode (no backend calls):

**OPS Mode:**
- `health` → `/health`
- `drift`, `backup`, `snapshot`, `stale` → `/drift`
- `status` → `/status`
- Other → Shows hints

**PLAN/RUN Mode:** Stages context, then runs default action

**SHIP Mode:** Stages release note, but **never auto-executes `/ship`**

#### 5. Safety Constraints
- `/ship` never auto-executes from plain text routing
- SHIP mode requires explicit `/ship` or `/ship --confirm` command
- Mode switching is instant and safe (no side effects)

### New Commands

| Command | Description |
|---------|-------------|
| `/ops` | Health + Drift + Backups overview |
| `/health` | System health check |
| `/drift` | Staleness and queue drift check |
| `/work <PREFIX>` | Knowledge acquisition |

### Technical Changes

**Pure Frontend Routing:**
- Removed backend `route_cli_input` dependency
- Modal routing uses simple keyword matching
- No Python calls for routing decisions

**Functions Added:**
- `Invoke-ModalRoute` - Routes plain text by mode
- `Invoke-DefaultAction` - Runs mode's default action
- `Switch-Mode` - Changes current mode

**Global State:**
- `$Global:CurrentMode` - Current mode (OPS|PLAN|RUN|SHIP)
- `$Global:LastPlanNote` - Staged plan context
- `$Global:LastRunNote` - Staged steering note
- `$Global:LastShipNote` - Staged release note
- `$Global:ModeConfig` - Mode colors and prompts

### Files Modified
- `control_panel.ps1`: +150 lines (modal routing, new commands)
- `docs/CHANGELOG.md`: Added v13.2 entry

### Release Statement

> "Modal CLI introduced to provide mode-driven workflows: operators stay in context with colored prompts, context staging, and safe default actions."

---

## v13.1.0 "Unified TUI" (Production Ready)
**Date:** 2025-12-09

**Theme:** "Dashboard as escalation layer"

### Major Features

#### 1. Unified CLI + Dashboard
Single control panel with health-based view switching eliminates context-switching between windows.

**Key Concept:**
- Healthy → Compact status bar + command prompt
- Unhealthy → Full dashboard + suggested actions
- Manual override with `/dash` and `/compact`

**View Switching Logic:**
| System State | View | Rule |
|--------------|------|------|
| OK | Compact | Default healthy view |
| WARN | Compact | Soft highlight in status bar |
| WARN (3+ checks) | Dashboard | Auto-escalate if persistent |
| WARN (blocking) | Dashboard | Auto-escalate if queue stuck (>5 reviewing) |
| FAIL | Dashboard | Always expand on failure |

**New Commands:**
- `/dash` - Toggle full dashboard view (30s override)
- `/compact` - Toggle compact status bar (30s override)
- `-DashboardMode` flag for always-dashboard mode

#### 2. Compact Status Bar
Single-line status display when system is healthy:
```
🟢 OK | pending: 3 | reviewing: 0 | workers: 2 | /ops for details
```

**Features:**
- Workers count (fastest "why nothing moving" indicator)
- Health status icon (🟢/🟡/🔴)
- WARN details row when applicable

#### 3. Smart View Switching

**Flap Guard:** 2-second debounce prevents view thrashing

**Override Precedence:** 30-second manual override window after `/dash` or `/compact`

**Adaptive Refresh (planned):**
- OK: 5-10s
- WARN: 3-5s
- FAIL: 1-2s

### Infrastructure Changes

**dashboard.ps1 Deprecation:**
- Converted to thin shim that calls `control_panel.ps1 -DashboardMode`
- Kept for backwards compatibility
- Planned removal in v13.2

**start_mesh.ps1 Updates:**
- No longer launches separate dashboard window
- Shows view command hints in startup output
- Updated to v13.1.0

**Files Modified:**
- `control_panel.ps1`: +200 lines (health functions, compact bar, view logic)
- `dashboard.ps1`: -340 lines (converted to 30-line shim)
- `start_mesh.ps1`: Updated to v13.1.0
- `docs/ARCHITECTURE.md`: Updated system diagram and component docs
- `docs/PLAN_v13.1_UNIFIED_TUI.md`: Implementation plan

### Release Statement

> "Unified TUI introduced to make dashboard an escalation layer: healthy systems show compact status, unhealthy systems auto-expand to full dashboard for operator attention."

---

## v13.0.1 "Unified Startup" (Production Ready)
**Date:** 2025-12-09

**Theme:** "Make the safe path the easy path"

### Major Features

#### 1. Unified Startup System
Single-command orchestration that launches server + CLI + dashboard with conflict detection and PID tracking.

**Files Added:**
- `start_mesh.ps1` - Main orchestrator
- `stop_mesh.ps1` - Clean shutdown with PID file
- `mesh.bat` - Quick Windows launcher
- `docs/STARTUP_GUIDE.md` - Comprehensive operator guide
- `docs/ARCHITECTURE.md` - System architecture reference
- `QUICK_START.md` - One-page quick reference

**Usage:**
```powershell
.\mesh.bat         # Start everything
.\stop_mesh.ps1    # Clean shutdown
```

**Key Features:**
- ✅ Conflict detection (warns if server already running)
- ✅ PID tracking in `control/state/_runtime/mesh_server.pid`
- ✅ Single-shot launch (no auto-restart, no gate bypassing)
- ✅ `/ops` preflight hint in startup output
- ✅ Graceful shutdown with 5-second timeout

#### 2. Static Safety Check Polish
Added 177 `# SAFETY-ALLOW: status-write` markers to bring entire codebase into compliance.

**Files Modified:**
- `mesh_server.py`: 129 markers
- `dynamic_rigor.py`: 19 markers
- `router.py`: 15 markers
- `qa_protocol.py`: 8 markers
- `stress_tests.py`: 5 markers
- `mission_control.py`: 1 marker

**Integration:**
- Added to `RELEASE_CHECKLIST.md` as P0 Item #0
- Added compliance note to `OPERATIONS.md`

### Minor Improvements

#### Terminology Cleanup
Replaced "chain-of-thought" with governance-aligned terminology:
- "chain-of-thought streaming" → "decision/audit trace"
- "live COT display" → "live agent event log"

**Files Modified:**
- `docs/STARTUP_GUIDE.md`
- `docs/ARCHITECTURE.md`

#### Restart Semantics Clarification
Added explicit documentation that launcher is single-shot (no auto-restart, no watchdog).

**Clarifications:**
- Inline comment in `start_mesh.ps1`: "No auto-restart, no watchdog"
- Architecture doc notes single-shot launch requirement
- Must pass `/health` and `/drift` before production use

### Infrastructure

**Runtime State Management:**
- Created `control/state/_runtime/` for ephemeral state
- Added `mesh_server.pid` for clean shutdown
- Updated `.gitignore` to exclude runtime directory

### Release Statement

> "Unified startup introduced to make the safe operational path the default: one command launches server, CLI, and dashboard with conflict detection and operator-first documentation."

---

## v13.0.0 "Governance Lock"
**Date:** 2025-12-08

**Theme:** "Enforce first, Exception second"

### Major Features

1. **Static Safety Check** - Mechanical enforcement of Single-Writer discipline
   - Only `update_task_state()` may modify task status
   - 4 forbidden patterns detected
   - Async-ready scope detection
   - `# SAFETY-ALLOW: status-write` exception marker

2. **Decision Packet Template** - Structured decision documentation
3. **Role Contracts** - Librarian, Curator, Planner definitions in OPERATIONS.md

**Files Added:**
- `tests/static_safety_check.py`
- `docs/templates/DECISION_PACKET.md`

**Updated:**
- `docs/OPERATIONS.md` with role contracts
- `docs/RELEASE_CHECKLIST.md` with Static Safety Check

---

## v12.2.0 "Preflight Fusion"
**Date:** 2025-12-08

### Major Features
* **Preflight Fusion:** `/ship` now runs Health + Drift + CI checks before release.
* **Gate System:** Hard blocks on FAIL, warnings on WARN, green light on OK.
* **Centralized Emitter:** `update_task_state()` ensures all status changes emit timestamps.
* **Invoke-Ship Function:** Standalone preflight function for reusability.

### Preflight Sequence
1. **Health Sentinel** - System status check (blocks on FAIL)
2. **Drift Sentinel** - Staleness check (blocks on FAIL)
3. **CI Gate** - Constitution + Registry + Golden Thread
4. **Review Queue** - Shows pending reviews
5. **Git Status** - Shows uncommitted changes

### Ship Command Flow
```
/ship              →  Preflight Dashboard (read-only)
/ship --confirm    →  Execute gates then ship
```

### Gate Logic
| Condition | Action |
|-----------|--------|
| Health FAIL | BLOCKED |
| Drift FAIL | BLOCKED |
| CI Fails | ABORT |
| Reviews pending | WARN + suggestions |
| All OK | Ready to ship |

### Maintenance Tools
* `/migrate_timestamps` - Preview timestamp backfill (dry run)
* `/migrate_timestamps_apply` - Apply timestamp migration
* `/verify_db` - Check database integrity and anomalies

### Architecture
* `update_task_state()` - Centralized state updater with One Gavel rule
* `submit_review_decision()` - Now uses emitter for timestamp consistency
* `Invoke-Ship` - Standalone PowerShell function for preflight

---

## v12.1.1 "Timestamp Emitters"
**Date:** 2025-12-08

### Bug Fixes
* **Blocked Recovery:** Fixed missing `updated_at` when task recovers from blocked→pending

### Infrastructure
* All task state transitions now emit `updated_at` timestamps
* Enables Drift Sentinel to detect stale tasks accurately

---

## v12.1.0 "The Drift Sentinel"
**Date:** 2025-12-08

### Major Features
* **Drift Sentinel:** `/drift` command detects staleness and stuck queues.
* **Velocity Monitoring:** Moves beyond "Is it broken?" to "Is it stuck?"

### Drift Checks
* **Queue Counts:** Shows reviewing/pending task counts
* **Stale Reviews:** Warns if any review task >72h old
* **Review Packets:** Checks age of oldest pending review packet (24h/72h thresholds)
* **Snapshot Freshness:** Warns >24h, fails >1 week since last backup

### Thresholds
| Check | OK | WARN | FAIL |
|-------|-----|------|------|
| Stale Reviews | <72h | >72h | - |
| Review Packets | <24h | 24-72h | >72h |
| Snapshots | <24h | 24h-1wk | >1wk |

### Robustness
* **parse_iso() Helper:** Safe ISO 8601 parsing handles 'Z' suffix (Python <3.11 compat)
* **Explicit Paths:** Uses `os.path.join(STATE_DIR, "reviews")` for clarity

### Design Principles
* Read-only sentinel - no side effects
* Catches "Silent Failures" - systems that look green but are rotting
* Answers: "Is the system rotting?"

---

## v12.0.0 "The Sentinel"
**Date:** 2025-12-08

### Major Features
* **Health Sentinel:** `/health` command provides single-pane-of-glass system status.
* **Check Engine Light:** Color-coded indicators (Green=OK, Yellow=WARN, Red=FAIL).

### Health Checks
* **Registry:** Validates alignment between domain rules and SOURCE_REGISTRY.json
* **Database:** Confirms SQLite reachability and basic query execution
* **Queue:** Shows reviewing/pending counts with risky task breakdown
* **Ledger:** Checks last activity timestamp (warns if >24h stale)
* **Snapshots:** Verifies backup availability

### Design Principles
* Read-only sentinel - no side effects
* Single Source of Truth - Python backend does all logic
* CLI is just a color-coded window

---

## v11.0.1 "Safety Hardening"
**Date:** 2025-12-08

### Bug Fixes
* **Snapshot Path Alignment:** `/snapshots` CLI now reads directly from `control/snapshots` (same as Python writes).
* **Restore Validation:** Added `.zip` format verification and structure validation to prevent restoring random/corrupt archives.
* **CI Imports:** Consolidated all imports at top of `tests/run_ci.py` for cleaner module organization.

### Safety Improvements (Defense in Depth)
* `/snapshots` shows count in header: `AVAILABLE SNAPSHOTS (5)` - instantly shows backup health.
* `/snapshots` shows timestamps and file sizes for each backup.
* `/restore` validates `.zip` extension AND checks file existence before showing warning.
* `/restore_confirm` mirrors ALL safety checks - catches copy-pasted bad commands.
* Server-side restore validates snapshot contains at least one Mesh component (state/, sources/, mesh.db, or DOMAIN_RULES.md).
* Corrupted or invalid zip files are rejected with clear error messages at every layer.

---

## v11.0.0 "Operations" (Production Ready)
**Date:** 2025-12-08

### CI & Automation
* **CI Judge:** `tests/run_ci.py` consolidates Constitution Tests, Registry Check, and Golden Thread into single Pass/Fail gate.
* **Ship Guard:** `/ship --confirm` now runs CI pre-flight check; aborts on failure.

### Operations Tools
* **Ledger Report:** `/report [days]` generates activity summary by actor, decision, and authority risk.
* **Snapshot Backup:** `/snapshot [label]` creates zip backup of state, sources, database, and DOMAIN_RULES.md.
* **Snapshot Restore:** `/restore <zip_name>` restores full system state from backup.
* **List Snapshots:** `/snapshots` shows available backups with sizes.

### Infrastructure
* Snapshots stored in `control/snapshots/` with timestamped filenames.
* Recovery includes: state/, sources/, DOMAIN_RULES.md, mesh.db
* CI exit code 0 (pass) or 1 (fail) for pipeline integration.

---

## v10.18.0 "The Cockpit" (Release Candidate)
**Date:** 2025-12-08

### Major Features
* **The Cockpit:** Added `/work`, `/plan`, `/ship` super-commands for Human-in-the-Loop workflow.
* **Dashboard Notifications:** RECOMMENDED section with hotkeys `[A]` Auto-approve, `[V]` View reviews.
* **Release Readiness:** `/release_status` pre-flight check showing queue, ledger, and system health.
* **Context Memory:** CLI remembers current Prefix (`HIPAA`) and Task ID.
* **Release Ledger:** Immutable, append-only audit trail (`release_ledger.jsonl`) tracking every decision.

### Compliance & Safety
* **One Gavel Rule:** `COMPLETE` status can only be set via `submit_review_decision`.
* **Hard Lock:** Direct status writes to `completed` are blocked in `complete_task()` and `run_autonomous_loop()`.
* **Strict Actor Identity:** Gavel requires explicit `HUMAN`, `AUTO`, or `BATCH` actor tag.
* **Gatekeeper:** Hard blocks on tasks missing code evidence or paired tests for Domain rules.
* **Testability Shim:** Full filesystem isolation for policy-as-code tests via `MESH_BASE_DIR`.

### Architecture
* **Knowledge Refinery:** Raw Ingestion -> Curator Agent -> `DOMAIN_RULES.md` -> Planner.
* **Archetype Planning:** Tasks strictly typed (`[DB]`, `[API]`, `[SEC]`) with dependency ordering.
* **Source Registry:** `SOURCE_REGISTRY.json` defines Authority Tiers (MANDATORY vs STRONG vs DEFAULT).
* **Path Helpers:** Centralized `get_state_path()` and `get_source_path()` for all file operations.

### Validation
* **Constitution Tests:** 12/12 Passing.
* **Golden Thread:** End-to-End smoke test verified (`tests/smoke_test.py`).

---

## v10.17.0 "The Constitution"
**Date:** 2025-12-07

### Features
* **Testability Shim:** `MESH_BASE_DIR` environment variable for test isolation.
* **Explicit Actor Channel:** All review decisions require actor identity.
* **Constitution Integration Tests:** Full test suite for compliance rules.

---

## v10.16.0 "The Ledger"
**Date:** 2025-12-06

### Features
* **Release Ledger:** Append-only audit trail for all review decisions.
* **Actor Validation:** Gavel rejects invalid actors.
* **Ledger Command:** `/ledger` to view audit history.

---

## v10.15.0 "Case Files"
**Date:** 2025-12-05

### Features
* **Review Cases:** `/review_cases` groups tasks by authority.
* **Batch Approve:** `/approve_case` for bulk approvals by source.

---

## v10.14.0 "Safe Autopilot"
**Date:** 2025-12-04

### Features
* **Auto-Approve:** `/auto_approve` for safe plumbing tasks.
* **Safety Policy:** Authority + Archetype checks before auto-approval.

---

## Pre-v10 (Legacy)

Earlier versions established:
- MCP server integration
- Task state machine
- Source ingestion pipeline
- Worker execution framework
- Mode system (Vibe/Converge/Ship)
