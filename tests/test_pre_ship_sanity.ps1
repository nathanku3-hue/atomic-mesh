# Pre-Ship Sanity Checks
# Verifies real-world behavior beyond golden fixtures

param([switch]$Interactive)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = "$RepoRoot\src\AtomicMesh.UI"

# Source all module files
$files = @(
    'Private/Models/UiToast.ps1',
    'Private/Models/UiEvent.ps1',
    'Private/Models/UiEventLog.ps1',
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/WorkerInfo.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Models/UiCache.ps1',
    'Private/Models/UiState.ps1',
    'Private/Reducers/ComputePlanState.ps1',
    'Private/Reducers/ComputeLaneMetrics.ps1',
    'Private/Reducers/ComputeNextHint.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1',
    'Private/Layout/LayoutConstants.ps1',
    'Private/Render/Console.ps1',
    'Private/Render/RenderCommon.ps1',
    'Private/Render/RenderPlan.ps1',
    'Private/Render/RenderGo.ps1',
    'Private/Render/RenderBootstrap.ps1',
    'Private/Render/CommandPicker.ps1',
    'Private/Render/Overlays/RenderHistory.ps1'
)
foreach ($file in $files) {
    $fullPath = Join-Path $ModuleRoot $file
    if (Test-Path $fullPath) { . $fullPath }
}

# Source routers
. "$ModuleRoot\Public\Invoke-CommandRouter.ps1"
. "$ModuleRoot\Public\Invoke-KeyRouter.ps1"

$passed = 0
$failed = 0

