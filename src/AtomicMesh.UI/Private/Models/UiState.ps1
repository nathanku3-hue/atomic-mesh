using namespace System.Collections.Generic

class UiState {
    [string]$CurrentPage      # BOOTSTRAP | PLAN | GO
    [string]$CurrentMode      # OPS | PLAN | RUN | SHIP (Golden mode ring)
    [string]$OverlayMode      # None | History (F2 toggle)
    [string]$HistorySubview   # TASKS | DOCS | SHIP (Tab cycles in History)
    [int]$HistorySelectedRow
    [int]$HistoryScrollOffset
    [bool]$HistoryDetailsVisible

    # NOTE: Using [object] to avoid type mismatch on module reload
    # PowerShell classes are scope-bound; reload creates "new" types
    [object]$Toast       # UiToast
    [object]$EventLog    # UiEventLog
    [object]$Cache       # UiCache
    [datetime]$NowUtc
    [int]$RenderFrames
    [int]$SkippedFrames
    [int]$DataRefreshes
    [string]$InputBuffer
    [datetime]$LastDataRefreshUtc

    # Region-based dirty rendering
    # Regions: "all", "content", "picker", "input", "toast", "footer"
    [HashSet[string]]$DirtyRegions
    [string]$LastSnapshotHash
    [int]$LastWidth
    [int]$LastHeight
    [bool]$AutoRefreshEnabled
    [string]$LastInputBuffer
    [string]$LastAdapterError
    [int]$LastPickerHeight    # For picker area clearing

    UiState() {
        # Golden state defaults
        $this.CurrentPage = "PLAN"
        $this.CurrentMode = "OPS"              # Golden default mode
        $this.OverlayMode = "None"
        $this.HistorySubview = "TASKS"         # Default history tab
        $this.HistorySelectedRow = 0
        $this.HistoryScrollOffset = 0
        $this.HistoryDetailsVisible = $false

        $this.Toast = [UiToast]::new()
        $this.EventLog = [UiEventLog]::new()
        $this.Cache = [UiCache]::new()
        $this.NowUtc = [datetime]::UtcNow
        $this.RenderFrames = 0
        $this.SkippedFrames = 0
        $this.DataRefreshes = 0
        $this.InputBuffer = ""
        $this.LastDataRefreshUtc = [datetime]::MinValue

        # Region-based dirty init
        $this.DirtyRegions = [HashSet[string]]::new()
        $this.DirtyRegions.Add("all") | Out-Null  # Initial full render
        $this.LastSnapshotHash = ""
        $this.LastWidth = 0
        $this.LastHeight = 0
        $this.AutoRefreshEnabled = $true
        $this.LastInputBuffer = ""
        $this.LastAdapterError = ""
        $this.LastPickerHeight = 0
    }

    # Mark a specific region dirty (default: "all" for full render)
    [void] MarkDirty([string]$region) {
        if ([string]::IsNullOrWhiteSpace($region)) { $region = "all" }
        $this.DirtyRegions.Add($region) | Out-Null
    }

    # Check if a region is dirty (returns true if "all" is dirty)
    [bool] IsDirty([string]$region) {
        if ($this.DirtyRegions.Contains("all")) { return $true }
        return $this.DirtyRegions.Contains($region)
    }

    # Check if any region is dirty
    [bool] HasDirty() {
        return $this.DirtyRegions.Count -gt 0
    }

    # Clear all dirty flags
    [void] ClearDirty() {
        $this.DirtyRegions.Clear()
    }

    # Golden Contract: Toggle overlay on/off
    [void] ToggleOverlay([string]$mode) {
        if ($this.OverlayMode -eq $mode) {
            $this.OverlayMode = "None"
        } else {
            $this.OverlayMode = $mode
        }
        $this.MarkDirty("content")  # Overlay changes require content redraw
    }

    # Golden Contract: Cycle mode ring (OPS -> PLAN -> RUN -> SHIP -> OPS)
    [void] CycleMode() {
        $ring = @("OPS", "PLAN", "RUN", "SHIP")
        $idx = [Array]::IndexOf($ring, $this.CurrentMode)
        $this.CurrentMode = $ring[($idx + 1) % $ring.Length]
        $this.MarkDirty("content")  # Mode affects pipeline colors
    }

    # Golden Contract: Cycle history subview (TASKS -> DOCS -> SHIP -> TASKS)
    [void] CycleHistorySubview() {
        $tabs = @("TASKS", "DOCS", "SHIP")
        $idx = [Array]::IndexOf($tabs, $this.HistorySubview)
        $this.HistorySubview = $tabs[($idx + 1) % $tabs.Length]
        $this.MarkDirty("content")  # Tab change = content change
    }

    # Golden Contract: Set page (BOOTSTRAP | PLAN | GO)
    [void] SetPage([string]$page) {
        if ($this.CurrentPage -ne $page) {
            $this.CurrentPage = $page
            $this.MarkDirty("content")  # Page switch = full content
        }
    }

    # Golden Contract: Toggle history details pane (Enter key in History overlay)
    [void] ToggleHistoryDetails() {
        $this.HistoryDetailsVisible = -not $this.HistoryDetailsVisible
        $this.MarkDirty("content")
    }

    # Golden Contract: Close history details pane (ESC priority)
    [void] CloseHistoryDetails() {
        if ($this.HistoryDetailsVisible) {
            $this.HistoryDetailsVisible = $false
            $this.MarkDirty("content")
        }
    }
}
