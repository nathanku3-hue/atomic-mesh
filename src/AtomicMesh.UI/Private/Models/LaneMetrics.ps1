class LaneMetrics {
    [string]$Name
    [int]$Queued
    [int]$Active
    [int]$Tokens
    [string]$State
    [string]$Bar
    [string]$DotColor
    [string]$Reason

    LaneMetrics() {
        $this.Name = ""
        $this.Queued = 0
        $this.Active = 0
        $this.Tokens = 0
        $this.State = "PENDING"
        $this.Bar = "-----"
        $this.DotColor = "DarkGray"
        $this.Reason = ""
    }

    static [LaneMetrics] CreateDefault([string]$name) {
        $lane = [LaneMetrics]::new()
        $lane.Name = $name
        return $lane
    }
}
