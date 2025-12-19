function Render-HistoryOverlay {
    param(
        [UiState]$State,
        [int]$StartRow = 0
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $state = if ($State) { $State } else { [UiState]::new() }
    $subview = if ($state.HistorySubview) { $state.HistorySubview } else { "TASKS" }
    $detailsVisible = $state.HistoryDetailsVisible

    # Get dimensions
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $Half = [Math]::Floor($W / 2)
    $ContentWidthL = $Half - 4
    $ContentWidthR = $W - $Half - 4
    $R = $StartRow

    # Border top
    Draw-Border -Row $R -HalfWidth $Half
    $R++

    # Header: "HISTORY VIEW (F2/Esc to exit)" on left, details hint on right
    $leftLabel = "HISTORY VIEW"
    $leftHint = "(F2/Esc to exit)"
    $padL = $ContentWidthL - $leftLabel.Length - $leftHint.Length
    if ($padL -lt 0) { $padL = 0 }

    TryWriteAt -Row $R -Col 0 -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col 2 -Text $leftLabel -Color "Cyan" | Out-Null
    $hintCol = 2 + $leftLabel.Length + $padL
    TryWriteAt -Row $R -Col $hintCol -Text $leftHint -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half - 2) -Text " |" -Color "DarkGray" | Out-Null

    # Right panel: show details hint or details pane indicator
    $rightHint = if ($detailsVisible) { "[DETAILS VISIBLE] Esc=close" } else { "Enter=toggle details" }
    TryWriteAt -Row $R -Col $Half -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($Half + 2) -Text $rightHint.PadRight($ContentWidthR) -Color "DarkGray" | Out-Null
    TryWriteAt -Row $R -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
    $R++

    # Border after header
    Draw-Border -Row $R -HalfWidth $Half
    $R++

    # Column headers vary by subview (golden contract)
    $headerLeft = ""
    $pipelineLabel = "PIPELINE"
    switch ($subview) {
        "TASKS" {
            $headerLeft = " WORKER      CONTENT              HE"
        }
        "DOCS" {
            $headerLeft = " FILE        DESCRIPTION          ST"
        }
        "SHIP" {
            $headerLeft = " ARTIFACT    VERSION              ST"
        }
    }
    if ($headerLeft.Length -gt $ContentWidthL) {
        $headerLeft = $headerLeft.Substring(0, $ContentWidthL)
    }
    Print-Row -Row $R -LeftTxt $headerLeft -RightTxt $pipelineLabel -HalfWidth $Half -ColorL "DarkCyan" -ColorR "Cyan"
    $R++

    # Data rows (empty for now - will be populated from history data)
    # For the fixture, show placeholder based on subview
    $emptyMsg = switch ($subview) {
        "TASKS" { "(no history data)" }
        "DOCS"  { "(no docs data)" }
        "SHIP"  { "(no ship data)" }
    }
    Print-Row -Row $R -LeftTxt $emptyMsg -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
    $R++

    # If details visible, render a details pane below
    if ($detailsVisible) {
        Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++

        # Details header
        Print-Row -Row $R -LeftTxt "--- TASK DETAILS ---" -RightTxt "" -HalfWidth $Half -ColorL "Yellow" -ColorR "DarkGray"
        $R++

        # Details content (placeholder - would show selected task details)
        Print-Row -Row $R -LeftTxt "Worker: (none selected)" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"
        $R++

        Print-Row -Row $R -LeftTxt "Status: -" -RightTxt "" -HalfWidth $Half -ColorL "White" -ColorR "DarkGray"
        $R++

        Print-Row -Row $R -LeftTxt "Press ESC to close details" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
        $R++
    }
}
