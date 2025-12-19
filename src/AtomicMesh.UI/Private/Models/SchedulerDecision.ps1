class SchedulerDecision {
    [string]$NextAction
    [string]$Reason

    SchedulerDecision() {
        $this.NextAction = ""
        $this.Reason = ""
    }
}
