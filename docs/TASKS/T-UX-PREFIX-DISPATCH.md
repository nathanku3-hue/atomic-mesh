# T-UX-PREFIX-DISPATCH: Unique Prefix Auto-Run

**Priority:** P2
**Type:** UX Enhancement
**Status:** IMPLEMENTED
**Created:** 2025-12-14
**Completed:** 2025-12-14
**Milestone:** Post v16.1.0

---

## Summary

Implement unique prefix auto-execution for slash commands. When user types a prefix that uniquely matches one command, it should run immediately without opening the picker.

---

## Current Behavior

| Input | Result |
|-------|--------|
| `/init` + Enter | Exact match → runs immediately ✅ |
| `/in` + Enter | Opens picker (even if unique match) |
| `/i` + Enter | Opens picker |

## Target Behavior

| Input | Result |
|-------|--------|
| `/init` + Enter | Exact match → runs immediately ✅ |
| `/in` + Enter | Unique prefix → runs `/init` immediately |
| `/i` + Enter | Multiple matches → opens picker |

---

## Acceptance Criteria

- [ ] Exact match runs immediately (unchanged, already works)
- [ ] Unique prefix runs without picker
- [ ] Multiple matches opens picker (unchanged)
- [ ] Deterministic matching rules documented in code
- [ ] No console growth or redraw issues

---

## Constraints

- **No new commands** - this is picker behavior only
- **No picker redesign** - minimal change to existing flow
- **Deterministic** - same input always produces same result
- **No enforcement changes** - UX only, does not touch gates

---

## Implementation Notes

Location: `control_panel.ps1` in `Show-CommandPicker` function (~line 7864)

Current logic:
```powershell
# Check for exact match first
$exactMatch = $filteredCmds | Where-Object { $_.Name -eq $script:pickerFilter }
if ($exactMatch) {
    return @{ Kind = "select"; Command = "/" + $exactMatch.Name }
}
# Otherwise use highlighted selection
```

Suggested addition (after exact match check):
```powershell
# Check for unique prefix match
if ($filteredCmds.Count -eq 1) {
    return @{ Kind = "select"; Command = "/" + $filteredCmds[0].Name }
}
# Multiple matches → show picker (existing behavior)
```

---

## Testing

1. `/init` + Enter → runs init (exact match)
2. `/in` + Enter → runs init (unique prefix, assuming no `/inbox` command)
3. `/s` + Enter → opens picker (multiple: `/status`, `/ship`, `/snapshots`, etc.)
4. Console frame stable after all operations

---

## Risk Assessment

**Risk:** LOW
- Isolated to picker logic
- No enforcement gate changes
- Easy to revert

---

**Freeze Rule:** This task must NOT modify:
- `submit_review_decision` gates
- Risk gate semantics
- Router READONLY ordering
