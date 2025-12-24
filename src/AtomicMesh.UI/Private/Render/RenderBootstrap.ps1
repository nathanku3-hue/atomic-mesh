function Render-Bootstrap {
    param(
        $Snapshot,
        $State,
        [int]$StartRow = 0,
        [int]$BottomRow = -1   # Golden: RowInput - 2 (frame-fill target)
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Get dimensions
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $Half = [Math]::Floor($W / 2)
    $HalfRight = $W - $Half
    $ContentWidthR = $HalfRight - 4  # For pipeline rendering

    # Left column: minimal bootstrap layout
    $leftLines = @(
        @{ Text = "New repo"; Color = "Yellow" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = "Next: /init"; Color = "Cyan" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" }
    )

    # Right column: empty
    $pipelineDirectives = @(
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = ""; Color = "DarkGray" }
    )

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
    # GOLDEN TRANSPLANT: Frame-fill loop (lines 7572-7576 pattern)
    # Source: golden_control_panel_reference.ps1 commit 6990922
    # =============================================================================
    if ($BottomRow -gt 0) {
        while ($R -lt $BottomRow) {
            Print-Row -Row $R -LeftTxt "" -RightTxt "" -HalfWidth $Half -ColorL "DarkGray" -ColorR "DarkGray"
            $R++
        }
    }
}
