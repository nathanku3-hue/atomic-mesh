class UiEvent {
    [datetime]$TimestampUtc
    [string]$Message
    [string]$Level

    UiEvent() {
        $this.TimestampUtc = [datetime]::UtcNow
        $this.Message = ""
        $this.Level = "info"
    }

    UiEvent([string]$message, [string]$level) {
        $this.TimestampUtc = [datetime]::UtcNow
        $this.Message = $message
        $this.Level = if ($level) { $level } else { "info" }
    }
}
