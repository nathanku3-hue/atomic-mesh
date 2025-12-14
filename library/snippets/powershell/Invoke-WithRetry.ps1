# SNIPPET: Invoke-WithRetry
# LANG: powershell
# TAGS: retry, resilience, http
# INTENT: Retry wrapper for unreliable operations with exponential backoff
# UPDATED: 2025-12-12

function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Retry a script block with exponential backoff.

    .PARAMETER ScriptBlock
    The code to execute

    .PARAMETER MaxRetries
    Maximum number of attempts (default: 3)

    .PARAMETER BaseDelay
    Initial delay in seconds (default: 1)

    .EXAMPLE
    Invoke-WithRetry { Get-Content "remote-file.txt" } -MaxRetries 5
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,

        [int]$MaxRetries = 3,
        [double]$BaseDelay = 1.0
    )

    for ($attempt = 0; $attempt -lt $MaxRetries; $attempt++) {
        try {
            return & $ScriptBlock
        } catch {
            if ($attempt -eq ($MaxRetries - 1)) {
                throw
            }
            $delay = $BaseDelay * [Math]::Pow(2, $attempt) + (Get-Random -Minimum 0 -Maximum 1000) / 1000.0
            Start-Sleep -Seconds $delay
        }
    }
}
