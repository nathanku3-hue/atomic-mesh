# =============================================================================
# STREAM ROW RENDERER (golden lines 7977-7995)
# Renders pre-computed StreamRow model - no state computation here
# =============================================================================
function Render-StreamRow {
    param(
        [int]$Row,
        [int]$HalfWidth,
        $StreamRow,           # Pre-computed hashtable from Compute-StreamRows
        $RightDirective = $null  # Optional right column directive
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Get layout constants
    $nameWidth = Get-StreamNameWidth
    $barWidth = Get-StreamBarWidth
    $stateWidth = Get-StreamStateWidth

    function Get-StreamProp {
        param($obj, [string]$prop, $fallback)
        if (-not $obj) { return $fallback }
        if ($obj -is [hashtable]) {
            return $(if ($obj.ContainsKey($prop)) { $obj[$prop] } else { $fallback })
        }
        try {
            $p = $obj.PSObject.Properties[$prop]
            if ($p) { return $p.Value }
        } catch {}
        return $fallback
    }

    # Get terminal width
    $W = if ($script:CaptureMode) { $script:CaptureWidth } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $HalfRight = $W - $HalfWidth
    $ContentWidthL = $HalfWidth - 4  # "| " + content + " |"
    $ContentWidthR = $HalfRight - 4

    # Calculate summary max length (remaining space in left column)
    # Format: | <name:10> <bar:5> <state:8> <summary:remaining> |
    $summaryMaxLen = $ContentWidthL - $nameWidth - 1 - $barWidth - 1 - $stateWidth - 1
    if ($summaryMaxLen -lt 0) { $summaryMaxLen = 0 }

    # Extract stream row fields with safe defaults
    $name = Get-StreamProp $StreamRow "Name" ""
    $bar = Get-StreamProp $StreamRow "Bar" ""
    $barColor = Get-StreamProp $StreamRow "BarColor" "DarkGray"
    $state = Get-StreamProp $StreamRow "State" ""
    $summary = Get-StreamProp $StreamRow "Summary" ""
    $summaryColor = Get-StreamProp $StreamRow "SummaryColor" "DarkGray"

    # Truncate summary if needed
    if ($summary.Length -gt $summaryMaxLen) {
        $summary = $summary.Substring(0, $summaryMaxLen)
    }

    # Render left column: | <name> <bar> <state> <summary> |
    $col = 0
    TryWriteAt -Row $Row -Col $col -Text "| " -Color "DarkGray" | Out-Null
    $col += 2

    TryWriteAt -Row $Row -Col $col -Text $name.PadRight($nameWidth) -Color "White" | Out-Null
    $col += $nameWidth

    TryWriteAt -Row $Row -Col $col -Text " " -Color "White" | Out-Null
    $col += 1

    TryWriteAt -Row $Row -Col $col -Text $bar.PadRight($barWidth) -Color $barColor | Out-Null
    $col += $barWidth

    TryWriteAt -Row $Row -Col $col -Text " " -Color "White" | Out-Null
    $col += 1

    TryWriteAt -Row $Row -Col $col -Text $state.PadRight($stateWidth) -Color $barColor | Out-Null
    $col += $stateWidth

    TryWriteAt -Row $Row -Col $col -Text " " -Color "White" | Out-Null
    $col += 1

    TryWriteAt -Row $Row -Col $col -Text $summary.PadRight($summaryMaxLen) -Color $summaryColor | Out-Null
    $col = $HalfWidth - 2

    TryWriteAt -Row $Row -Col $col -Text " |" -Color "DarkGray" | Out-Null

    # Render right column (if provided)
    if ($RightDirective) {
        $rightText = if ($RightDirective.Text) { $RightDirective.Text } else { "" }
        $rightColor = if ($RightDirective.Color) { $RightDirective.Color } else { "DarkGray" }

        if ($rightText.Length -gt $ContentWidthR) {
            $rightText = $rightText.Substring(0, $ContentWidthR)
        }

        TryWriteAt -Row $Row -Col $HalfWidth -Text "| " -Color "DarkGray" | Out-Null
        TryWriteAt -Row $Row -Col ($HalfWidth + 2) -Text $rightText.PadRight($ContentWidthR) -Color $rightColor | Out-Null
        TryWriteAt -Row $Row -Col ($W - 2) -Text " |" -Color "DarkGray" | Out-Null
    }
}

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

    # =============================================================================
    # UNIFIED 6-ROW LAYOUT: STREAMS (left) + PIPELINE (right)
    # Left column: STREAMS header + 4 stream rows + empty row
    # Right column: PIPELINE with optional Docs summary line (pre-draft)
    # =============================================================================

    # Get pre-computed stream rows from snapshot (or create defaults)
    $streamRows = @()
    if ($snapshot.LaneMetrics -and $snapshot.LaneMetrics.Count -gt 0) {
        $streamRows = Compute-StreamRows -LaneMetrics $snapshot.LaneMetrics
    }

    # Ensure we always have 4 stream rows (with defaults if missing)
    # Stream display order: backend/frontend first, then QA/librarian
    $defaultNames = @("BACKEND", "FRONTEND", "QA", "LIBRARIAN")
    $filled = Get-StreamBarFilled
    $empty = Get-StreamBarEmpty
    $defaultBar = "$empty$empty$empty$empty$empty"  # □□□□□

    while ($streamRows.Count -lt 4) {
        $idx = $streamRows.Count
        $name = if ($idx -lt $defaultNames.Count) { $defaultNames[$idx] } else { "" }
        $streamRows += @{
            Name         = $name
            Bar          = $defaultBar
            BarColor     = "DarkGray"
            State        = "IDLE"
            Summary      = ""
            SummaryColor = "DarkGray"
        }
    }

    # Right column: PIPELINE (always, with Docs summary pre-draft)
    # Reducer handles state detection
    $rightDirectives = Get-PipelineRightColumn -Snapshot $snapshot

    # Detect pre-draft state for left-column guidance
    $hasDraft = $planState -and $planState.HasDraft
    $isAccepted = $planState -and $planState.Accepted
    $isPreInit = $planState -and $planState.Status -eq "PRE_INIT"
    $isPreDraft = (-not $hasDraft) -and (-not $isAccepted) -and (-not $isPreInit)

    $R = $StartRow

    # Row 0: STREAMS header (left) + PIPELINE header (right)
    $right0 = if ($rightDirectives.Count -gt 0) { $rightDirectives[0] } else { @{ Text = ""; Color = "DarkGray" } }
    $rightColor0 = if ($right0.Color) { $right0.Color } else { "DarkGray" }
    Print-Row -Row $R -LeftTxt "STREAMS" -RightTxt $right0.Text -HalfWidth $Half -ColorL "Yellow" -ColorR $rightColor0
    $R++

    # Rows 1-4: Stream rows (left) + pipeline content (right)
    for ($i = 0; $i -lt 4; $i++) {
        $streamRow = if ($i -lt $streamRows.Count) { $streamRows[$i] } else { @{ Name = ""; Bar = ""; BarColor = "DarkGray"; State = ""; Summary = ""; SummaryColor = "DarkGray" } }
        $rightIdx = $i + 1
        $right = if ($rightIdx -lt $rightDirectives.Count) { $rightDirectives[$rightIdx] } else { @{ Text = ""; Color = "DarkGray" } }

        # Special handling for pipeline stages row (has StageColors)
        if ($right.ContainsKey('StageColors') -and $right.StageColors) {
            Render-StreamRow -Row $R -HalfWidth $Half -StreamRow $streamRow -RightDirective @{ Text = ""; Color = "DarkGray" }
            Render-PipelineStagesRow -Text $right.Text -StageColors $right.StageColors -Row $R -Col ($Half + 2) -Width $ContentWidthR
        }
        else {
            Render-StreamRow -Row $R -HalfWidth $Half -StreamRow $streamRow -RightDirective $right
        }
        $R++
    }

    # Row 5: Empty left + last pipeline content (right)
    $right5 = if ($rightDirectives.Count -gt 5) { $rightDirectives[5] } else { @{ Text = ""; Color = "DarkGray" } }
    $rightColor5 = if ($right5.Color) { $right5.Color } else { "DarkGray" }
    Print-Row -Row $R -LeftTxt "" -RightTxt $right5.Text -HalfWidth $Half -ColorL "DarkGray" -ColorR $rightColor5
    $R++

    # =============================================================================
    # GOLDEN TRANSPLANT: Frame-fill loop (lines 7572-7576)
    # Pre-draft guidance moved 2 rows down into frame-fill area:
    # - Row 7: Blocker (red) or >>> Next: /draft-plan (cyan)
    # - Row 8: Hint: D = doc details
    # =============================================================================
    if ($BottomRow -gt 0) {
        # Pre-compute guidance for pre-draft (skip if adapter error)
        $showGuidance = $isPreDraft -and -not $hasError
        $docsAllPassed = $false
        try { $docsAllPassed = $snapshot.DocsAllPassed -eq $true } catch {}

        $frameRowIdx = 0
        while ($R -lt $BottomRow) {
            $leftFill = ""
            $leftColor = "DarkGray"

            if ($showGuidance) {
                if ($frameRowIdx -eq 1) {
                    # Row 7 (2nd frame-fill row): Blocker or Next guidance
                    if ($docsAllPassed) {
                        $leftFill = ">>> Next: /draft-plan"
                        $leftColor = "Cyan"
                    } else {
                        $leftFill = "Blocker: Complete docs first"
                        $leftColor = "Red"
                    }
                } elseif ($frameRowIdx -eq 2) {
                    # Row 8 (3rd frame-fill row): D hint
                    $leftFill = "Hint: D = doc details"
                    $leftColor = "DarkGray"
                }
            }

            Print-Row -Row $R -LeftTxt $leftFill -RightTxt "" -HalfWidth $Half -ColorL $leftColor -ColorR "DarkGray"
            $R++
            $frameRowIdx++
        }
    }
}
