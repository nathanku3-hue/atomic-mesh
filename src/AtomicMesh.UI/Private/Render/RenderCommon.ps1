function Clear-Row {
    param(
        [int]$Row,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    $len = if ($Width -gt 0) { $Width } else { 1 }
    TryWriteAt -Row $Row -Col 0 -Text (" " * $len) | Out-Null
}

function Render-TitleRow {
    param(
        [int]$Row,
        [string]$Title,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    $text = (" " + $Title + " ").PadRight($Width)
    $text = $text.Substring(0, [Math]::Min($text.Length, $Width))
    TryWriteAt -Row $Row -Col 0 -Text $text -Color "Cyan" | Out-Null
}

function Render-ToastLine {
    param(
        [UiToast]$Toast,
        [int]$Row,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    Clear-Row -Row $Row -Width $Width
    if ($Toast -and $Toast.Message) {
        $text = $Toast.Message
        if ($text.Length -gt ($Width - 4)) {
            $text = $text.Substring(0, $Width - 4)
        }
        TryWriteAt -Row $Row -Col 0 -Text $text -Color "Yellow" | Out-Null
    }
}

function Render-InputLine {
    param(
        [string]$Buffer,
        [int]$Row,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    $prompt = "> "
    $text = $prompt + $Buffer
    if ($text.Length -gt $Width) {
        $text = $text.Substring($text.Length - $Width, $Width)
    }
    Clear-Row -Row $Row -Width $Width
    TryWriteAt -Row $Row -Col 0 -Text $text -Color "White" | Out-Null
}

function Render-HintBar {
    param(
        [int]$Row,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    $hint = "Tab cycle  F2 history  F4 details  F5 pause  F6 stats  ESC close  /quit"
    if ($hint.Length -gt $Width) {
        $hint = $hint.Substring(0, $Width)
    }
    Clear-Row -Row $Row -Width $Width
    TryWriteAt -Row $Row -Col 0 -Text $hint -Color "DarkGray" | Out-Null
}