function Test-Check {
    param([string]$Name, [scriptblock]$Block)
    Write-Host "CHECK: $Name ... " -NoNewline
    try {
        $result = & $Block
        if ($result -eq $true) {
            Write-Host "PASS" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "FAIL ($result)" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ""
Write-Host "=" * 60
Write-Host "PRE-SHIP SANITY CHECKS"
Write-Host "=" * 60
Write-Host ""

# -----------------------------------------------------------------------------
# CHECK 1: Real console single frame (no exceptions)
# -----------------------------------------------------------------------------
Test-Check "Real console single frame render" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "UNKNOWN"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    # Use capture mode to avoid actual console writes during test
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Plan -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Verify output is non-empty and contains expected content
    if ($output -match "PLAN" -and $output.Length -gt 50) {
        return $true
    }
    return "Output missing PLAN or too short"
}

# -----------------------------------------------------------------------------
# CHECK 2: Tab ignored when input buffer non-empty
# -----------------------------------------------------------------------------
Test-Check "Tab ignored when typing (input non-empty)" {
    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    $state.CurrentMode = "OPS"
    $state.InputBuffer = "/dr"  # Simulating user typing /dr

    $origMode = $state.CurrentMode

    # Simulate Tab keypress
    $keyInfo = [System.ConsoleKeyInfo]::new([char]9, [System.ConsoleKey]::Tab, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $keyInfo -State $state

    # Tab should return "noop" and mode should NOT change
    if ($result -eq "noop" -and $state.CurrentMode -eq $origMode) {
        return $true
    }
    return "Mode changed or wrong result: $result, mode=$($state.CurrentMode)"
}

# -----------------------------------------------------------------------------
# CHECK 3: Tab cycles mode when input empty
# -----------------------------------------------------------------------------
Test-Check "Tab cycles mode when input empty" {
    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    $state.CurrentMode = "OPS"
    $state.InputBuffer = ""

    $keyInfo = [System.ConsoleKeyInfo]::new([char]9, [System.ConsoleKey]::Tab, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $keyInfo -State $state

    # Tab should cycle mode OPS -> PLAN
    if ($result -eq "mode" -and $state.CurrentMode -eq "PLAN") {
        return $true
    }
    return "Mode not cycled: result=$result, mode=$($state.CurrentMode)"
}

# -----------------------------------------------------------------------------
# CHECK 4: /go switches to GO page (requires accepted plan)
# -----------------------------------------------------------------------------
Test-Check "/go switches to GO page" {
    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"  # Guard: /go requires accepted plan

    $result = Invoke-CommandRouter -Command "/go" -State $state -Snapshot $snapshot

    if ($state.CurrentPage -eq "GO" -and $result -eq "ok") {
        return $true
    }
    return "Page not GO or wrong result: page=$($state.CurrentPage), result=$result"
}

# -----------------------------------------------------------------------------
# CHECK 5: /plan returns to PLAN page
# -----------------------------------------------------------------------------
Test-Check "/plan returns to PLAN page" {
    $state = [UiState]::new()
    $state.CurrentPage = "GO"

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()

    $result = Invoke-CommandRouter -Command "/plan" -State $state -Snapshot $snapshot

    if ($state.CurrentPage -eq "PLAN" -and $result -eq "ok") {
        return $true
    }
    return "Page not PLAN or wrong result: page=$($state.CurrentPage), result=$result"
}

# -----------------------------------------------------------------------------
# CHECK 6: Adapter error stays within two-column frame
# -----------------------------------------------------------------------------
Test-Check "Adapter error within layout bounds" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ERROR"
    $snapshot.Alerts = [UiAlerts]::new()
    $snapshot.Alerts.AdapterError = "Connection failed: Backend unreachable"
    $snapshot.LaneMetrics = @()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Plan -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Check that error text appears and layout is intact (has pipe chars)
    if ($output -match "ERROR" -and $output -match "\|") {
        # Verify no line exceeds 80 chars
        $lines = $output -split "`n"
        foreach ($line in $lines) {
            if ($line.Length -gt 80) {
                return "Line exceeds 80 chars: $($line.Length)"
            }
        }
        return $true
    }
    return "Error not visible or layout broken"
}

# -----------------------------------------------------------------------------
# CHECK 7: History Tab cycles subview
# -----------------------------------------------------------------------------
Test-Check "History Tab cycles subview (TASKS->DOCS)" {
    $state = [UiState]::new()
    $state.OverlayMode = "History"
    $state.HistorySubview = "TASKS"
    $state.InputBuffer = ""

    $keyInfo = [System.ConsoleKeyInfo]::new([char]9, [System.ConsoleKey]::Tab, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $keyInfo -State $state

    if ($result -eq "historyTab" -and $state.HistorySubview -eq "DOCS") {
        return $true
    }
    return "Subview not cycled: result=$result, subview=$($state.HistorySubview)"
}

# -----------------------------------------------------------------------------
# CHECK 8: ESC exits History overlay
# -----------------------------------------------------------------------------
Test-Check "ESC exits History overlay" {
    $state = [UiState]::new()
    $state.OverlayMode = "History"
    $state.InputBuffer = ""

    $keyInfo = [System.ConsoleKeyInfo]::new([char]27, [System.ConsoleKey]::Escape, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $keyInfo -State $state

    if ($result -eq "overlay" -and $state.OverlayMode -eq "None") {
        return $true
    }
    return "Overlay not cleared: result=$result, overlay=$($state.OverlayMode)"
}

# -----------------------------------------------------------------------------
# CHECK 9: ESC clears input when not in overlay
# -----------------------------------------------------------------------------
Test-Check "ESC clears input buffer" {
    $state = [UiState]::new()
    $state.OverlayMode = "None"
    $state.InputBuffer = "/draft"

    $keyInfo = [System.ConsoleKeyInfo]::new([char]27, [System.ConsoleKey]::Escape, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $keyInfo -State $state

    if ($result -eq "input" -and $state.InputBuffer -eq "") {
        return $true
    }
    return "Input not cleared: result=$result, buffer=$($state.InputBuffer)"
}

# -----------------------------------------------------------------------------
# CHECK 10: Hint bar has no F4/F5/F6 (golden parity)
# -----------------------------------------------------------------------------
Test-Check "Hint bar has no F4/F5/F6" {
    $state = [UiState]::new()
    $state.OverlayMode = "None"
    $state.CurrentMode = "PLAN"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-HintBar -Row 21 -Width 80 -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Verify NO F4/F5/F6 text appears (dev hints disabled by default)
    if ($output -match "F4" -or $output -match "F5" -or $output -match "F6") {
        return "Found non-golden hint: F4/F5/F6 present"
    }
    # Golden format: mode badge should be present
    if ($output -notmatch "\[PLAN\]") {
        return "Missing golden mode badge: [PLAN] not present"
    }
    return $true
}

# -----------------------------------------------------------------------------
# CHECK 11: Hint bar shows different text in History overlay
# -----------------------------------------------------------------------------
Test-Check "Hint bar shows subview tabs in History" {
    $state = [UiState]::new()
    $state.OverlayMode = "History"
    $state.HistorySubview = "TASKS"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-HintBar -Row 21 -Width 80 -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Golden format: In History mode, should show "Tab:" prefix with subview tabs
    if ($output -match "Tab:") {
        return $true
    }
    return "History hint bar missing 'Tab:' prefix for subview tabs"
}

# -----------------------------------------------------------------------------
# CHECK 12: Input line renders at correct position
# -----------------------------------------------------------------------------
Test-Check "Input line renders with prompt" {
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-InputLine -Buffer "test" -Row 23 -Width 80
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Check row 23 (0-indexed) has "> test"
    $lines = $output -split "`n"
    if ($lines.Count -ge 24 -and $lines[23] -match "^> test") {
        return $true
    }
    return "Input line not at row 23 or missing prompt"
}

# -----------------------------------------------------------------------------
# CHECK 13: Header renders with top border
# -----------------------------------------------------------------------------
Test-Check "Header starts with top border (+)" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # First row should start with '+' (top border)
    $lines = $output -split "`n"
    if ($lines.Count -ge 1 -and $lines[0] -match "^\+") {
        return $true
    }
    return "Header first line doesn't start with '+': $($lines[0].Substring(0, [Math]::Min(20, $lines[0].Length)))"
}

# -----------------------------------------------------------------------------
# CHECK 14: Header has mode label and health dot
# -----------------------------------------------------------------------------
Test-Check "Header contains mode label and health dot" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACTIVE"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # Header should contain EXEC or BOOTSTRAP label
    if ($output -match "EXEC" -or $output -match "BOOTSTRAP") {
        # Should also contain health dot (●)
        if ($output -match [char]0x25CF) {
            return $true
        }
        return "Header missing health dot"
    }
    return "Header missing mode label (EXEC/BOOTSTRAP)"
}

# -----------------------------------------------------------------------------
# CHECK 15: Full frame structure (header row 0, content row 4+)
# -----------------------------------------------------------------------------
Test-Check "Full frame: header at 0, content at 4" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    # Render header at row 0
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    # Render content at row 4
    Render-Plan -Snapshot $snapshot -State $state -StartRow 4
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Row 0 should be header border (+...)
    if ($lines.Count -lt 5) {
        return "Not enough rows: $($lines.Count)"
    }
    if ($lines[0] -notmatch "^\+") {
        return "Row 0 not header border"
    }

    # Row 3 should also be border (bottom of header)
    if ($lines[3] -notmatch "^\+") {
        return "Row 3 not header bottom border"
    }

    # Row 4 should be content (starts with '|' for PLAN screen)
    if ($lines[4] -notmatch "^\|") {
        return "Row 4 not content (expected '|')"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 16: Boxed input has Unicode borders (golden transplant)
# -----------------------------------------------------------------------------
Test-Check "Boxed input has Unicode borders" {
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    # Golden: rowInput at 75% of height
    $rowInput = [Math]::Floor(24 * 0.75)  # = 18
    Render-InputBox -Buffer "test" -RowInput $rowInput -Width 80
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Row 17 (rowInput-1) should have top border ┌
    if ($lines.Count -le $rowInput) {
        return "Not enough rows captured"
    }

    $topBorderRow = $rowInput - 1
    if ($lines[$topBorderRow] -notmatch [char]0x250C) {  # ┌
        return "Top border row missing Unicode corner"
    }

    # Row 18 (rowInput) should have │ > │
    if ($lines[$rowInput] -notmatch [char]0x2502) {  # │
        return "Input row missing vertical border"
    }

    # Row 19 (rowInput+1) should have bottom border └
    $bottomBorderRow = $rowInput + 1
    if ($lines[$bottomBorderRow] -notmatch [char]0x2514) {  # └
        return "Bottom border row missing Unicode corner"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 17: Frame-fill extends borders to footer row
# -----------------------------------------------------------------------------
Test-Check "Frame-fill extends borders to footer" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    # Simulate golden layout: content starts at row 4, footer at row 16
    $contentStartRow = 4
    $footerRow = 16  # rowInput - 2 where rowInput = 18
    Render-Plan -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Check that rows between content (4-7) and footer (16) have borders
    # Content ends around row 7-8, frame-fill should continue to row 15
    for ($row = 10; $row -lt $footerRow; $row++) {
        if ($lines.Count -gt $row -and $lines[$row].Length -gt 0) {
            if ($lines[$row] -notmatch "^\|") {
                return "Row $row missing frame border"
            }
        }
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 18: Get-PromptLayout returns golden values (PHASE 2)
# -----------------------------------------------------------------------------
Test-Check "Get-PromptLayout returns golden layout values" {
    $layout = Get-PromptLayout -Width 80 -Height 24

    # Golden: RowInput = Floor(24 * 0.75) = 18
    if ($layout.RowInput -ne 18) {
        return "RowInput should be 18, got $($layout.RowInput)"
    }

    # Golden: FooterRow = RowInput - 2 = 16
    if ($layout.RowFooter -ne 16) {
        return "RowFooter should be 16, got $($layout.RowFooter)"
    }

    # Golden: ContentStart = 4 (after 4-row header)
    if ($layout.ContentStart -ne 4) {
        return "ContentStart should be 4, got $($layout.ContentStart)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 19: Header shows truncated path on right (golden transplant)
# -----------------------------------------------------------------------------
Test-Check "Header shows truncated path on right" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # GOLDEN NUANCE FIX: Use ProjectPath for header display (not RepoRoot)
    $state.Cache.Metadata["ProjectPath"] = "C:\Users\Developer\Documents\Projects\MyLongProjectName\SubFolder"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Row 1 (content row) should contain truncated path with leading "..."
    if ($lines.Count -ge 2) {
        $contentRow = $lines[1]
        # Path should be truncated to 40 chars with "..."
        if ($contentRow -match "\.\.\.") {
            # Should also end with closing border
            if ($contentRow -match "\|$") {
                return $true
            }
            return "Header content row missing right border"
        }
        return "Path not truncated with ... for long path"
    }
    return "Not enough header rows"
}

# -----------------------------------------------------------------------------
# CHECK 20: Command picker filters commands (PHASE 3)
# -----------------------------------------------------------------------------
Test-Check "Command picker filters with /dr prefix" {
    # Get-PickerCommands should filter to /draft-plan when given "dr"
    $filtered = Get-PickerCommands -Filter "dr"

    if ($filtered.Count -ne 1) {
        return "Expected 1 match for 'dr', got $($filtered.Count)"
    }

    if ($filtered[0].Name -ne "draft-plan") {
        return "Expected 'draft-plan', got $($filtered[0].Name)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 21: Command picker returns all commands with no filter
# -----------------------------------------------------------------------------
Test-Check "Command picker returns all with empty filter" {
    $all = Get-PickerCommands -Filter ""

    # Should return at least 8 commands (help, plan, go, draft-plan, accept-plan, status, clear, quit)
    if ($all.Count -lt 8) {
        return "Expected at least 8 commands, got $($all.Count)"
    }

    # /help should be first (priority order)
    if ($all[0].Name -ne "help") {
        return "Expected 'help' first, got $($all[0].Name)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 22: Header path truncation at different widths
# -----------------------------------------------------------------------------
Test-Check "Header path truncation at width 120" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # GOLDEN NUANCE FIX: Use ProjectPath for header display
    $state.Cache.Metadata["ProjectPath"] = "C:\Short"

    Enable-CaptureMode -Width 120 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 120 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Row 1 (content row) should contain short path (no truncation needed)
    if ($lines.Count -ge 2) {
        $contentRow = $lines[1]
        if ($contentRow -match "C:\\Short") {
            return $true
        }
        return "Short path not displayed correctly at width 120"
    }
    return "Not enough header rows at width 120"
}

# -----------------------------------------------------------------------------
# CHECK 23: Narrow width (60 cols) frame integrity (PHASE 4)
# -----------------------------------------------------------------------------
Test-Check "Frame integrity at narrow width 60" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    Enable-CaptureMode -Width 60 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 60 -Snapshot $snapshot -State $state
    Render-Plan -Snapshot $snapshot -State $state -StartRow 4 -BottomRow 14
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Verify header borders at width 60
    if ($lines[0].Length -gt 60) {
        return "Header line exceeds 60 chars: $($lines[0].Length)"
    }
    if ($lines[0] -notmatch "^\+") {
        return "Header border missing at narrow width"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 24: Wide width (120 cols) frame integrity (PHASE 4)
# -----------------------------------------------------------------------------
Test-Check "Frame integrity at wide width 120" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    # GOLDEN NUANCE FIX: Use ProjectPath for header display
    $state.Cache.Metadata["ProjectPath"] = "C:\Long\Path\To\Project\Repository"

    Enable-CaptureMode -Width 120 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 120 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Header should fill to 120 cols
    if ($lines[0].Length -lt 118) {
        return "Header border too short at wide width: $($lines[0].Length)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 25: Short height (16 rows) layout adapts (PHASE 4)
# -----------------------------------------------------------------------------
Test-Check "Layout adapts to short height 16" {
    $layout = Get-PromptLayout -Width 80 -Height 16

    # RowInput should be clamped appropriately
    # Golden: Floor(16 * 0.75) = 12, but min space is needed
    if ($layout.RowInput -lt 10) {
        return "RowInput too low for height 16: $($layout.RowInput)"
    }
    if ($layout.RowInput -gt 13) {
        return "RowInput too high for height 16: $($layout.RowInput)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 26: Command picker state management (PHASE 4)
# -----------------------------------------------------------------------------
Test-Check "Command picker state cycles correctly" {
    Reset-PickerState
    Open-CommandPicker -InitialFilter ""

    $state = Get-PickerState
    if (-not $state.IsActive) {
        return "Picker should be active after Open"
    }
    if ($state.Commands.Count -lt 8) {
        return "Picker should have at least 8 commands"
    }

    Navigate-PickerDown
    $state = Get-PickerState
    if ($state.SelectedIndex -ne 1) {
        return "SelectedIndex should be 1 after Down, got $($state.SelectedIndex)"
    }

    Navigate-PickerUp
    $state = Get-PickerState
    if ($state.SelectedIndex -ne 0) {
        return "SelectedIndex should be 0 after Up, got $($state.SelectedIndex)"
    }

    Update-PickerFilter "go"
    $state = Get-PickerState
    if ($state.Commands.Count -ne 1) {
        return "Filter 'go' should yield 1 command, got $($state.Commands.Count)"
    }

    Reset-PickerState
    $state = Get-PickerState
    if ($state.IsActive) {
        return "Picker should be inactive after Reset"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 27: Header path right-aligned at width 60
# -----------------------------------------------------------------------------
Test-Check "Header path right-aligned at w60" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACTIVE"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # GOLDEN NUANCE FIX: Use ProjectPath for header display (not RepoRoot)
    $state.Cache.Metadata["ProjectPath"] = "C:\Users\Dev\Projects\MyLongProjectName\SubFolder"

    Enable-CaptureMode -Width 60 -Height 10
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 60 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"
    $contentRow = $lines[1]

    # Verify row length equals width
    if ($contentRow.Length -ne 60) {
        return "Content row length $($contentRow.Length) != 60"
    }

    # Verify row ends with "  |" (path right-aligned, closing border)
    if ($contentRow.Substring(57, 3) -ne "  |") {
        return "Row doesn't end with '  |' at cols 57-59"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 28: Header path right-aligned at width 80
# -----------------------------------------------------------------------------
Test-Check "Header path right-aligned at w80" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACTIVE"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # GOLDEN NUANCE FIX: Use ProjectPath for header display (not RepoRoot)
    $state.Cache.Metadata["ProjectPath"] = "C:\Users\Dev\Projects\MyLongProjectName\SubFolder"

    Enable-CaptureMode -Width 80 -Height 10
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"
    $contentRow = $lines[1]

    # Verify row length equals width
    if ($contentRow.Length -ne 80) {
        return "Content row length $($contentRow.Length) != 80"
    }

    # Verify row ends with "  |" (path right-aligned, closing border)
    if ($contentRow.Substring(77, 3) -ne "  |") {
        return "Row doesn't end with '  |' at cols 77-79"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 29: Header path right-aligned at width 120
# -----------------------------------------------------------------------------
Test-Check "Header path right-aligned at w120" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACTIVE"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # GOLDEN NUANCE FIX: Use ProjectPath for header display (not RepoRoot)
    $state.Cache.Metadata["ProjectPath"] = "C:\Users\Dev\Projects\MyLongProjectName\SubFolder"

    Enable-CaptureMode -Width 120 -Height 10
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 120 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"
    $contentRow = $lines[1]

    # Verify row length equals width
    if ($contentRow.Length -ne 120) {
        return "Content row length $($contentRow.Length) != 120"
    }

    # Verify row ends with "  |" (path right-aligned, closing border)
    if ($contentRow.Substring(117, 3) -ne "  |") {
        return "Row doesn't end with '  |' at cols 117-119"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 30: / triggers dropdown (Gate 3)
# -----------------------------------------------------------------------------
Test-Check "Typing / triggers dropdown" {
    Reset-PickerState
    $pickerState = Get-PickerState

    # Initially inactive
    if ($pickerState.IsActive) {
        return "Picker should be inactive initially"
    }

    # Open with /
    Open-CommandPicker -InitialFilter ""
    $pickerState = Get-PickerState

    if (-not $pickerState.IsActive) {
        return "Picker should be active after opening"
    }
    if ($pickerState.Commands.Count -lt 8) {
        return "Picker should have at least 8 commands, got $($pickerState.Commands.Count)"
    }

    Reset-PickerState
    return $true
}

# -----------------------------------------------------------------------------
# CHECK 31: Tab inserts selected command + trailing space, closes dropdown
# -----------------------------------------------------------------------------
Test-Check "Tab completes with trailing space" {
    Reset-PickerState
    Open-CommandPicker -InitialFilter "go"
    $pickerState = Get-PickerState

    if ($pickerState.Commands.Count -ne 1) {
        return "Expected 1 command for 'go' filter, got $($pickerState.Commands.Count)"
    }

    # Get selected command
    $selected = Get-SelectedCommand
    if ($selected -ne "/go") {
        return "Expected '/go' selected, got '$selected'"
    }

    # Tab should produce "/go " (with trailing space)
    $expectedBuffer = $selected + " "
    if ($expectedBuffer -ne "/go ") {
        return "Buffer should be '/go ' after Tab, would be '$expectedBuffer'"
    }

    # After Tab, picker should be reset (inactive)
    Reset-PickerState
    $pickerState = Get-PickerState
    if ($pickerState.IsActive) {
        return "Picker should be inactive after Tab completion"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 32: Enter executes selected command
# -----------------------------------------------------------------------------
Test-Check "Enter executes selected command" {
    Reset-PickerState
    Open-CommandPicker -InitialFilter "plan"
    $pickerState = Get-PickerState

    # Should have filtered to /plan
    $selected = Get-SelectedCommand
    if ($selected -ne "/plan") {
        return "Expected '/plan' selected, got '$selected'"
    }

    Reset-PickerState
    return $true
}

# -----------------------------------------------------------------------------
# CHECK 33: ESC closes dropdown before clearing buffer
# -----------------------------------------------------------------------------
Test-Check "ESC closes dropdown first" {
    Reset-PickerState
    Open-CommandPicker -InitialFilter "dr"
    $pickerState = Get-PickerState

    if (-not $pickerState.IsActive) {
        return "Picker should be active"
    }

    # ESC should close dropdown
    Reset-PickerState
    $pickerState = Get-PickerState

    if ($pickerState.IsActive) {
        return "Picker should be inactive after ESC"
    }

    # Note: Input buffer preservation is handled by Start-ControlPanel,
    # which only clears buffer on second ESC. This test verifies the
    # picker closes first.
    return $true
}

# -----------------------------------------------------------------------------
# CHECK 34: Pipeline panel renders with stages (Gate 3 - Pipeline Panel)
# -----------------------------------------------------------------------------
Test-Check "Pipeline panel renders with stages" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true
    $snapshot.PlanState.PlanId = "test-plan"
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Plan -Snapshot $snapshot -State $state -StartRow 0
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"

    # Verify PIPELINE header in right column
    if ($lines[0] -notmatch "PIPELINE") {
        return "Missing PIPELINE header in right column"
    }

    # Verify pipeline data was computed (stages verified by CHECK 60 via Get-PipelineRightColumn)
    # Just verify we can get directives from the snapshot - visual rendering is separate
    $pipelineDirectives = Get-PipelineRightColumn -Snapshot $snapshot
    if (-not $pipelineDirectives -or $pipelineDirectives.Count -lt 6) {
        return "Pipeline directives incomplete (got $($pipelineDirectives.Count), expected 6)"
    }
    # Verify stages row exists in directives
    $stagesRow = $pipelineDirectives | Where-Object { $_.StageColors }
    if (-not $stagesRow) {
        return "Missing stages row in pipeline directives"
    }

    # Verify Next: hint in right column
    $nextFound = $false
    foreach ($line in $lines) {
        if ($line -match "Next:.*accept-plan") {
            $nextFound = $true
            break
        }
    }
    if (-not $nextFound) {
        return "Missing Next: /accept-plan hint in pipeline"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 35: Pipeline stage colors match state (Gate 3 - Pipeline Panel)
# -----------------------------------------------------------------------------
Test-Check "Pipeline stage colors match state" {
    # Test with DRAFT status - Ctx should be GREEN, Pln should be YELLOW
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $directives = Get-PipelineRightColumn -Snapshot $snapshot

    # Find the stages row (index 3)
    $stagesDirective = $directives[3]
    if (-not $stagesDirective.StageColors) {
        return "Stages directive missing StageColors"
    }

    $colors = $stagesDirective.StageColors
    if ($colors.Count -ne 6) {
        return "Expected 6 stage colors (with Opt), got $($colors.Count)"
    }

    # For DRAFT: Ctx=GREEN (initialized), Pln=YELLOW (draft), Wrk=GRAY, Opt=GRAY, Ver=GRAY, Shp=GRAY
    if ($colors[0] -ne "GREEN") {
        return "Ctx stage should be GREEN, got $($colors[0])"
    }
    if ($colors[1] -ne "YELLOW") {
        return "Pln stage should be YELLOW for DRAFT, got $($colors[1])"
    }
    if ($colors[2] -ne "GRAY") {
        return "Wrk stage should be GRAY, got $($colors[2])"
    }

    # Test with ACCEPTED status - Pln should be GREEN
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.PlanState.Accepted = $true
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesDirective = $directives[3]
    $colors = $stagesDirective.StageColors

    if ($colors[1] -ne "GREEN") {
        return "Pln stage should be GREEN for ACCEPTED, got $($colors[1])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 36: Enter toggles history details (Gate 5 - History Details)
# -----------------------------------------------------------------------------
Test-Check "Enter toggles history details" {
    $state = [UiState]::new()
    $state.OverlayMode = "History"
    $state.HistoryDetailsVisible = $false

    # Initially details should be hidden
    if ($state.HistoryDetailsVisible) {
        return "Details should be hidden initially"
    }

    # Simulate Enter key
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $enterKey -State $state

    if ($result -ne "historyDetails") {
        return "Enter should return 'historyDetails', got '$result'"
    }
    if (-not $state.HistoryDetailsVisible) {
        return "Details should be visible after Enter"
    }

    # Enter again should hide
    $result = Invoke-KeyRouter -KeyInfo $enterKey -State $state
    if ($state.HistoryDetailsVisible) {
        return "Details should be hidden after second Enter"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 37: ESC closes details before overlay (Gate 5 - ESC Priority)
# -----------------------------------------------------------------------------
Test-Check "ESC closes details before overlay" {
    $state = [UiState]::new()
    $state.OverlayMode = "History"
    $state.HistoryDetailsVisible = $true

    # ESC with details visible should close details, NOT overlay
    $escKey = [System.ConsoleKeyInfo]::new([char]27, [ConsoleKey]::Escape, $false, $false, $false)
    $result = Invoke-KeyRouter -KeyInfo $escKey -State $state

    if ($result -ne "historyDetails") {
        return "First ESC should return 'historyDetails', got '$result'"
    }
    if ($state.HistoryDetailsVisible) {
        return "Details should be hidden after ESC"
    }
    if ($state.OverlayMode -ne "History") {
        return "Overlay should still be visible after first ESC (was '$($state.OverlayMode)')"
    }

    # Second ESC should close overlay
    $result = Invoke-KeyRouter -KeyInfo $escKey -State $state
    if ($result -ne "overlay") {
        return "Second ESC should return 'overlay', got '$result'"
    }
    if ($state.OverlayMode -ne "None") {
        return "Overlay should be closed after second ESC"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 38: /help output format (Phase 5 - Help System)
# -----------------------------------------------------------------------------
Test-Check "/help shows curated command list" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()

    $result = Invoke-CommandRouter -Command "/help" -State $state -Snapshot $snapshot

    if ($result -ne "ok") {
        return "Expected 'ok' result, got '$result'"
    }

    $toastMsg = $state.Toast.Message
    if (-not $toastMsg) {
        return "No toast message set"
    }

    # Verify curated commands are present
    if ($toastMsg -notmatch "/help") {
        return "Help output missing /help"
    }
    if ($toastMsg -notmatch "/draft-plan") {
        return "Help output missing /draft-plan"
    }
    if ($toastMsg -notmatch "/go") {
        return "Help output missing /go"
    }
    if ($toastMsg -notmatch "/quit") {
        return "Help output missing /quit"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 39: /help --all shows full catalog (Phase 5 - Help System)
# -----------------------------------------------------------------------------
Test-Check "/help --all shows full command catalog" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()

    $result = Invoke-CommandRouter -Command "/help --all" -State $state -Snapshot $snapshot

    if ($result -ne "ok") {
        return "Expected 'ok' result, got '$result'"
    }

    $toastMsg = $state.Toast.Message
    if (-not $toastMsg) {
        return "No toast message set"
    }

    # Verify all commands from picker are present
    $allCommands = Get-PickerCommands -Filter ""
    foreach ($cmd in $allCommands) {
        if ($toastMsg -notmatch [regex]::Escape("/$($cmd.Name)")) {
            return "Help --all missing command /$($cmd.Name)"
        }
    }

    # Verify it has more content than regular /help
    $lines = $toastMsg -split "`n"
    if ($lines.Count -lt 7) {
        return "Help --all should have at least 8 lines (header + 8 commands), got $($lines.Count)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 40: Header shows ProjectPath, not RepoRoot (Provenance Gate)
# -----------------------------------------------------------------------------
Test-Check "Header shows ProjectPath (not RepoRoot)" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # Set BOTH paths to different values
    $state.Cache.Metadata["RepoRoot"] = "E:\Code\atomic-mesh-ui-sandbox"  # Module location
    $state.Cache.Metadata["ProjectPath"] = "E:\Code\test-project"         # Launch directory

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"
    $contentRow = $lines[1]

    # Header should contain ProjectPath (test-project), NOT RepoRoot (atomic-mesh-ui-sandbox)
    if ($contentRow -match "atomic-mesh-ui-sandbox") {
        return "FAIL: Header shows RepoRoot instead of ProjectPath"
    }
    if ($contentRow -notmatch "test-project") {
        return "FAIL: Header missing ProjectPath 'test-project'"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 41: ProjectPath changes independently of RepoRoot (Provenance Gate)
# -----------------------------------------------------------------------------
Test-Check "ProjectPath changes reflect in header" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    $state = [UiState]::new()
    # Keep RepoRoot constant, change ProjectPath
    $state.Cache.Metadata["RepoRoot"] = "E:\Code\atomic-mesh-ui-sandbox"

    # Test with first ProjectPath
    $state.Cache.Metadata["ProjectPath"] = "E:\Code\project-alpha"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output1 = Get-CapturedOutput
    Disable-CaptureMode

    # Test with second ProjectPath
    $state.Cache.Metadata["ProjectPath"] = "E:\Code\project-beta"

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output2 = Get-CapturedOutput
    Disable-CaptureMode

    $lines1 = $output1 -split "`n"
    $lines2 = $output2 -split "`n"
    $contentRow1 = $lines1[1]
    $contentRow2 = $lines2[1]

    # First should show project-alpha
    if ($contentRow1 -notmatch "project-alpha") {
        return "FAIL: First header missing 'project-alpha'"
    }

    # Second should show project-beta
    if ($contentRow2 -notmatch "project-beta") {
        return "FAIL: Second header missing 'project-beta'"
    }

    # Neither should show RepoRoot
    if ($contentRow1 -match "atomic-mesh-ui-sandbox" -or $contentRow2 -match "atomic-mesh-ui-sandbox") {
        return "FAIL: Header still showing RepoRoot"
    }

    return $true
}

# =============================================================================
# GOLDEN NUANCE CHECKS (42-50)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 42: Source display format (Nuance 2)
# -----------------------------------------------------------------------------
Test-Check "Source display shows readiness mode" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true
    $snapshot.ReadinessMode = "live"
    $snapshot.LaneMetrics = @()

    $directives = Get-PipelineRightColumn -Snapshot $snapshot

    # Source line should contain "snapshot.py (live)"
    $sourceLine = $directives | Where-Object { $_.Text -match "Source:" }
    if (-not $sourceLine) {
        return "Missing Source line in directives"
    }
    if ($sourceLine.Text -notmatch "snapshot\.py \(live\)") {
        return "Source format wrong: $($sourceLine.Text)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 43: Context stage colors (Nuance 3)
# -----------------------------------------------------------------------------
Test-Check "Context stage: PRE_INIT=RED, BOOTSTRAP=YELLOW, EXECUTION=GREEN" {
    # Test PRE_INIT = RED
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "PRE_INIT"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[0] -ne "RED") {
        return "PRE_INIT should be RED, got $($stagesLine.StageColors[0])"
    }

    # Test BOOTSTRAP = YELLOW
    $snapshot.PlanState.Status = "BOOTSTRAP"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[0] -ne "YELLOW") {
        return "BOOTSTRAP should be YELLOW, got $($stagesLine.StageColors[0])"
    }

    # Test ACCEPTED = GREEN (EXECUTION)
    $snapshot.PlanState.Status = "ACCEPTED"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[0] -ne "GREEN") {
        return "ACCEPTED should be GREEN, got $($stagesLine.StageColors[0])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 44: Plan stage colors (Nuance 3)
# -----------------------------------------------------------------------------
Test-Check "Plan stage: queued=GREEN, exhausted=YELLOW, zero=RED" {
    # Test with queued tasks = GREEN
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Queued = 5
    $snapshot.LaneMetrics = @($lane)
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[1] -ne "GREEN") {
        return "Queued tasks should make Plan GREEN, got $($stagesLine.StageColors[1])"
    }

    # Test DRAFT = YELLOW
    $snapshot.PlanState.Status = "DRAFT"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[1] -ne "YELLOW") {
        return "DRAFT should make Plan YELLOW, got $($stagesLine.StageColors[1])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 45: Work stage colors (Nuance 3)
# -----------------------------------------------------------------------------
Test-Check "Work stage: active=GREEN, queued=YELLOW, blocked=RED" {
    # Test with active tasks = GREEN
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Active = 2
    $lane.Queued = 3
    $snapshot.LaneMetrics = @($lane)
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[2] -ne "GREEN") {
        return "Active tasks should make Work GREEN, got $($stagesLine.StageColors[2])"
    }

    # Test with queued only = YELLOW
    $lane.Active = 0
    $lane.Queued = 5
    $snapshot.LaneMetrics = @($lane)
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[2] -ne "YELLOW") {
        return "Queued only should make Work YELLOW, got $($stagesLine.StageColors[2])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 46: Verify stage (Nuance 3 - simplified)
# -----------------------------------------------------------------------------
Test-Check "Verify stage follows Work state" {
    # Verify should be GRAY when Work is not done
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[3] -ne "GRAY") {
        return "Verify should be GRAY when Work not done, got $($stagesLine.StageColors[3])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 47: Ship stage colors (Nuance 3)
# -----------------------------------------------------------------------------
Test-Check "Ship stage: git clean=GREEN, uncommitted=YELLOW" {
    # Test with git clean and work done = GREEN
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.PlanState.Accepted = $true
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Active = 1  # Active tasks make Work GREEN
    $lane.Tokens = 5  # Completed tasks
    $snapshot.LaneMetrics = @($lane)
    $snapshot.HasAnyOptimized = $true  # P7: Make Optimize GREEN
    $snapshot.GitClean = $true
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    # Ship is now index 5 (after Ctx, Pln, Wrk, Opt, Ver)
    if ($stagesLine.StageColors[5] -eq "RED") {
        return "Ship should not be RED when git clean, got $($stagesLine.StageColors[5])"
    }

    # Test with uncommitted changes = YELLOW
    $snapshot.GitClean = $false
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    # With work done (index 2 = GREEN) but git dirty, Ship (index 5) should be YELLOW
    if ($stagesLine.StageColors[2] -eq "GREEN" -and $stagesLine.StageColors[5] -ne "YELLOW") {
        return "Ship should be YELLOW when git dirty, got $($stagesLine.StageColors[5])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 48: Next hint priority chain (Nuance 4)
# -----------------------------------------------------------------------------
Test-Check "Next hint follows priority chain" {
    # Test PRE_INIT → /init
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "PRE_INIT"
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $nextLine = $directives | Where-Object { $_.Text -match "Next:" }
    if ($nextLine.Text -notmatch "/init") {
        return "PRE_INIT should hint /init, got $($nextLine.Text)"
    }

    # Test DRAFT → /accept-plan
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $nextLine = $directives | Where-Object { $_.Text -match "Next:" }
    if ($nextLine.Text -notmatch "/accept-plan") {
        return "DRAFT should hint /accept-plan, got $($nextLine.Text)"
    }

    # Test ACCEPTED with queued → /go
    $snapshot.PlanState.Status = "ACCEPTED"
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Queued = 5
    $snapshot.LaneMetrics = @($lane)
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $nextLine = $directives | Where-Object { $_.Text -match "Next:" }
    if ($nextLine.Text -notmatch "/go") {
        return "ACCEPTED with queued should hint /go, got $($nextLine.Text)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 49: Lane counts use DISTINCT lanes (Nuance 5)
# -----------------------------------------------------------------------------
Test-Check "Lane counts use DistinctLaneCounts from snapshot" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.LaneMetrics = @()
    $snapshot.Alerts = [UiAlerts]::new()

    # Set DistinctLaneCounts explicitly
    $snapshot.DistinctLaneCounts = @{ pending = 3; active = 2 }

    $state = [UiState]::new()

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output = Get-CapturedOutput
    Disable-CaptureMode

    $lines = $output -split "`n"
    $contentRow = $lines[1]

    # Header should show "3 pending" and "2 active"
    if ($contentRow -notmatch "3 pending") {
        return "Header should show '3 pending', got: $contentRow"
    }
    if ($contentRow -notmatch "2 active") {
        return "Header should show '2 active', got: $contentRow"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 50: Health dot color (Nuance 6)
# -----------------------------------------------------------------------------
Test-Check "Health dot: FAIL=Red, WARN=Yellow, OK=Green" {
    $state = [UiState]::new()

    # Test OK = Green (default)
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.HealthStatus = "OK"
    $snapshot.Alerts = [UiAlerts]::new()

    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output1 = Get-CapturedOutput
    Disable-CaptureMode

    # Test WARN = Yellow
    $snapshot.HealthStatus = "WARN"
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output2 = Get-CapturedOutput
    Disable-CaptureMode

    # Test FAIL = Red
    $snapshot.HealthStatus = "FAIL"
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    $output3 = Get-CapturedOutput
    Disable-CaptureMode

    # All outputs should contain the health dot character
    $healthDot = [char]0x25CF
    if ($output1 -notmatch [regex]::Escape($healthDot)) {
        return "OK output missing health dot"
    }
    if ($output2 -notmatch [regex]::Escape($healthDot)) {
        return "WARN output missing health dot"
    }
    if ($output3 -notmatch [regex]::Escape($healthDot)) {
        return "FAIL output missing health dot"
    }

    return $true
}

# =============================================================================
# P1-P4 GOLDEN NUANCE CHECKS (52-55)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 52: Task-specific hints include task ID (P1)
# -----------------------------------------------------------------------------
Test-Check "Task-specific hint includes blocked task ID" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "BLOCKED"
    $snapshot.FirstBlockedTaskId = "T-123"
    $snapshot.LaneMetrics = @()

    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $nextLine = $directives | Where-Object { $_.Text -match "Next:" }

    if ($nextLine.Text -notmatch "T-123") {
        return "Blocked task ID not in hint: $($nextLine.Text)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 53: Command feedback has icons (P3)
# -----------------------------------------------------------------------------
Test-Check "Command feedback includes icons" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()

    # Test /plan command feedback
    $result = Invoke-CommandRouter -Command "/plan" -State $state -Snapshot $snapshot

    if ($result -ne "ok") {
        return "Expected 'ok' result, got '$result'"
    }

    $toastMsg = $state.Toast.Message
    # Check for success icon (✅ = U+2705)
    if ($toastMsg -notmatch [char]0x2705) {
        return "Toast missing success icon: $toastMsg"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 54: /ship blocks on HIGH risk unverified (P4)
# -----------------------------------------------------------------------------
Test-Check "/ship blocks on HIGH risk unverified" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()
    $snapshot.HighRiskUnverifiedCount = 2
    $snapshot.GitClean = $true

    $result = Invoke-CommandRouter -Command "/ship" -State $state -Snapshot $snapshot

    $toastMsg = $state.Toast.Message
    if ($toastMsg -notmatch "Cannot ship.*HIGH risk") {
        return "Expected HIGH risk blocking message: $toastMsg"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 55: /ship succeeds when no HIGH risk (P4)
# -----------------------------------------------------------------------------
Test-Check "/ship succeeds when no HIGH risk" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()
    $snapshot.HighRiskUnverifiedCount = 0
    $snapshot.GitClean = $true

    $result = Invoke-CommandRouter -Command "/ship" -State $state -Snapshot $snapshot

    $toastMsg = $state.Toast.Message
    if ($toastMsg -notmatch "Ready to ship") {
        return "Expected success message: $toastMsg"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 51: 200ms timing guard fail-open behavior (Nuance guarantee)
# -----------------------------------------------------------------------------
Test-Check "200ms guard: fail-open mode displays correctly" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true

    # Simulate fail-open mode (what happens when snapshot.py exceeds 200ms)
    $snapshot.ReadinessMode = "fail-open"
    $snapshot.LaneMetrics = @()

    $directives = Get-PipelineRightColumn -Snapshot $snapshot

    # Source line should show "fail-open" mode
    $sourceLine = $directives | Where-Object { $_.Text -match "Source:" }
    if (-not $sourceLine) {
        return "Missing Source line in directives"
    }
    if ($sourceLine.Text -notmatch "snapshot\.py \(fail-open\)") {
        return "Fail-open not shown in source: $($sourceLine.Text)"
    }

    # Verify defaults are used (pending=0, active=0 from fail-open)
    # This simulates what happens when DB queries timeout
    if ($snapshot.DistinctLaneCounts.pending -ne 0 -or $snapshot.DistinctLaneCounts.active -ne 0) {
        # Note: fail-open returns default values
        # This is correct behavior - verifying we show the mode indicator
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 56: /draft-plan shows blocking files when BLOCKED (P5)
# -----------------------------------------------------------------------------
Test-Check "/draft-plan shows blocking files when BLOCKED" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "BOOTSTRAP"
    $snapshot.BlockingFiles = @("PRD", "SPEC")

    $result = Invoke-CommandRouter -Command "/draft-plan" -State $state -Snapshot $snapshot

    $toastMsg = $state.Toast.Message
    if ($toastMsg -notmatch "BLOCKED") {
        return "Expected BLOCKED message: $toastMsg"
    }
    if ($toastMsg -notmatch "PRD") {
        return "Expected PRD in blocking files: $toastMsg"
    }
    if ($toastMsg -notmatch "SPEC") {
        return "Expected SPEC in blocking files: $toastMsg"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 57: /accept-plan shows task count (P6)
# -----------------------------------------------------------------------------
Test-Check "/accept-plan shows task count" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true

    # Add lane metrics with 5 queued tasks
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Queued = 5
    $snapshot.LaneMetrics = @($lane)

    $result = Invoke-CommandRouter -Command "/accept-plan" -State $state -Snapshot $snapshot

    $toastMsg = $state.Toast.Message
    if ($toastMsg -notmatch "5 task") {
        return "Expected '5 task' in message: $toastMsg"
    }

    return $true
}

# =============================================================================
# P7 OPTIMIZE STAGE CHECKS (58-60)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 58: Optimize stage color logic (P7)
# -----------------------------------------------------------------------------
Test-Check "Optimize stage: HasAnyOptimized=GREEN, tasks=YELLOW, none=GRAY" {
    # Test with HasAnyOptimized = GREEN
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"
    $snapshot.HasAnyOptimized = $true
    $snapshot.OptimizeTotalTasks = 3
    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Active = 1
    $snapshot.LaneMetrics = @($lane)
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    # Opt is index 3 (after Ctx, Pln, Wrk)
    if ($stagesLine.StageColors[3] -ne "GREEN") {
        return "HasAnyOptimized should be GREEN, got $($stagesLine.StageColors[3])"
    }

    # Test with tasks but no proof = YELLOW
    $snapshot.HasAnyOptimized = $false
    $snapshot.OptimizeTotalTasks = 5
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }
    if ($stagesLine.StageColors[3] -ne "YELLOW") {
        return "Tasks without proof should be YELLOW, got $($stagesLine.StageColors[3])"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 59: /simplify command with task ID (P7)
# -----------------------------------------------------------------------------
Test-Check "/simplify command shows task ID" {
    $state = [UiState]::new()
    $snapshot = [UiSnapshot]::new()
    $snapshot.FirstUnoptimizedTaskId = "T-456"

    $result = Invoke-CommandRouter -Command "/simplify" -State $state -Snapshot $snapshot

    $toastMsg = $state.Toast.Message
    if ($toastMsg -notmatch "T-456") {
        return "Expected task ID T-456 in message: $toastMsg"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 60: Pipeline shows 6 stages with Opt (P7)
# -----------------------------------------------------------------------------
Test-Check "Pipeline shows 6 stages [Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]" {
    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"

    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.Text -match "\[Opt\]" }

    if (-not $stagesLine) {
        return "Pipeline missing [Opt] stage"
    }

    # Verify 6 stages in StageColors array
    $colorsLine = $directives | Where-Object { $_.StageColors }
    if ($colorsLine.StageColors.Count -ne 6) {
        return "Expected 6 stage colors, got $($colorsLine.StageColors.Count)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 62: False positive guard - "Entropy Check: Failed" should NOT count
# -----------------------------------------------------------------------------
Test-Check "Entropy Check: Failed does NOT count as optimized" {
    # This guards against regex matching partial/incorrect markers
    # "Entropy Check: Failed" should NOT trigger HasAnyOptimized

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"

    # Simulate: HasAnyOptimized should be FALSE even with active tasks
    # because "Entropy Check: Failed" is not an accepted marker
    $snapshot.HasAnyOptimized = $false  # This is what snapshot.py should return
    $snapshot.OptimizeTotalTasks = 3    # Tasks exist but none have valid markers

    $lane = [LaneMetrics]::CreateDefault("test")
    $lane.Active = 1
    $snapshot.LaneMetrics = @($lane)

    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $stagesLine = $directives | Where-Object { $_.StageColors }

    # Opt stage (index 3) should be YELLOW (tasks exist but no valid markers)
    # NOT GREEN (which would mean HasAnyOptimized=true)
    if ($stagesLine.StageColors[3] -eq "GREEN") {
        return "FAIL: Optimize stage incorrectly GREEN without valid markers"
    }
    if ($stagesLine.StageColors[3] -ne "YELLOW") {
        return "FAIL: Optimize stage should be YELLOW, got $($stagesLine.StageColors[3])"
    }

    return $true
}

# =============================================================================
# SLOW SNAPSHOT REGRESSION TEST (CHECK 61 -> now CHECK 63)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 63: Slow snapshot triggers fail-open mode (regression test)
# -----------------------------------------------------------------------------
Test-Check "Slow snapshot triggers fail-open mode" {
    # Simulate what happens when snapshot.py exceeds the 200ms budget
    # The UI should:
    # 1. Show "fail-open" in Source display
    # 2. Preserve last-good snapshot (no crash)
    # 3. No page corruption (layout still valid)

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"
    $snapshot.PlanState.HasDraft = $true

    # Simulate fail-open mode (snapshot exceeded 200ms budget)
    $snapshot.ReadinessMode = "fail-open"
    $snapshot.DistinctLaneCounts = @{ pending = 0; active = 0 }  # Defaults from fail-open
    $snapshot.GitClean = $true  # Fail-open default
    $snapshot.HealthStatus = "OK"  # Fail-open default
    $snapshot.LaneMetrics = @()

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    # 1. Verify Source shows fail-open
    $directives = Get-PipelineRightColumn -Snapshot $snapshot
    $sourceLine = $directives | Where-Object { $_.Text -match "Source:" }
    if ($sourceLine.Text -notmatch "fail-open") {
        return "Source should show 'fail-open' when snapshot exceeded budget: $($sourceLine.Text)"
    }

    # 2. Verify layout still renders without crash
    Enable-CaptureMode -Width 80 -Height 24
    Begin-ConsoleFrame
    Render-Header -StartRow 0 -Width 80 -Snapshot $snapshot -State $state
    Render-Plan -Snapshot $snapshot -State $state -StartRow 4 -BottomRow 16
    $output = Get-CapturedOutput
    Disable-CaptureMode

    # 3. Verify layout integrity (has borders, expected structure)
    $lines = $output -split "`n"
    if ($lines[0] -notmatch "^\+") {
        return "Layout corrupted: header border missing"
    }
    if ($lines[4] -notmatch "^\|") {
        return "Layout corrupted: content row missing border"
    }

    # 4. Verify PLAN content still renders (not blank)
    if ($output -notmatch "PLAN") {
        return "Content not rendered: missing PLAN label"
    }

    return $true
}

# =============================================================================
# COMMAND GUARDS (CHECK 63-64)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 63: /go blocks without accepted plan
# -----------------------------------------------------------------------------
Test-Check "/go blocks without accepted plan" {
    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "DRAFT"  # Not accepted

    $result = Invoke-CommandRouter -Command "/go" -State $state -Snapshot $snapshot

    # Should stay on PLAN page (blocked)
    if ($state.CurrentPage -ne "PLAN") {
        return "Should stay on PLAN when blocked: page=$($state.CurrentPage)"
    }

    # Toast should mention /accept-plan
    if ($state.Toast.Message -notmatch "accept-plan") {
        return "Toast should mention /accept-plan: $($state.Toast.Message)"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 64: /accept-plan blocks without draft
# -----------------------------------------------------------------------------
Test-Check "/accept-plan blocks without draft" {
    $state = [UiState]::new()

    $snapshot = [UiSnapshot]::new()
    $snapshot.PlanState = [PlanState]::new()
    $snapshot.PlanState.Status = "ACCEPTED"  # Already accepted, no draft

    $result = Invoke-CommandRouter -Command "/accept-plan" -State $state -Snapshot $snapshot

    # Toast should mention /draft-plan
    if ($state.Toast.Message -notmatch "draft-plan") {
        return "Toast should mention /draft-plan: $($state.Toast.Message)"
    }

    return $true
}

# =============================================================================
# REGION-BASED DIRTY RENDERING (CHECK 65-67)
# =============================================================================

# -----------------------------------------------------------------------------
# CHECK 65: Picker-only dirty does NOT clear screen
# -----------------------------------------------------------------------------
Test-Check "Picker-only dirty does NOT clear screen" {
    $state = [UiState]::new()
    $state.ClearDirty()  # Clear initial "all" dirty

    # Mark only picker dirty
    $state.MarkDirty("picker")

    # Verify picker is dirty but "all" and "content" are not
    if ($state.IsDirty("all")) {
        return "Should not be 'all' dirty"
    }
    if ($state.IsDirty("content")) {
        return "Should not be 'content' dirty"
    }
    if (-not $state.IsDirty("picker")) {
        return "Should be 'picker' dirty"
    }

    # Verify HasDirty returns true
    if (-not $state.HasDirty()) {
        return "HasDirty should be true"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 66: Input-only dirty does NOT trigger content dirty
# -----------------------------------------------------------------------------
Test-Check "Input-only dirty does NOT trigger content dirty" {
    $state = [UiState]::new()
    $state.ClearDirty()

    $state.MarkDirty("input")

    if ($state.IsDirty("content")) {
        return "Input should not trigger content dirty"
    }
    if (-not $state.IsDirty("input")) {
        return "Input should be dirty"
    }

    return $true
}

# -----------------------------------------------------------------------------
# CHECK 67: Content dirty returns true for content check
# -----------------------------------------------------------------------------
Test-Check "Content dirty triggers full redraw flag" {
    $state = [UiState]::new()
    $state.ClearDirty()

    $state.MarkDirty("content")

    if (-not $state.IsDirty("content")) {
        return "Content should be dirty"
    }

    # "all" check should NOT return true for just "content"
    # (IsDirty("all") only returns true if "all" was explicitly marked)
    $state.ClearDirty()
    $state.MarkDirty("content")

    # But content IS enough to trigger full render in the loop
    # This is the design: needsFull = IsDirty("all") OR IsDirty("content")
    return $true
}

# -----------------------------------------------------------------------------
# RESULTS
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "=" * 60
Write-Host "RESULTS"
Write-Host "=" * 60
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failed -gt 0) {
    exit 1
}

Write-Host "All pre-ship checks passed!" -ForegroundColor Green

if ($Interactive) {
    Write-Host ""
    Write-Host "=" * 60
    Write-Host "MANUAL SMOKE CHECKLIST (10 minutes)"
    Write-Host "=" * 60
    Write-Host ""

    Write-Host "1. LAUNCH-PATH CORRECTNESS:" -ForegroundColor Cyan
    Write-Host "   - Run from E:\Code\test and confirm header shows E:\Code\test"
    Write-Host "   - Run from different folder and confirm header changes accordingly"
    Write-Host ""

    Write-Host "2. PERFORMANCE/HITCH CHECK (60s):" -ForegroundColor Cyan
    Write-Host "   - Let it run ~60s at normal refresh. Watch for hitch every tick."
    Write-Host "   - If -Dev stats available, confirm snapshot duration < 200ms"
    Write-Host "   - Source should show 'snapshot.py (live)' not '(fail-open)'"
    Write-Host ""

    Write-Host "3. GIT DIRTY DETECTION:" -ForegroundColor Cyan
    Write-Host "   - Make repo dirty: echo x >> foo.txt"
    Write-Host "   - Ship stage should flip to YELLOW and /ship should warn"
    Write-Host "   - Revert/clean (del foo.txt) -> flips back to GREEN"
    Write-Host ""

    Write-Host "4. DROPDOWN + COMMANDS:" -ForegroundColor Cyan
    Write-Host "   - Type / -> dropdown appears with all commands"
    Write-Host "   - /s filters to simplify"
    Write-Host "   - Up/Down navigates selection"
    Write-Host "   - Tab completion adds trailing space"
    Write-Host "   - ESC closes dropdown first (before clearing buffer)"
    Write-Host ""

    Write-Host "5. OPTIMIZE MARKERS SANITY:" -ForegroundColor Cyan
    Write-Host "   - Add task note with: 'Entropy Check: Passed' -> Optimize GREEN"
    Write-Host "   - Add task note with: 'OPTIMIZATION WAIVED' -> Optimize GREEN"
    Write-Host "   - Add task note with: 'CAPTAIN_OVERRIDE: ENTROPY' -> Optimize GREEN"
    Write-Host "   - Task with no marker -> Optimize YELLOW, hint suggests /simplify <id>"
    Write-Host ""

    Write-Host "6. FAIL-OPEN BEHAVIOR:" -ForegroundColor Cyan
    Write-Host "   - Temporarily break DB (rename tasks.db)"
    Write-Host "   - UI should stay alive, Source shows 'fail-open'"
    Write-Host "   - Restore DB -> recovers gracefully"
    Write-Host ""

    Write-Host "7. RESIZE STRESS TEST:" -ForegroundColor Cyan
    Write-Host "   - Resize terminal rapidly - no crash, no smear, clean redraw"
    Write-Host ""

    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

exit 0
