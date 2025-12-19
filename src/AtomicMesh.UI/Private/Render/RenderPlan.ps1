# Golden-Parity Print-Row: Two-column bordered layout
function Print-Row {
    param(
        [int]$Row,
        [string]$LeftTxt,
        [string]$RightTxt,
        [int]$HalfWidth,
        [string]$ColorL = "White",
        [string]$ColorR = "White"
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Calculate widths (match golden exactly)
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $HalfRight = $W - $HalfWidth
    $ContentWidthL = $HalfWidth - 4    # "| " (2) + content + " |" (2)
    $ContentWidthR = $HalfRight - 4

    # Truncate if needed (no ellipses per golden rule)
    if ($LeftTxt.Length -gt $ContentWidthL) {
        $LeftTxt = $LeftTxt.Substring(0, $ContentWidthL)
    }
    if ($RightTxt.Length -gt $ContentWidthR) {
        $RightTxt = $RightTxt.Substring(0, $ContentWidthR)
    }

    # Draw Left Box at column 0
    TryWriteAt -Row $Row -Col 0 -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $Row -Col 2 -Text ($LeftTxt.PadRight($ContentWidthL)) -Color $ColorL | Out-Null
    TryWriteAt -Row $Row -Col ($HalfWidth - 2) -Text " |" -Color "DarkGray" | Out-Null

    # Draw Right Box at column HalfWidth
    TryWriteAt -Row $Row -Col $HalfWidth -Text "| " -Color "DarkGray" | Out-Null
    TryWriteAt -Row $Row -Col ($HalfWidth + 2) -Text ($RightTxt.PadRight($ContentWidthR)) -Color $ColorR | Out-Null
    TryWriteAt -Row $Row -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
}

function Render-Plan {
    param(
        $Snapshot,
        $State,
        [int]$StartRow = 0,
        [int]$BottomRow = -1   # Golden: RowInput - 2 (frame-fill target)
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $snapshot = if ($Snapshot) { $Snapshot } else { [UiSnapshot]::new() }
    $planState = if ($snapshot.PlanState) { $snapshot.PlanState } else { [PlanState]::new() }
    $alerts = if ($snapshot.Alerts) { $snapshot.Alerts } else { [UiAlerts]::new() }

    # Get dimensions
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $Half = [Math]::Floor($W / 2)
    $HalfRight = $W - $Half
    $ContentWidthR = $HalfRight - 4  # For pipeline rendering

    # Check for adapter error state
    $hasError = $alerts.AdapterError -and $alerts.AdapterError.Length -gt 0

    # Compute plan state line (golden logic)
    $planStateLine = ""
    $planStateColor = "White"
    if ($hasError) {
        $planStateLine = "ERROR: Backend unreachable"
        $planStateColor = "Red"
    }
    elseif ($planState.Accepted) {
        $planStateLine = "Plan: accepted"
    }
    elseif ($planState.HasDraft) {
        $planStateLine = "Plan: draft exists (not accepted)"
    }
    else {
        $planStateLine = "Plan: no draft"
    }

    # Left column content (page-specific)
    $leftLines = @(
        @{ Text = "PLAN"; Color = "Yellow" },
        @{ Text = $planStateLine; Color = $planStateColor },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" }
    )

    # Right column: PIPELINE directives (golden layout)
    $pipelineDirectives = Get-PipelineRightColumn -Snapshot $snapshot

    # Render rows using golden two-column format
    $R = $StartRow

    for ($i = 0; $i -lt 6; $i++) {
        $left = if ($i -lt $leftLines.Count) { $leftLines[$i] } else { @{ Text = ""; Color = "DarkGray" } }
        $right = if ($i -lt $pipelineDirectives.Count) { $pipelineDirectives[$i] } else { @{ Text = ""; Color = "DarkGray" } }

        # Special handling for pipeline stages row (index 3)
        if ($right.ContainsKey('StageColors') -and $right.StageColors) {
            # Render left side normally
            Print-Row -Row $R -LeftTxt $left.Text -RightTxt "" -HalfWidth $Half -ColorL $left.Color -ColorR "DarkGray"
            # Render pipeline stages with colors in right column
            Render-PipelineStagesRow -Text $right.Text -StageColors $right.StageColors -Row $R -Col ($Half + 2) -Width $ContentWidthR
        }
        else {
            $rightColor = if ($right.Color) { $right.Color } else { "DarkGray" }
            Print-Row -Row $R -LeftTxt $left.Text -RightTxt $right.Text -HalfWidth $Half -ColorL $left.Color -ColorR $rightColor
        }
        $R++
    }

    # =============================================================================
    # GOLDEN TRANSPLANT: Frame-fill loop (lines 7572-7576)
    # Source: golden_control_panel_reference.ps1 commit 6990922
    # =============================================================================
    if ($BottomRow -gt 0) {
        while ($R -lt $BottomRow) {
            Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
            $R++
        }
    }
}
