class LaneMetrics {
    [string]$Name
    [int]$Queued
    [int]$Active
    [int]$Tokens
    [string]$State
    [string]$Bar
    [string]$DotColor
    [string]$StateColor   # Primary color for this lane's state (used by renderers)
    [string]$DotChar      # Symbol used for legend/stream dots
    [string]$Reason

    LaneMetrics() {
        $this.Name = ""
        $this.Queued = 0
        $this.Active = 0
        $this.Tokens = 0
        $this.State = "IDLE"
        $this.Bar = ([char]0x25A1).ToString() * 5  # □□□□□
        $this.DotColor = "DarkGray"
        $this.StateColor = "DarkGray"
        $this.DotChar = [char]0x25CF  # ●
        $this.Reason = ""
    }

    static [LaneMetrics] CreateDefault([string]$name) {
        $lane = [LaneMetrics]::new()
        $lane.Name = $name
        return $lane
    }
}
