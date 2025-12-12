# Plan: Minimal TUI Fix (v13.1.1)

**Status:** AWAITING APPROVAL
**Date:** 2025-12-10

---

## Problem

The v13.1.0 implementation accidentally replaced the original TUI layout instead of adding to it:
- `Initialize-Screen` now conditionally calls `Draw-Dashboard` or `Draw-CompactStatusBar`
- Should have kept original layout and added compact bar at the top

---

## Goal

Restore original layout + add health integration in a **strictly additive** way:
- Original panes, spacing, headers, rendering order preserved
- Single-line compact status added at TOP of existing layout
- ~30 lines of changes only

---

## Approach: Additive Only

### Original Initialize-Screen (RESTORE THIS)
```powershell
function Initialize-Screen {
    $W = $Host.UI.RawUI.WindowSize.Width
    $H = $Host.UI.RawUI.WindowSize.Height
    if ($H -lt 25) {
        try { $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($W, 30) } catch {}
    }

    Clear-Host
    Set-Pos $Global:RowHeader 0
    Show-Header
    Draw-Dashboard      # ← ALWAYS called, never replaced
}
```

### New Initialize-Screen (ADDITIVE)
```powershell
function Initialize-Screen {
    $W = $Host.UI.RawUI.WindowSize.Width
    $H = $Host.UI.RawUI.WindowSize.Height
    if ($H -lt 25) {
        try { $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($W, 30) } catch {}
    }

    Clear-Host

    # v13.1: Single-line health status (additive, at row 0)
    $health = Get-SystemHealthStatus
    Write-CompactHealthLine -Health $health

    # Original layout unchanged
    Set-Pos $Global:RowHeader 0
    Show-Header
    Draw-Dashboard      # ← ALWAYS called
}
```

---

## Minimal Changes (~30 lines)

### 1. Keep Global Variables (6 lines)
Already added, keep them:
```powershell
$Global:ViewMode = "auto"
$Global:WarnCount = 0
$Global:LastHealthCheck = $null
$Global:LastViewSwitch = $null
$Global:ManualOverrideUntil = $null
```

### 2. Simplify Get-SystemHealthStatus (15 lines)
Remove complex logic, just wrap sentinels:
```powershell
function Get-SystemHealthStatus {
    $result = @{ Status = "OK"; Summary = "" }
    try {
        $health = python -c "from mesh_server import get_health_report; print(get_health_report())" 2>&1
        $drift = python -c "from mesh_server import get_drift_report; print(get_drift_report())" 2>&1

        if ($health -match "FAIL" -or $drift -match "FAIL") {
            $result.Status = "FAIL"
        } elseif ($health -match "WARN" -or $drift -match "WARN") {
            $result.Status = "WARN"
            $Global:WarnCount++
        } else {
            $Global:WarnCount = 0
        }
    } catch { $result.Status = "WARN" }
    return $result
}
```

### 3. Add Write-CompactHealthLine (8 lines)
Single line, not boxed:
```powershell
function Write-CompactHealthLine {
    param([hashtable]$Health)
    $icon = switch ($Health.Status) { "OK" { "🟢" } "WARN" { "🟡" } "FAIL" { "🔴" } }
    $color = switch ($Health.Status) { "OK" { "Green" } "WARN" { "Yellow" } "FAIL" { "Red" } }
    Write-Host "$icon $($Health.Status) | /ops for details" -ForegroundColor $color
}
```

### 4. Modify Initialize-Screen (2 lines added)
```diff
function Initialize-Screen {
    ...
    Clear-Host
+   $health = Get-SystemHealthStatus
+   Write-CompactHealthLine -Health $health
    Set-Pos $Global:RowHeader 0
    Show-Header
    Draw-Dashboard
}
```

### 5. Keep /dash and /compact Commands (already added)
These just set `$Global:ViewMode` - no layout changes needed.

---

## What Gets Removed

1. **Draw-CompactStatusBar** - Replace with simpler `Write-CompactHealthLine`
2. **Get-EffectiveViewMode** - Not needed (always show dashboard)
3. **Set-ViewModeOverride** - Simplify to direct variable set
4. **View mode conditional in Initialize-Screen** - Remove, always draw dashboard

---

## Diff Summary

```
control_panel.ps1:
  - REMOVE: Draw-CompactStatusBar (~70 lines)
  - REMOVE: Get-EffectiveViewMode (~30 lines)
  - REMOVE: Set-ViewModeOverride (~10 lines)
  - REMOVE: View switching in Initialize-Screen (~15 lines)
  - ADD: Write-CompactHealthLine (8 lines)
  - MODIFY: Initialize-Screen (+2 lines)
  - KEEP: Get-SystemHealthStatus (simplify to 15 lines)
  - KEEP: Global variables (6 lines)
  - KEEP: /dash, /compact commands (already added)

Net change: ~30 lines added, ~120 lines removed
```

---

## View Behavior After Fix

| Status | Display |
|--------|---------|
| OK | `🟢 OK \| /ops` + original full dashboard |
| WARN | `🟡 WARN \| /ops` + original full dashboard |
| WARN (3+) | Same (escalation is informational only) |
| FAIL | `🔴 FAIL \| /ops` + original full dashboard |
| `/dash` | No change (dashboard always shown) |
| `/compact` | No change (dashboard always shown) |

The `/dash` and `/compact` commands become no-ops in this minimal version, but are kept for future use.

---

## Files Changed

| File | Change |
|------|--------|
| `control_panel.ps1` | Restore Initialize-Screen, simplify health functions |
| `dashboard.ps1` | Keep as shim (no change) |
| `start_mesh.ps1` | No change needed |

---

## Approval Checklist

- [ ] Restore original Initialize-Screen (always calls Draw-Dashboard)
- [ ] Single-line health status at top (not boxed)
- [ ] Keep original panes/spacing/headers
- [ ] ~30 lines net change
- [ ] /dash and /compact become no-ops (for now)

---

*Plan v13.1.1 - Minimal TUI Fix - Ready for Approval*
