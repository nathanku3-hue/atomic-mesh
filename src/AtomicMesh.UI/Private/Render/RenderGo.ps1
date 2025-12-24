# Helper to draw border line
function Draw-Border {
    param([int]$Row, [int]$HalfWidth)

    if (-not (Get-ConsoleFrameValid)) { return }

    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }

    $leftBorder = "+" + ("-" * ($HalfWidth - 2)) + "+"
    $rightBorder = "+" + ("-" * ($W - $HalfWidth - 2)) + "+"

    TryWriteAt -Row $Row -Col 0 -Text $leftBorder -Color "DarkGray" | Out-Null
    TryWriteAt -Row $Row -Col $HalfWidth -Text $rightBorder -Color "DarkGray" | Out-Null
}

function Render-Go {
    param(
        $Snapshot,
        $State,
        [int]$StartRow = 0,
        [int]$BottomRow = -1   # Golden: RowInput - 2 (frame-fill target)
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $snapshot = if ($Snapshot) { $Snapshot } else { [UiSnapshot]::new() }
    $planState = if ($snapshot.PlanState) { $snapshot.PlanState } else { [PlanState]::new() }
    $lanes = if ($snapshot.LaneMetrics) { $snapshot.LaneMetrics } else { @() }

    # Get dimensions
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $Half = [Math]::Floor($W / 2)
    $HalfRight = $W - $Half
    $ContentWidthR = $HalfRight - 4  # For pipeline rendering
    $R = $StartRow

    # Count active/queued from lanes
    $activeCount = 0
    $queuedCount = 0
    foreach ($lane in $lanes) {
        $activeCount += $lane.Active
        $queuedCount += $lane.Queued
    }

    # Build left column content (page-specific)
    $leftLines = @(
        @{ Text = "GO / EXEC"; Color = "Cyan" },
        @{ Text = "Active: $activeCount  Queued: $queuedCount"; Color = if ($activeCount -gt 0) { "Yellow" } else { "DarkGray" } }
    )

    # Legend (only when any non-idle lane)
    $showLegend = ($activeCount -gt 0 -or $queuedCount -gt 0)
    if ($showLegend) {
        if ($activeCount -gt 0) {
            $leftLines += @{ Text = "Legend: $($lanes[0].DotChar) Running"; Color = "Green" }
        }
        if ($queuedCount -gt 0) {
            $leftLines += @{ Text = "Legend: $([char]0x25CB) Queued"; Color = "Yellow" }  # ○ queued
        }
    }

    # Add lane summary lines
    foreach ($lane in $lanes) {
        if ($lane.Active -gt 0 -or $lane.Queued -gt 0) {
            $laneColor = if ($lane.StateColor) { $lane.StateColor } elseif ($lane.Active -gt 0) { "Cyan" } elseif ($lane.Queued -gt 0) { "Yellow" } else { "DarkGray" }
            $leftLines += @{ Text = "  [$($lane.Name)] A:$($lane.Active) Q:$($lane.Queued)"; Color = $laneColor }
        }
    }

    # Pad to 6 lines minimum
    while ($leftLines.Count -lt 6) {
        $leftLines += @{ Text = ""; Color = "DarkGray" }
    }

    # Right column: PIPELINE directives (golden layout)
    $pipelineDirectives = Get-PipelineRightColumn -Snapshot $snapshot

    # Render rows using golden two-column format
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
