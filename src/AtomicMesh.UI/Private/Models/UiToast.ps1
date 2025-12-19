class UiToast {
    [string]$Message
    [string]$Level
    [datetime]$ExpiresUtc

    UiToast() {
        $this.Message = ""
        $this.Level = ""
        $this.ExpiresUtc = [datetime]::MinValue
    }

    [void]Set([string]$message, [string]$level, [int]$ttlSeconds) {
        $this.Message = $message
        $this.Level = if ($level) { $level } else { "info" }
        $ttl = if ($ttlSeconds -gt 0) { $ttlSeconds } else { 0 }
        $this.ExpiresUtc = [datetime]::UtcNow.AddSeconds($ttl)
    }

    [bool]ClearIfExpired([datetime]$nowUtc) {
        $referenceTime = if ($nowUtc) { $nowUtc } else { [datetime]::UtcNow }
        if ($this.Message -and $this.ExpiresUtc -ne [datetime]::MinValue -and $referenceTime -ge $this.ExpiresUtc) {
            $this.Message = ""
            $this.Level = ""
            $this.ExpiresUtc = [datetime]::MinValue
            return $true
        }
        return $false
    }
}
