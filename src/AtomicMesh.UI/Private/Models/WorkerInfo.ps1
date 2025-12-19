class WorkerInfo {
    [string]$Id
    [string]$Status
    [datetime]$LastSeenUtc

    WorkerInfo() {
        $this.Id = ""
        $this.Status = "unknown"
        $this.LastSeenUtc = [datetime]::UtcNow
    }
}
