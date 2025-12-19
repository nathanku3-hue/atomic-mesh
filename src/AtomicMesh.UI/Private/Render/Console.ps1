$script:FrameState = @{ Skip = $false }

# Capture mode for golden-master testing
$script:CaptureMode = $false
$script:CaptureBuffer = $null
$script:CaptureWidth = 80
$script:CaptureHeight = 24
$script:CaptureCursorRow = 0
$script:CaptureCursorCol = 0

function Enable-CaptureMode {
    param(
        [int]$Width = 80,
        [int]$Height = 24
    )

    $script:CaptureMode = $true
    $script:CaptureWidth = $Width
    $script:CaptureHeight = $Height
    $script:CaptureCursorRow = 0
    $script:CaptureCursorCol = 0

    # Initialize buffer with spaces
    $script:CaptureBuffer = @()
    for ($r = 0; $r -lt $Height; $r++) {
        $script:CaptureBuffer += ,([char[]](" " * $Width))
    }
}

function Disable-CaptureMode {
    $script:CaptureMode = $false
}

function Get-CapturedOutput {
    if (-not $script:CaptureBuffer) { return "" }

    $lines = @()
    foreach ($row in $script:CaptureBuffer) {
        $lines += (-join $row)
    }
    return ($lines -join "`n")
}

function Begin-ConsoleFrame {
    $script:FrameState = @{ Skip = $false }
}

function End-ConsoleFrame {
    return -not $script:FrameState.Skip
}

function Get-ConsoleFrameValid {
    return -not $script:FrameState.Skip
}

function TrySetPos {
    param(
        [int]$Row,
        [int]$Col
    )

    $targetRow = if ($Row -lt 0) { 0 } else { $Row }
    $targetCol = if ($Col -lt 0) { 0 } else { $Col }

    if ($script:CaptureMode) {
        $script:CaptureCursorRow = [Math]::Min($targetRow, $script:CaptureHeight - 1)
        $script:CaptureCursorCol = [Math]::Min($targetCol, $script:CaptureWidth - 1)
        return $true
    }

    try {
        [Console]::SetCursorPosition($targetCol, $targetRow)
        return $true
    }
    catch {
        $script:FrameState.Skip = $true
        return $false
    }
}

function TryWriteAt {
    param(
        [int]$Row,
        [int]$Col,
        [string]$Text,
        [string]$Color
    )

    if (-not (TrySetPos -Row $Row -Col $Col)) {
        return $false
    }

    if ($script:CaptureMode) {
        # Write to capture buffer (ignore color in capture mode)
        if ($Text) {
            foreach ($char in $Text.ToCharArray()) {
                if ($script:CaptureCursorRow -lt $script:CaptureHeight -and $script:CaptureCursorCol -lt $script:CaptureWidth) {
                    $script:CaptureBuffer[$script:CaptureCursorRow][$script:CaptureCursorCol] = $char
                    $script:CaptureCursorCol++
                }
            }
        }
        return $true
    }

    try {
        if ($PSBoundParameters.ContainsKey('Color') -and $Color) {
            Write-Host $Text -NoNewline -ForegroundColor $Color
        }
        else {
            Write-Host $Text -NoNewline
        }
        return $true
    }
    catch {
        $script:FrameState.Skip = $true
        return $false
    }
}
