class UiCache {
    [UiSnapshot]$LastSnapshot
    [hashtable]$Metadata
    [string]$LastRawSignature

    UiCache() {
        $this.LastSnapshot = $null
        $this.Metadata = @{}
        $this.LastRawSignature = ""
    }
}
