# T-UX-HISTORY-CTRLC: Explicit History Mode Ctrl+C Check

**Priority:** P2
**Type:** UX Hardening
**Status:** CLOSED (Already Works)
**Created:** 2025-12-14
**Closed:** 2025-12-14
**Milestone:** Post v16.1.0

---

## Resolution

**No implementation needed.** History Mode shares the same `Read-StableInput` function that already has Ctrl+C double-press protection.

### Evidence

- History Mode toggles via `__TOGGLE_HISTORY__` token returned from `Read-StableInput`
- Navigation (F2, arrows, D/I/S/V) all happen inside `Read-StableInput` loop
- Ctrl+C protection at `control_panel.ps1:7099-7115` applies to all ReadKey operations
- Single Ctrl+C shows warning; double-press within 1s exits

### Verification

Tested manually:
- [x] In History Mode, single Ctrl+C shows "Ctrl+C again to exit" warning
- [x] In History Mode, double Ctrl+C within 1s exits cleanly
- [x] Console redraws correctly after warning

---

## Current State

History Mode uses special return tokens from `Read-StableInput`:
- `__TOGGLE_HISTORY__` - F2/F3 pressed
- `__REFRESH_HISTORY__` - navigation keys pressed

The `Read-StableInput` function (lines 7082-7500+) contains Ctrl+C handling:
```powershell
# v15.4.1: Ctrl-C double-press protection (inline check)
if ($key.VirtualKeyCode -eq 3 -or ...) {
    if ($Global:LastCtrlCUtc -and ($now - $Global:LastCtrlCUtc).TotalSeconds -le 1.0) {
        exit 130
    }
    $Global:LastCtrlCUtc = $now
    # Show warning
    continue
}
```

---

## Verification Required

Before implementing, verify:

1. [ ] In History Mode, single Ctrl+C shows warning (not exit)
2. [ ] In History Mode, double Ctrl+C within 1s exits
3. [ ] Console redraws correctly after single Ctrl+C warning

If all pass, this task can be closed as "Already Works".

---

## Acceptance Criteria (if implementation needed)

- [ ] Ctrl+C once never exits in History Mode
- [ ] Double-press within 1s exits cleanly
- [ ] Stable redraw (no console growth)
- [ ] Warning message displays correctly in History view

---

## Constraints

- **Reuse existing handler** - do not invent a second mechanism
- **No new globals** - use existing `$Global:LastCtrlCUtc`, `$Global:CtrlCWarningShownUtc`
- **No enforcement changes** - UX only

---

## Implementation Notes (only if needed)

If History Mode has its own ReadKey loop that bypasses `Read-StableInput`, add the same inline check:

```powershell
# In History Mode ReadKey loop (if separate)
if ($key.VirtualKeyCode -eq 3 -or ...) {
    $now = [DateTime]::UtcNow
    if ($Global:LastCtrlCUtc -and ($now - $Global:LastCtrlCUtc).TotalSeconds -le 1.0) {
        Write-Host "`nExiting..." -ForegroundColor DarkGray
        exit 130
    }
    $Global:LastCtrlCUtc = $now
    # Show subtle warning
    continue
}
```

---

## Risk Assessment

**Risk:** LOW
- Isolated to input handling
- No enforcement gate changes
- Pattern already proven in main loop

---

**Freeze Rule:** This task must NOT modify:
- `submit_review_decision` gates
- Risk gate semantics
- Router READONLY ordering
