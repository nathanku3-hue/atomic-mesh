class UiAlerts {
    [string[]]$Messages
    [string]$AdapterError    # Golden: backend connection error

    UiAlerts() {
        $this.Messages = @()
        $this.AdapterError = ""
    }
}
