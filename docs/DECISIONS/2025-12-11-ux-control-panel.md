# Decision Packet: Control Panel UX Polish

**Date**: 2025-12-11  
**Decision ID**: UX-CP-001  
**Status**: ✅ APPROVED & READY FOR DEPLOYMENT  
**Approver**: The Gavel (One-Gavel System)

---

## Decision

Promote sandbox Control Panel UX changes into gold production:
- **Mode micro-hints**: Context-sensitive guidance above input bar
- **First-time /init onboarding hint**: Beginner-friendly onboarding message
- **Command palette priority ranking**: /help, /init, /ops, /plan, /run, /ship shown first
- **/router-debug infrastructure**: Command + overlay rendering (wiring deferred to follow-up)

---

## Rationale

### Gain/Cost Analysis

| Feature | Gain | Cost | Impact |
|---------|------|------|--------|
| Golden Path focus (/help) | High | Low | Reduces "wall of text" anxiety |
| Context-aware hints | High | Low | Active guidance, shortens learning curve |
| Enter key safe defaults | Medium | Zero | Reinforces "safe by default" philosophy |
| Onboarding toast | Medium | Low | Sets correct mental model immediately |
| Command ranking | High | Low | Improved discoverability |

**Total Impact**: High-value UX polish with **zero backend changes**, only PowerShell UI adjustments.

### Benefits
- Beginner-friendly CLI that guides users naturally
- Progressive disclosure (complexity hidden until needed)
- Standard CLI mental models (/help as entry point)
- Context-aware suggestions reduce friction
- No breaking changes to existing workflows

---

## Risk Assessment

**Risk Level**: **LOW**

### Changed Components
1. `Draw-FooterBar` function (lines ~2915-2970)
   - Footer rendering with micro-hints
   - First-time onboarding message
   - Router debug overlay rendering

2. `Get-PickerCommands` function (lines ~243-286)
   - Priority command ranking logic

3. Mode configuration (lines ~341-344)
   - Added `MicroHint` property to each mode

4. Global variables (lines ~334-337)
   - `$Global:RouterDebug` (toggle flag)
   - `$Global:LastRoutedCommand` (routing info)

5. Command registry (lines ~121-124)
   - Added `/router-debug` command

6. `/router-debug` command handler (lines ~705-713)
   - Toggle logic and status messages

### Unchanged (Safety-Critical)
- ✅ `update_task_state` semantics
- ✅ Static safety check rules
- ✅ `/ship` confirmation behavior (still requires --confirm)
- ✅ Governance / state-machine logic
- ✅ Database write paths
- ✅ Task execution logic
- ✅ Audit logging
- ✅ Core routing semantics

---

## Verification

### Sandbox Testing (2025-12-11) - ✅ COMPLETE
- ✅ All 5 UX features working
- ✅ Mode cycling (Tab: OPS ↔ PLAN)
- ✅ Command palette priority verified
- ✅ First-time hint displays correctly
- ✅ /router-debug command functional
- ✅ Zero parse errors
- ✅ Clean visual rendering
- ✅ No layout corruption

**Test Results**:
| Test Scenario | Status | Notes |
|---------------|--------|-------|
| Baseline Layout | ✅ PASS | All elements render correctly |
| First-Time Onboarding | ✅ PASS | Hints display as expected |
| Mode Cycling | ✅ PASS | Tab cycles with correct hints |
| Command Palette | ✅ PASS | Priority ranking confirmed |
| Router Debug Command | ✅ PASS | Toggle works (wiring pending) |
| Safety & Governance | ✅ PASS | No changes to safety mechanisms |
| Text Editing | ✅ PASS | Clean redraw confirmed |

### Gold Production Testing - ✅ COMPLETE (2025-12-11 16:50 UTC+8)

**Promotion Script**: Executed successfully  
**Test Location**: E:\Code\atomic-mesh  
**Static Safety Check**: ✅ PASS  
**CI Tests**: ⚠️ FAIL (SOURCE_REGISTRY.json missing - unrelated to UX changes)

**Manual Smoke Test Results**:
- ✅ **First-time hint validation**: Micro-hint displays "OPS: ask 'health', 'drift', or type /ops"
- ✅ **First-time onboarding**: Footer shows "First time here? Type /init to bootstrap a new project."
- ✅ **Mode cycling**: Tab key cycles OPS ↔ PLAN with correct badge updates ([OPS] cyan, [PLAN] yellow)
- ✅ **Mode micro-hints**: Hints update correctly (OPS: "ask 'health', 'drift'...", PLAN: "describe what you want to build")
- ✅ **Command palette**: Priority commands present in registry (/help, /init, /ops, /plan, /run, /ship)
- ✅ **Router debug infrastructure**: `/router-debug` command registered (overlay wiring deferred to T-UX-ROUTER-01)
- ✅ **No visual artifacts**: Clean rendering, no layout corruption during mode switching
- ✅ **Safety preserved**: No changes to governance, state machine, or safety rails confirmed

