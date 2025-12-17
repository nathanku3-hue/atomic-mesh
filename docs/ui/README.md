# UI Golden Snapshots

This directory contains canonical UI screenshots for regression testing.

## Files

- `exec-dashboard-final.png` - EXEC mode dashboard (v19.8 final)

## Required State

Capture screenshot with:
- **Header**: `|  EXEC ● | 0 pending | 0 active ... path  |` (2-space padding both sides)
- **Lanes**: BACKEND/FRONTEND IDLE, QA/AUDIT OK, LIBRARIAN OK
- **Right panel**:
  - Context Ready
  - Security: Read-Only Mode for Data
  - PIPELINE
  - `[Ctx] → [Pln] → [Wrk] → [Opt] → [Ver] → [Shp]`
  - Next: /draft-plan
  - Critical: (PLN) No tasks exist yet
- **Footer**: `ask 'health', 'drift', or type /ops [OPS]` flush to right edge

## v19.8 Fixes Applied

1. No trailing `+` at right edge (bottom border uses `-`)
2. No trailing `|` pip artifact (footer clears row above + footer row)
3. Header path has 2-space padding before right border
4. Footer content extends to last column (no gap)

## Capturing

```powershell
.\control_panel.ps1
# Wait for EXEC mode to render, then capture
```

Save as `exec-dashboard-final.png` in this directory.
