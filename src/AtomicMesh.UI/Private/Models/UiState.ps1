class UiState {
    [string]$CurrentPage
    [string]$OverlayMode
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
        $this.CurrentPage = "PLAN"
        $this.OverlayMode = "None"
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
}