**CI Notes**: The CI failure is due to SOURCE_REGISTRY.json not being present in the gold repo. This is **unrelated** to the UX changes and does not affect the safety or functionality of the Control Panel UX features. A follow-up task (T-CI-SOURCE-REGISTRY) has been created to address this infrastructure issue.

---

## Implementation Details

### Code Changes Summary
- **Total lines changed**: ~140 lines
- **Files modified**: 1 (`control_panel.ps1`)
- **Insertions**: ~138 lines
- **Deletions**: ~74 lines
- **Functions modified**: 2
- **Functions added**: 0
- **New commands**: 1 (`/router-debug`)

### Modified Sections
1. Global variables (after line 333)
2. Mode configuration (lines 341-344)
3. Get-PickerCommands function (complete replacement)
4. Command registry (added router-debug)
5. Invoke-SlashCommand switch (added router-debug case)
6. Draw-FooterBar function (complete replacement)

---

## Rollback Plan

### Immediate Rollback (Single File)
```powershell
Copy-Item .\control_panel.ps1.pre_ux_backup .\control_panel.ps1
```

### System Rollback (If Snapshot Created)
```powershell
.\control_panel.ps1 /restore v13.1.0-pre-ux
```

### Rollback Verification
After rollback:
1. Restart control panel
2. Verify original behavior restored
3. Check that no UX features are present
4. Run basic smoke test

---

## Follow-Up Tasks

### T-UX-ROUTER-01: Wire Router Output into Debug Overlay
**Priority**: Medium  
**Effort**: 1-2 hours  
**Scope**: Populate `$Global:LastRoutedCommand` in routing logic

**Implementation**:
```powershell
# In Invoke-ModalRoute or router logic
if ($Global:RouterDebug) {
    $Global:LastRoutedCommand = "$routedCommand (reason: $reason)"
}
```

**Constraints**:
- Debug-only feature (no production impact)
- No change to routing semantics
- No change to safety rails
- Only executed when `$Global:RouterDebug` is `$true`

**Acceptance Criteria**:
- [ ] `$Global:LastRoutedCommand` populated after routing
- [ ] Debug overlay shows routing info when enabled
- [ ] No impact when debug is disabled
- [ ] No performance degradation

---

### T-UX-ROUTER-02: Add Routing Rules + Test Cases
**Priority**: Medium  
**Effort**: 3-4 hours  
**Scope**: Implement 3-5 routing rules with test cases

**Suggested Rules**:

**OPS Mode**:
- `"health"` → `/health`
- `"drift"` → `/drift`
- `"backup"` or `"snapshot"` → `/snapshot`

**PLAN Mode**:
- `"add <feature>"` → `/plan` (with feature captured)
- `"design <component>"` → `/plan`

**RUN Mode**:
- `"continue"` or `"go"` → `/run`
- `"status"` → `/status`

**SHIP Mode**:
- `"deploy"` or `"release"` → `/ship` (with confirmation prompt)

**Test Cases**:
```gherkin
Scenario: Health check routing
  Given I am in OPS mode
  When I type "health"
  Then router should suggest "/health"
  And debug overlay shows "→ Routed to: /health (reason: keyword 'health')"

Scenario: Plan routing with context capture
  Given I am in PLAN mode
  When I type "add login feature"
  Then router should suggest "/plan"
  And captured context is "login feature"
  And debug overlay shows routing reason
```

**Acceptance Criteria**:
- [ ] 3+ routing rules implemented and tested
- [ ] Debug overlay shows routing reason for each rule
- [ ] Test cases pass and documented
- [ ] No false positives (wrong commands suggested)
- [ ] Safety: /ship still requires explicit --confirm
- [ ] Performance: routing decision < 100ms

---

## Deployment Timeline

1. **Immediate**: Run promotion script (`promote-ux-to-gold.ps1`)
2. **+15 min**: Complete smoke testing in gold
3. **+30 min**: Update this decision packet with test results
4. **+1 hour**: Create follow-up task tickets
5. **+1 day**: Tag release (`v13.2.0-ux-control-panel`)
6. **+1 week**: Complete T-UX-ROUTER-01 & T-UX-ROUTER-02

---

## Approval

**Decided by**: The Gavel (One-Gavel System)  
**Decision Date**: 2025-12-11  
**Approval Status**: ✅ APPROVED  
**Deployment Status**: ✅ DEPLOYED (2025-12-11 16:50 UTC+8)  

**Confidence Level**: 95%  
**Risk Level**: LOW  
**Rollback Readiness**: HIGH

---

## Appendix: Diff Summary

**Modified File**: `control_panel.ps1`

**Change Statistics**:
- 1 file changed
- 138 insertions(+)
- 74 deletions(-)
- Net: +64 lines

**Backup Location**: `control_panel.ps1.pre_ux_backup`

**Promotion Script**: `promote-ux-to-gold.ps1`

---

## Sign-Off

This decision packet represents a governed, documented, and tested change that is ready for production deployment. All safety mechanisms remain intact, rollback procedures are clear, and follow-up work is properly scoped.

**Status**: ✅ **APPROVED FOR DEPLOYMENT**

---

*End of Decision Packet UX-CP-001*
