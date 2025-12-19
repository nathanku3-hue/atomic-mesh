# Golden header row count (border + content + blank + border)
$script:HeaderRowCount = 4

function Get-HeaderRowCount { return $script:HeaderRowCount }

function Render-Header {
    param(
        [int]$StartRow,
        [int]$Width,
        $Snapshot,
        $State
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    $snapshot = if ($Snapshot) { $Snapshot } else { [UiSnapshot]::new() }
    $state = if ($State) { $State } else { [UiState]::new() }

    # Mode label (golden: EXEC for initialized, BOOTSTRAP otherwise)
    $isInitialized = $snapshot.PlanState -and $snapshot.PlanState.Status -ne "BOOTSTRAP"
    $modeLabel = if ($isInitialized) { "EXEC" } else { "BOOTSTRAP" }
    $modeLabelColor = if ($isInitialized) { "White" } else { "Yellow" }

    # GOLDEN NUANCE 6: Health dot color from snapshot.HealthStatus
    # "OK" → Green, "WARN" → Yellow, "FAIL" → Red
    $healthDot = [char]0x25CF  # ●
    $healthColor = switch ($snapshot.HealthStatus) {
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "Green" }  # OK or unset
    }
    # Fallback: also check AdapterError for backward compatibility
    if ($snapshot.Alerts -and $snapshot.Alerts.AdapterError) {
        $healthColor = "Red"
    }

    # GOLDEN NUANCE 5: Lane counts from snapshot.DistinctLaneCounts
    # Uses DISTINCT lanes (not total tasks) as per golden SQL
    $pendingCount = 0
    $activeCount = 0
    if ($snapshot.DistinctLaneCounts) {
        $pendingCount = [int]$snapshot.DistinctLaneCounts.pending
        $activeCount = [int]$snapshot.DistinctLaneCounts.active
    } elseif ($snapshot.LaneMetrics) {
        # Fallback: compute from lane metrics if DistinctLaneCounts not available
        foreach ($lane in $snapshot.LaneMetrics) {
            $pendingCount += $lane.Queued
            $activeCount += $lane.Active
        }
    }
    $pendingStr = "$pendingCount pending"
    $activeStr = "$activeCount active"
    $pendingColor = if ($pendingCount -gt 0) { "White" } else { "DarkGray" }
    $activeColor = if ($activeCount -gt 0) { "White" } else { "DarkGray" }

    # Path (right-aligned, truncated)
    # GOLDEN NUANCE FIX: Show ProjectPath (where user launched from), NOT RepoRoot
    # GOLDEN TRANSPLANT: lines 1125-1130, 1167-1175
    # Path truncation must be DYNAMIC based on available width, not fixed at 40
    $rawPath = if ($State -and $State.Cache -and $State.Cache.Metadata -and $State.Cache.Metadata["ProjectPath"]) {
        $State.Cache.Metadata["ProjectPath"]
    } else { "" }

    # Border line
    $borderLine = "-" * ($Width - 2)

    # Row 0: Top border
    $R = $StartRow
    TryWriteAt -Row $R -Col 0 -Text "+" -Color "Cyan" | Out-Null
    TryWriteAt -Row $R -Col 1 -Text $borderLine -Color "Cyan" | Out-Null
    TryWriteAt -Row $R -Col ($Width - 1) -Text "+" -Color "Cyan" | Out-Null
    $R++

    # Row 1: Content row
    # GOLDEN FORMULA: |  EXEC ● | x pending | x active <padding> <path>  |
    # Golden lines 1169-1171:
    #   $countsLen = $pendingStr.Length + 3 + $activeStr.Length
    #   $usedLen = 1 + 2 + $modeLabel.Length + 1 + 1 + 3 + $countsLen
    #   $padLen = $width - $usedLen - $path.Length - 3  # -3 for "  |"

    $countsLen = $pendingStr.Length + 3 + $activeStr.Length  # pending + " | " + active
    $fixedLeftLen = 1 + 2 + $modeLabel.Length + 1 + 1 + 3 + $countsLen  # | + "  " + EXEC + " " + ● + " | " + counts

    # Calculate max path length based on available width
    # Need at least 1 space padding, so: fixedLeftLen + 1 + pathLen + 3 <= width
    $maxPathLen = $Width - $fixedLeftLen - 1 - 3  # -1 for min padding, -3 for "  |"
    $maxPathLen = [Math]::Max($maxPathLen, 0)
    $maxPathLen = [Math]::Min($maxPathLen, 40)  # Golden caps at 40

    # Truncate path if needed
    $path = $rawPath
    if ($path.Length -gt $maxPathLen) {
        if ($maxPathLen -gt 3) {
            $path = "..." + $path.Substring($path.Length - ($maxPathLen - 3))
        } else {
            $path = ""  # No room for path at all
        }
    }

    # Calculate padding to right-align path (golden line 1171)
    $padLen = $Width - $fixedLeftLen - $path.Length - 3  # -3 for "  |"
    if ($padLen -lt 1) { $padLen = 1 }
    $padding = " " * $padLen

    TryWriteAt -Row $R -Col 0 -Text "|" -Color "Cyan" | Out-Null
    $col = 1
    TryWriteAt -Row $R -Col $col -Text "  " -Color "White" | Out-Null
    $col += 2
    TryWriteAt -Row $R -Col $col -Text $modeLabel -Color $modeLabelColor | Out-Null
    $col += $modeLabel.Length
    TryWriteAt -Row $R -Col $col -Text " " -Color "White" | Out-Null
    $col += 1
    TryWriteAt -Row $R -Col $col -Text $healthDot -Color $healthColor | Out-Null
    $col += 1
    TryWriteAt -Row $R -Col $col -Text " | " -Color "DarkGray" | Out-Null
    $col += 3
    TryWriteAt -Row $R -Col $col -Text $pendingStr -Color $pendingColor | Out-Null
    $col += $pendingStr.Length
    TryWriteAt -Row $R -Col $col -Text " | " -Color "DarkGray" | Out-Null
    $col += 3
    TryWriteAt -Row $R -Col $col -Text $activeStr -Color $activeColor | Out-Null
    $col += $activeStr.Length
    TryWriteAt -Row $R -Col $col -Text $padding -Color "White" | Out-Null
    $col += $padLen
    TryWriteAt -Row $R -Col $col -Text $path -Color "DarkGray" | Out-Null
    $col += $path.Length
    TryWriteAt -Row $R -Col $col -Text "  |" -Color "Cyan" | Out-Null
    $R++

    # Row 2: Blank interior row
    $blankContent = " " * ($Width - 2)
    TryWriteAt -Row $R -Col 0 -Text "|" -Color "Cyan" | Out-Null
    TryWriteAt -Row $R -Col 1 -Text $blankContent -Color "White" | Out-Null
    TryWriteAt -Row $R -Col ($Width - 1) -Text "|" -Color "Cyan" | Out-Null
    $R++

    # Row 3: Bottom border
    TryWriteAt -Row $R -Col 0 -Text "+" -Color "Cyan" | Out-Null
    TryWriteAt -Row $R -Col 1 -Text $borderLine -Color "Cyan" | Out-Null
    TryWriteAt -Row $R -Col ($Width - 1) -Text "+" -Color "Cyan" | Out-Null
}

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

