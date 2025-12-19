class PlanState {
    [string]$Status
    [bool]$HasDraft
    [bool]$Accepted
    [string]$PlanId
    [string]$Summary
    [string]$NextHint

    PlanState() {
        $this.Status = "UNKNOWN"
        $this.HasDraft = $false
        $this.Accepted = $false
        $this.PlanId = ""
        $this.Summary = ""
        $this.NextHint = ""
    }
}
