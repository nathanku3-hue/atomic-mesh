class UiState {
    [string]$CurrentPage      # BOOTSTRAP | PLAN | GO
    [string]$CurrentMode      # OPS | PLAN | RUN | SHIP (Golden mode ring)
    [string]$OverlayMode      # None | History (F2 toggle)
    [string]$HistorySubview   # TASKS | DOCS | SHIP (Tab cycles in History)
    [int]$HistorySelectedRow
    [int]$HistoryScrollOffset
    [bool]$HistoryDetailsVisible

    [UiToast]$Toast
    [UiEventLog]$EventLog
    [UiCache]$Cache
    [datetime]$NowUtc
    [int]$RenderFrames
    [int]$SkippedFrames
    [int]$DataRefreshes
    [string]$InputBuffer
    [datetime]$LastDataRefreshUtc

    # Dirty-driven rendering fields
    [bool]$IsDirty
    [string]$DirtyReason
    [string]$LastSnapshotHash
    [int]$LastWidth
    [int]$LastHeight
    [bool]$AutoRefreshEnabled
    [string]$LastInputBuffer
    [string]$LastAdapterError

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

        # Dirty-driven rendering init
        $this.IsDirty = $true
        $this.DirtyReason = "init"
        $this.LastSnapshotHash = ""
        $this.LastWidth = 0
        $this.LastHeight = 0
        $this.AutoRefreshEnabled = $true
        $this.LastInputBuffer = ""
        $this.LastAdapterError = ""
    }

    [void] MarkDirty([string]$reason) {
        $this.IsDirty = $true
        $this.DirtyReason = $reason
    }

    [void] ClearDirty() {
        $this.IsDirty = $false
        $this.DirtyReason = ""
    }

    # Golden Contract: Toggle overlay on/off
    [void] ToggleOverlay([string]$mode) {
        if ($this.OverlayMode -eq $mode) {
            $this.OverlayMode = "None"
        } else {
            $this.OverlayMode = $mode
        }
        $this.MarkDirty("overlay")
    }

    # Golden Contract: Cycle mode ring (OPS -> PLAN -> RUN -> SHIP -> OPS)
    [void] CycleMode() {
        $ring = @("OPS", "PLAN", "RUN", "SHIP")
        $idx = [Array]::IndexOf($ring, $this.CurrentMode)
        $this.CurrentMode = $ring[($idx + 1) % $ring.Length]
        $this.MarkDirty("mode")
    }

    # Golden Contract: Cycle history subview (TASKS -> DOCS -> SHIP -> TASKS)
    [void] CycleHistorySubview() {
        $tabs = @("TASKS", "DOCS", "SHIP")
        $idx = [Array]::IndexOf($tabs, $this.HistorySubview)
        $this.HistorySubview = $tabs[($idx + 1) % $tabs.Length]
        $this.MarkDirty("historyTab")
    }

    # Golden Contract: Set page (BOOTSTRAP | PLAN | GO)
    [void] SetPage([string]$page) {
        if ($this.CurrentPage -ne $page) {
            $this.CurrentPage = $page
            $this.MarkDirty("page")
        }
    }

    # Golden Contract: Toggle history details pane (Enter key in History overlay)
    [void] ToggleHistoryDetails() {
        $this.HistoryDetailsVisible = -not $this.HistoryDetailsVisible
        $this.MarkDirty("historyDetails")
    }

    # Golden Contract: Close history details pane (ESC priority)
    [void] CloseHistoryDetails() {
        if ($this.HistoryDetailsVisible) {
            $this.HistoryDetailsVisible = $false
            $this.MarkDirty("historyDetails")
        }
    }
}
