# Plan: Unified CLI/TUI (v13.1)

**Status:** IMPLEMENTED
**Date:** 2025-12-09

---

## Goal

Unify Control Panel and Dashboard into a **single CLI/TUI** with health-based view switching:
- **Healthy** → Compact status header + primary workflow (command prompt)
- **Unhealthy** → Full dashboard view + suggested next actions

---

## Current State

| Component | Lines | Purpose |
|-----------|-------|---------|
| `control_panel.ps1` | ~4600 | Command interpreter, embedded TUI dashboard, main loop |
| `dashboard.ps1` | ~370 | Standalone auto-refresh TUI, separate window |
| `start_mesh.ps1` | 143 | Launches both as separate windows |

**Problem:** Two separate surfaces rendering duplicate state. User must context-switch between windows.

---

## Proposed Architecture

### Single Entry Point: `control_panel.ps1`

```
┌─────────────────────────────────────────────────────────┐
│                  UNIFIED TUI/CLI                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [HEALTH-BASED VIEW SWITCHING]                         │
│                                                         │
│  IF system healthy:                                     │
│    ┌─────────────────────────────────────────────────┐ │
│    │ 🟢 MESH OK | 3 pending | 0 reviewing | /ops    │ │  ← Compact Status Bar
│    │                                                 │ │
│    │ >                                              │ │  ← Command Prompt
│    └─────────────────────────────────────────────────┘ │
│                                                         │
│  IF system unhealthy (or /dash requested):             │
│    ┌─────────────────────────────────────────────────┐ │
│    │ Full Dashboard (existing Draw-Dashboard)        │ │  ← Current TUI
│    │   - EXEC column                                 │ │
│    │   - COGNITIVE column                            │ │
│    │   - Recommendations                             │ │
│    │   - Live audit log                              │ │
│    │                                                 │ │
│    │ [Press ESC to return to compact view]           │ │
│    └─────────────────────────────────────────────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Minimal Changes Required

### 1. Add Health-Check Function (10 lines)

```powershell
function Get-SystemHealthStatus {
    # Returns: @{ IsHealthy = $true/$false; Summary = "text" }
    # Calls existing get_health_report() and get_drift_report()
    # Returns unhealthy if either has FAIL status
}
```

### 2. Add Compact Status Bar (15 lines)

```powershell
function Draw-CompactStatusBar {
    # Single line: [HEALTH] | stats | hint
    # Example: "🟢 OK | 3 pending | 0 reviewing | /ops for details"
}
```

### 3. Add View Mode Toggle (5 lines)

```powershell
$Global:ViewMode = "auto"  # auto | compact | dashboard

# In main loop:
if ($ViewMode -eq "auto") {
    $health = Get-SystemHealthStatus
    if ($health.IsHealthy) { Draw-CompactStatusBar }
    else { Draw-Dashboard }
}
```

### 4. Add `/dash` Command (3 lines)

```powershell
"dash" = @{ Desc = "Toggle full dashboard view" }
# In switch: Toggle $Global:ViewMode
```

### 5. Update `start_mesh.ps1` (Remove dashboard launch)

**Current:**
```powershell
# Phase 3: Launch Dashboard
Start-Process dashboard.ps1 ...
```

**Proposed:**
```powershell
# Phase 3: Dashboard now integrated into Control Panel
Write-Host "  ✅ Dashboard integrated into Control Panel" -ForegroundColor Green
```

---

## Files to Modify

| File | Change | Scope |
|------|--------|-------|
| `control_panel.ps1` | Add `Get-SystemHealthStatus`, `Draw-CompactStatusBar`, view mode logic | ~30 lines |
| `start_mesh.ps1` | Remove Phase 3 dashboard launch | -10 lines |
| `docs/ARCHITECTURE.md` | Update component diagram | Documentation |
| `docs/CHANGELOG.md` | Add v13.1 entry | Documentation |

**Total code change:** ~30 lines added, ~10 removed

---

## What Stays the Same

1. **All 50+ slash commands** - No changes
2. **Existing Draw-Dashboard function** - Preserved as full dashboard view
3. **Command picker/dropdown** - No changes
4. **Input handling** - No changes
5. **Python integration** - No changes
6. **dashboard.ps1** - Kept for standalone use (optional)

---

## Health-Based Switching Logic

```
                    ┌──────────────┐
                    │   Startup    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ Check Health │
                    │   & Drift    │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
       ┌──────▼──────┐          ┌───────▼───────┐
       │   HEALTHY   │          │   UNHEALTHY   │
       │ (OK status) │          │ (FAIL/WARN)   │
       └──────┬──────┘          └───────┬───────┘
              │                         │
       ┌──────▼──────┐          ┌───────▼───────┐
       │  Compact    │          │    Full       │
       │ Status Bar  │          │  Dashboard    │
       │ + Prompt    │          │ + Actions     │
       └─────────────┘          └───────────────┘
```

**Unhealthy triggers:**
- Health Sentinel returns FAIL
- Drift Sentinel returns FAIL
- Review queue > 5 tasks (configurable)
- Any blocked tasks

---

## User Override Commands

| Command | Action |
|---------|--------|
| `/dash` | Toggle to full dashboard view |
| `/compact` | Toggle to compact view |
| `ESC` (in dashboard) | Return to compact view |
| `/ops` | Existing operator dashboard (unchanged) |

---

## Implementation Order

1. **Add compact status bar** - Can test immediately
2. **Add health check** - Integrate existing sentinel calls
3. **Add view mode logic** - Wire into main loop
4. **Update start_mesh.ps1** - Remove dashboard launch
5. **Documentation** - Update ARCHITECTURE.md

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Main loop complexity | View mode is single variable check |
| Terminal resize issues | Use existing responsive sizing logic |
| Health check latency | Cache for 5 seconds, async-friendly |
| User confusion | Clear status bar indicates mode |

---

## Approval Checklist

- [ ] Compact status bar design approved
- [ ] Health-check thresholds approved (FAIL = unhealthy)
- [ ] Override commands (`/dash`, `/compact`) approved
- [ ] Start mesh changes approved (remove dashboard launch)

---

## Questions for Approval

1. **Should warning (WARN) status trigger full dashboard?**
   - Current plan: Only FAIL triggers dashboard
   - Alternative: WARN also triggers dashboard

2. **Should the standalone `dashboard.ps1` be removed?**
   - Current plan: Keep for optional standalone use
   - Alternative: Remove entirely

3. **Refresh rate for health check in compact mode?**
   - Current plan: Check every 5 seconds (matches dashboard)
   - Alternative: On-demand only

---

*Plan v13.1 - Unified TUI - Ready for Approval*
