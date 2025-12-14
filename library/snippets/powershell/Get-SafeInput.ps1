# SNIPPET: Get-SafeInput
# LANG: powershell
# TAGS: input, validation, user-prompt
# INTENT: Get user input with validation and default fallback
# UPDATED: 2025-12-12

function Get-SafeInput {
    <#
    .SYNOPSIS
    Prompt user for input with validation and default value.

    .PARAMETER Prompt
    Message to display to user

    .PARAMETER Default
    Default value if user presses Enter

    .PARAMETER ValidatePattern
    Regex pattern for validation (optional)

    .EXAMPLE
    $port = Get-SafeInput -Prompt "Enter port" -Default "8080" -ValidatePattern '^\d+$'
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [string]$Default = "",
        [string]$ValidatePattern = ""
    )

    do {
        $value = Read-Host "$Prompt $(if ($Default) { "[default: $Default]" })"

        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }

        if ($ValidatePattern -and $value -notmatch $ValidatePattern) {
            Write-Warning "Invalid input. Must match pattern: $ValidatePattern"
            $value = $null
        }
    } while ($null -eq $value)

    return $value
}
