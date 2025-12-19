# NOTE: Using [object] instead of [UiSnapshot] to avoid type mismatch on module reload
# PowerShell classes are scope-bound; reloading creates a "new" UiSnapshot type
class UiCache {
    [object]$LastSnapshot
    [hashtable]$Metadata
    [string]$LastRawSignature

    UiCache() {
        $this.LastSnapshot = $null
        $this.Metadata = @{}
        $this.LastRawSignature = ""
    }
}
