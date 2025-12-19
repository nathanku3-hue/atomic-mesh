function Render-StreamDetailsOverlay {
    param(
        [UiState]$State
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $window = $Host.UI.RawUI.WindowSize
    $width = if ($window.Width -gt 0) { $window.Width } else { 80 }

    $row = 2
    $title = "Stream details (F4)"
    if ($title.Length -gt $width) { $title = $title.Substring(0, $width) }
    TryWriteAt -Row $row -Col 0 -Text $title -Color "DarkGray" | Out-Null
    $row++

    $message = "Stream details overlay not implemented yet."
    if ($message.Length -gt $width) {
        $message = $message.Substring(0, $width)
    }
    TryWriteAt -Row $row -Col 0 -Text $message -Color "Yellow" | Out-Null
}
