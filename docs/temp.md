## Merge Complete

**Done. Merged to main.**

```
main (HEAD)
├── 45376a6 chore: remove legacy F4 overlay and dead code
├── 44d1391 feat(ui): v22.0 Golden Parity + P7 Optimize Stage (62/62 tests)
└── f20d0cb fix(ui): dirty-gated rendering to eliminate perma-refresh flicker
```

**Cleanup completed:**
- Deleted `RenderStreamDetails.ps1`
- Deleted `test_stream_details_overlay.py`
- Updated F4 test → F2 only

**Final status:**
- 62/62 pre-ship sanity ✅
- 10/10 golden parity ✅
- 81 files, +31,546 / -10,483 lines

Ready for manual smoke (2 min): Launch → /go → /plan → F2 → ESC → resize.

---

## Command Guards Added

| Command | Guard | Message if blocked |
|---------|-------|-------------------|
| `/go` | Requires `ACCEPTED` | "Draft not accepted - run /accept-plan first" |
| `/go` | Requires any plan | "No plan - run /draft-plan first" |
| `/accept-plan` | Requires `DRAFT` | "No draft to accept - run /draft-plan first" |

**Tests:** 64/64 pass (added CHECK 63-64)

**Commit:** `a33942e`

---

## Code Review: Guard Implementation

**What we did:** Inline guards in `Invoke-CommandRouter.ps1` switch cases.

| Aspect | Verdict |
|--------|---------|
| Single file change | ✅ Good - localized |
| Co-located guard + logic | ✅ Good - easy to read |
| Tests added | ✅ Good - verified behavior |
| Clear user feedback | ✅ Good - actionable hints |

**Cleaner alternatives (if guards grow):**
- Separate `Test-CanAcceptPlan` functions
- Declarative guard table with RequiredStatus + Hint

**Verdict:** Pragmatic for 2 simple guards. Refactor if complexity grows.

---

## Refresh Optimization Options

**Problem:** Picker/input changes trigger `MarkDirty()` → full `[Console]::Clear()` → flicker.

| Option | Description | Effort | Benefit |
|--------|-------------|--------|---------|
| **A: Region flags** | Separate dirty flags per region | Medium | Best - targeted redraws |
| **B: Picker bypass** | Don't `Clear()` when only picker changed | Low | Good - fixes main issue |
| **C: Diff rendering** | Compare frames, write only changed cells | High | Overkill |

**Recommended: Option A** - Right abstraction, minimal code increase.

Design:
```powershell
[HashSet[string]]$DirtyRegions  # "input", "picker", "toast", "content", "all"
if ($state.IsDirty("all")) { Clear + full }
else { partial redraws per region }
```

---

## Region-Based Dirty Rendering - Implemented

**Commit:** `ff8d410`

**Regions:**
| Region | Triggers | Behavior |
|--------|----------|----------|
| `all` | resize, init | Clear-Screen + full render |
| `content` | data change, page switch, overlay, commands | Clear-Screen + full render |
| `picker` | dropdown open/close/navigate | Partial: clear stale + render dropdown |
| `input` | typing, backspace | Partial: render input box only |
| `toast` | toast set/expire | Partial: render toast line only |
| `footer` | mode change | Partial: render hint bar only |

**Key files changed:**
- `UiState.ps1`: `DirtyRegions` HashSet + `IsDirty(region)`, `HasDirty()`, `ClearDirty()`
- `Start-ControlPanel.ps1`: Split render loop (full vs partial paths)
- `Console.ps1`: `Clear-Screen` wrapper with counter for testing
- `CommandPicker.ps1`: `Render-PickerArea` handles shrink/close

**Tests:** 67/67 pre-ship + 10/10 golden (CHECK 65-67 added)

---

## Bug Fix: UiCache Type Mismatch

**Commit:** `3ba0b9f`

**Problem:** `Cannot convert "UiSnapshot" value of type "UiSnapshot" to type "UiSnapshot"`

**Cause:** PowerShell classes are scope-bound. Module reload creates a "new" UiSnapshot type that can't be assigned to the old typed `[UiSnapshot]$LastSnapshot` property.

**Fix:** Changed `[UiSnapshot]$LastSnapshot` → `[object]$LastSnapshot` in UiCache.ps1

---

## Bug Fix: All Cross-Class Type References

**Commit:** `f96f7bc`

Extended fix to all model classes:

| Class | Properties Changed |
|-------|-------------------|
| UiState | Toast, EventLog, Cache → `[object]` |
| UiSnapshot | PlanState, LaneMetrics, SchedulerDecision, Alerts → `[object]` |
| UiEventLog | Events → `ArrayList`, Add param → `[object]` |
| UiCache | LastSnapshot → `[object]` |

**Tests:** 67/67 pass

---

## Bug Fix: Remove Function Parameter Type Constraints

**Commit:** `8aaf99e`

**Problem persisted** because function parameters like `[UiState]$State` reject objects created with old class definitions on module reload.

**Fix:** Removed all `[UiState]$`, `[UiSnapshot]$`, `[PlanState]$`, `[LaneMetrics]$` type constraints from function parameters across 13 files.

Now using duck typing - objects work as long as they have expected properties.

**Note:** You must restart your PowerShell session to clear cached old class types.