# =============================================================================
# GOLDEN TRANSPLANT: Draw-InputBar (lines 8345-8377)
# Source: golden_control_panel_reference.ps1 commit 6990922
# =============================================================================
# Original golden code:
# function Draw-InputBar {
#     param([int]$width, [int]$rowInput)
#     $left = $Global:InputLeft
#     $topRow = $rowInput - 1
#     $bottomRow = $rowInput + 1
#     $boxWidth = $width - $left - 1
#     $innerWidth = $boxWidth - 2
#     # Clear columns 0-1 on all three rows
#     $leftPad = " " * $left
#     Set-Pos $topRow 0; Write-Host $leftPad -NoNewline
#     Set-Pos $rowInput 0; Write-Host $leftPad -NoNewline
#     Set-Pos $bottomRow 0; Write-Host $leftPad -NoNewline
#     # Top border: ┌───────────┐
#     Set-Pos $topRow $left
#     Write-Host ("┌" + ("─" * $innerWidth) + "┐") -NoNewline -ForegroundColor DarkGray
#     # Middle line: │ >         │
#     Set-Pos $rowInput $left
#     Write-Host "│" -NoNewline -ForegroundColor DarkGray
#     Write-Host " > " -NoNewline -ForegroundColor White
#     Write-Host (" " * ($innerWidth - 3)) -NoNewline
#     Write-Host "│" -NoNewline -ForegroundColor DarkGray
#     # Bottom border: └───────────┘
#     Set-Pos $bottomRow $left
#     Write-Host ("└" + ("─" * $innerWidth) + "┘") -NoNewline -ForegroundColor DarkGray
#     # Position cursor where typing starts
#     Set-Pos $rowInput ($left + 4)
# }
# =============================================================================

# Golden layout constants (lines 4133)
$script:InputLeft = 2

function Render-InputBox {
    param(
        [string]$Buffer,
        [int]$RowInput,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Golden transplant: exact variable names and formulas from lines 8348-8352
    $left = $script:InputLeft
    $topRow = $RowInput - 1
    $bottomRow = $RowInput + 1
    $boxWidth = $Width - $left - 1      # width of box from InputLeft to right edge
    $innerWidth = $boxWidth - 2          # space between left and right borders

    # Golden transplant: clear columns 0 to InputLeft-1 on all three rows (lines 8354-8358)
    $leftPad = " " * $left
    TryWriteAt -Row $topRow -Col 0 -Text $leftPad -Color "White" | Out-Null
    TryWriteAt -Row $RowInput -Col 0 -Text $leftPad -Color "White" | Out-Null
    TryWriteAt -Row $bottomRow -Col 0 -Text $leftPad -Color "White" | Out-Null

    # Golden transplant: Top border ┌───────────┐ (lines 8360-8362)
    $topBorder = [char]0x250C + ([string][char]0x2500 * $innerWidth) + [char]0x2510
    TryWriteAt -Row $topRow -Col $left -Text $topBorder -Color "DarkGray" | Out-Null

    # Golden transplant: Middle line │ > <buffer> │ (lines 8364-8369)
    # Truncate buffer if needed (golden: no ellipses, just truncate)
    $maxInputLen = $innerWidth - 3    # max text length (innerWidth minus " > ")
    $displayBuffer = if ($Buffer.Length -gt $maxInputLen) {
        $Buffer.Substring($Buffer.Length - $maxInputLen)
    } else { $Buffer }
    $padding = " " * ($maxInputLen - $displayBuffer.Length)

    TryWriteAt -Row $RowInput -Col $left -Text ([string][char]0x2502) -Color "DarkGray" | Out-Null
    TryWriteAt -Row $RowInput -Col ($left + 1) -Text " > " -Color "White" | Out-Null
    TryWriteAt -Row $RowInput -Col ($left + 4) -Text $displayBuffer -Color "White" | Out-Null
    TryWriteAt -Row $RowInput -Col ($left + 4 + $displayBuffer.Length) -Text $padding -Color "White" | Out-Null
    TryWriteAt -Row $RowInput -Col ($left + $boxWidth - 1) -Text ([string][char]0x2502) -Color "DarkGray" | Out-Null

    # Golden transplant: Bottom border └───────────┘ (lines 8371-8373)
    $bottomBorder = [char]0x2514 + ([string][char]0x2500 * $innerWidth) + [char]0x2518
    TryWriteAt -Row $bottomRow -Col $left -Text $bottomBorder -Color "DarkGray" | Out-Null

    # Golden transplant: cursor position at InputLeft + 4 + buffer length (line 8376)
    # Position cursor where next character will be typed (always, even if frame invalid)
    $cursorCol = $left + 4 + $displayBuffer.Length
    if (-not $script:CaptureMode) {
        try { [Console]::SetCursorPosition($cursorCol, $RowInput) } catch {}
    }
}

# Legacy function for backward compatibility with tests
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
        [int]$Width,
        $State,
        [bool]$DevHintsEnabled = $false
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Golden mode badge colors
    $modeColors = @{
        "OPS"  = "Cyan"
        "PLAN" = "Yellow"
        "RUN"  = "Magenta"
        "SHIP" = "Green"
    }
    $currentMode = if ($State -and $State.CurrentMode) { $State.CurrentMode } else { "OPS" }
    $modeLabel = "[$currentMode]"
    $modeColor = $modeColors[$currentMode]
    if (-not $modeColor) { $modeColor = "Gray" }

    Clear-Row -Row $Row -Width $Width

    # Golden footer format differs by context
    if ($State -and $State.OverlayMode -eq "History") {
        # History mode: show Tab: [TASKS] | DOCS | SHIP with current tab highlighted
        $subview = if ($State.HistorySubview) { $State.HistorySubview } else { "TASKS" }

        # Build tab string for positioning
        $tabPrefix = "Tab: "
        $tabTasks = if ($subview -eq "TASKS") { "[TASKS]" } else { " TASKS " }
        $tabDocs = if ($subview -eq "DOCS") { "[DOCS]" } else { " DOCS " }
        $tabShip = if ($subview -eq "SHIP") { "[SHIP]" } else { " SHIP " }

        # Position tabs at center-left, mode badge at right
        $half = [Math]::Floor($Width / 2)
        $tabStr = "$tabPrefix$tabTasks | $tabDocs | $tabShip"
        $tabCol = $half - $tabStr.Length
        if ($tabCol -lt 0) { $tabCol = 0 }

        # Render tab prefix
        TryWriteAt -Row $Row -Col $tabCol -Text $tabPrefix -Color "DarkGray" | Out-Null
        $col = $tabCol + $tabPrefix.Length

        # Render TASKS tab
        $tasksColor = if ($subview -eq "TASKS") { "Cyan" } else { "DarkGray" }
        TryWriteAt -Row $Row -Col $col -Text $tabTasks -Color $tasksColor | Out-Null
        $col += $tabTasks.Length

        TryWriteAt -Row $Row -Col $col -Text " | " -Color "DarkGray" | Out-Null
        $col += 3

        # Render DOCS tab
        $docsColor = if ($subview -eq "DOCS") { "Cyan" } else { "DarkGray" }
        TryWriteAt -Row $Row -Col $col -Text $tabDocs -Color $docsColor | Out-Null
        $col += $tabDocs.Length

        TryWriteAt -Row $Row -Col $col -Text " | " -Color "DarkGray" | Out-Null
        $col += 3

        # Render SHIP tab
        $shipColor = if ($subview -eq "SHIP") { "Cyan" } else { "DarkGray" }
        TryWriteAt -Row $Row -Col $col -Text $tabShip -Color $shipColor | Out-Null

        # Mode badge on far right
        $badgeCol = $Width - $modeLabel.Length
        if ($badgeCol -lt 2) { $badgeCol = 2 }
        TryWriteAt -Row $Row -Col $badgeCol -Text $modeLabel -Color $modeColor | Out-Null
    }
    else {
        # Normal mode: mode-specific hint text + mode badge right-aligned
        $hintText = switch ($currentMode) {
            "OPS"  { "ask 'health', 'drift', or type /ops" }
            "PLAN" { "describe what you want to build" }
            "RUN"  { "give feedback or press Enter" }
            "SHIP" { "/ship --confirm to release" }
            default { "" }
        }

        # Dev hints (F5/F6) only shown when enabled - NOT in golden baseline
        if ($DevHintsEnabled) {
            $hintText = "$hintText  F5 pause  F6 stats"
        }

        # Right-align: hint + space + mode badge
        $rightSection = "$hintText $modeLabel"
        $col = $Width - $rightSection.Length
        if ($col -lt 2) { $col = 2 }

        TryWriteAt -Row $Row -Col $col -Text $hintText -Color "DarkGray" | Out-Null
        TryWriteAt -Row $Row -Col ($col + $hintText.Length) -Text " " -Color "DarkGray" | Out-Null
        TryWriteAt -Row $Row -Col ($col + $hintText.Length + 1) -Text $modeLabel -Color $modeColor | Out-Null
    }
}
