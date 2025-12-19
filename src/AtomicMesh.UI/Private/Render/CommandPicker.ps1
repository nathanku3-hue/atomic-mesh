# =============================================================================
# GOLDEN TRANSPLANT: Command Picker (lines 9639-9920)
# Source: golden_control_panel_reference.ps1 commit 6990922
# =============================================================================

# Command registry with descriptions (from golden Global:Commands)
$script:CommandRegistry = @{
    "help"        = @{ Desc = "Show available commands" }
    "plan"        = @{ Desc = "Switch to PLAN page" }
    "go"          = @{ Desc = "Start execution (switch to GO page)" }
    "draft-plan"  = @{ Desc = "Create a new plan draft" }
    "accept-plan" = @{ Desc = "Accept the current plan draft" }
    "status"      = @{ Desc = "Show current status" }
    "simplify"    = @{ Desc = "Simplify task (add entropy proof)" }  # P7: Optimize stage
    "ship"        = @{ Desc = "Ship completed work (blocks on HIGH risk)" }
    "clear"       = @{ Desc = "Clear event log and toast" }
    "quit"        = @{ Desc = "Exit the control panel" }
}

# =============================================================================
# GOLDEN TRANSPLANT: Get-PickerCommands (lines 1052-1106)
# Returns flat list of commands for inline picker
# =============================================================================
function Get-PickerCommands {
    [OutputType([array])]
    param([string]$Filter = "")

    # Priority order (from golden lines 1060-1071 + P7 simplify)
    $priorityOrder = @("help", "draft-plan", "accept-plan", "plan", "go", "simplify", "ship", "status", "clear", "quit")

    $filter = $Filter.TrimStart("/").ToLower()
    [array]$results = @()

    if ([string]::IsNullOrEmpty($filter)) {
        # No filter: return all in priority order
        foreach ($cmdName in $priorityOrder) {
            if ($script:CommandRegistry.ContainsKey($cmdName)) {
                $results += [PSCustomObject]@{
                    Name = $cmdName
                    Desc = $script:CommandRegistry[$cmdName].Desc
                }
            }
        }
    }
    else {
        # Filter: return matching commands
        foreach ($cmdName in $priorityOrder) {
            if ($cmdName.StartsWith($filter) -and $script:CommandRegistry.ContainsKey($cmdName)) {
                $results += [PSCustomObject]@{
                    Name = $cmdName
                    Desc = $script:CommandRegistry[$cmdName].Desc
                }
            }
        }
    }

    # IMPORTANT: Use comma operator to force array return even for single items
    # This prevents PowerShell's automatic unwrapping of single-element arrays
    return ,$results
}

# =============================================================================
# GOLDEN TRANSPLANT: Get-FilteredCommands (lines 1360-1382)
# Quick filter for commands starting with prefix
# =============================================================================
function Get-FilteredCommands {
    param([string]$Filter)

    $filter = $Filter.TrimStart("/").ToLower()
    $filtered = @()

    foreach ($cmdName in $script:CommandRegistry.Keys) {
        if ([string]::IsNullOrEmpty($filter) -or $cmdName.StartsWith($filter)) {
            $filtered += @{
                Name = $cmdName
                Desc = $script:CommandRegistry[$cmdName].Desc
            }
        }
    }

    return $filtered
}

# =============================================================================
# Command picker state
# =============================================================================
$script:PickerState = @{
    IsActive = $false
    Filter = ""
    SelectedIndex = 0
    ScrollOffset = 0
    Commands = @()
}

function Get-PickerState { return $script:PickerState }

function Reset-PickerState {
    $script:PickerState.IsActive = $false
    $script:PickerState.Filter = ""
    $script:PickerState.SelectedIndex = 0
    $script:PickerState.ScrollOffset = 0
    $script:PickerState.Commands = @()
}

function Open-CommandPicker {
    param([string]$InitialFilter = "")

    $script:PickerState.IsActive = $true
    $script:PickerState.Filter = $InitialFilter
    $script:PickerState.SelectedIndex = 0
    $script:PickerState.ScrollOffset = 0
    $script:PickerState.Commands = Get-PickerCommands -Filter $InitialFilter
}

function Update-PickerFilter {
    param([string]$Filter)

    $script:PickerState.Filter = $Filter
    $script:PickerState.SelectedIndex = 0
    $script:PickerState.ScrollOffset = 0
    $script:PickerState.Commands = Get-PickerCommands -Filter $Filter
}

function Navigate-PickerUp {
    if ($script:PickerState.SelectedIndex -gt 0) {
        $script:PickerState.SelectedIndex--
        if ($script:PickerState.SelectedIndex -lt $script:PickerState.ScrollOffset) {
            $script:PickerState.ScrollOffset = $script:PickerState.SelectedIndex
        }
    }
}

function Navigate-PickerDown {
    param([int]$MaxVisible = 5)

    $maxIdx = $script:PickerState.Commands.Count - 1
    if ($script:PickerState.SelectedIndex -lt $maxIdx) {
        $script:PickerState.SelectedIndex++
        if ($script:PickerState.SelectedIndex -ge ($script:PickerState.ScrollOffset + $MaxVisible)) {
            $script:PickerState.ScrollOffset++
        }
    }
}

function Get-SelectedCommand {
    if ($script:PickerState.Commands.Count -gt 0 -and
        $script:PickerState.SelectedIndex -lt $script:PickerState.Commands.Count) {
        return "/" + $script:PickerState.Commands[$script:PickerState.SelectedIndex].Name
    }
    return $null
}

# =============================================================================
# GOLDEN TRANSPLANT: Draw-CommandDropdown (lines 1384-1466)
# Render command dropdown below input box
# =============================================================================
function Render-CommandDropdown {
    param(
        [int]$StartRow,
        [int]$Width,
        [int]$MaxVisible = 5
    )

    if (-not (Get-ConsoleFrameValid)) { return }
    if (-not $script:PickerState.IsActive) { return }

    $commands = $script:PickerState.Commands
    $selectedIdx = $script:PickerState.SelectedIndex
    $scrollOffset = $script:PickerState.ScrollOffset
    $filter = $script:PickerState.Filter

    # Golden line 1392-1393: Two-column layout
    $colWidth = 38
    $numCols = 1  # Simplified to single column for now

    $R = $StartRow

    # Draw each visible command
    $visible = [Math]::Min($MaxVisible, $commands.Count)
    for ($i = 0; $i -lt $visible; $i++) {
        $cmdIdx = $scrollOffset + $i
        if ($cmdIdx -ge $commands.Count) { break }

        $cmd = $commands[$cmdIdx]
        $isSelected = ($cmdIdx -eq $selectedIdx)

        # Golden lines 1423-1437: Format command name and description
        $cmdName = ("/" + $cmd.Name).PadRight(14)
        $desc = $cmd.Desc
        if ($desc.Length -gt 30) { $desc = $desc.Substring(0, 27) + "..." }
        $desc = $desc.PadRight(30)

        if ($isSelected) {
            # Golden lines 1428-1431: Selected item styling
            TryWriteAt -Row $R -Col 2 -Text ">" -Color "Cyan" | Out-Null
            TryWriteAt -Row $R -Col 4 -Text $cmdName -Color "Yellow" | Out-Null
            TryWriteAt -Row $R -Col (4 + 14) -Text $desc -Color "White" | Out-Null
        }
        else {
            # Golden lines 1433-1436: Unselected item styling
            TryWriteAt -Row $R -Col 2 -Text " " -Color "White" | Out-Null
            TryWriteAt -Row $R -Col 4 -Text $cmdName -Color "DarkYellow" | Out-Null
            TryWriteAt -Row $R -Col (4 + 14) -Text $desc -Color "DarkGray" | Out-Null
        }

        $R++
    }

    # Golden lines 1452-1461: Scroll indicator
    if ($commands.Count -gt $MaxVisible) {
        $remaining = $commands.Count - $scrollOffset - $visible
        if ($remaining -gt 0) {
            $scrollHint = "  v $remaining more"
            TryWriteAt -Row $R -Col 2 -Text $scrollHint -Color "DarkGray" | Out-Null
        }
    }
}

# =============================================================================
# Clear dropdown area
# =============================================================================
function Clear-CommandDropdown {
    param(
        [int]$StartRow,
        [int]$Width,
        [int]$Lines = 6
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    for ($i = 0; $i -lt $Lines; $i++) {
        $row = $StartRow + $i
        TryWriteAt -Row $row -Col 0 -Text (" " * $Width) -Color "White" | Out-Null
    }
}

# =============================================================================
# Render-PickerArea: Partial redraw for picker region
# Clears old area when picker shrinks/closes, renders current state
# =============================================================================
function Render-PickerArea {
    param(
        $State,
        [int]$RowInput,
        [int]$Width
    )

    $dropdownRow = $RowInput + 2  # Below input box bottom border
    $pickerState = Get-PickerState
    $newHeight = 0

    if ($pickerState.IsActive) {
        $newHeight = [Math]::Min($pickerState.Commands.Count, 5)  # MaxVisible = 5
        if ($pickerState.Commands.Count -gt 5) { $newHeight++ }   # +1 for scroll hint
    }

    # Clear the maximum of old and new heights to remove stale entries
    $clearHeight = [Math]::Max($State.LastPickerHeight, $newHeight)
    if ($clearHeight -gt 0) {
        Clear-CommandDropdown -StartRow $dropdownRow -Width $Width -Lines ($clearHeight + 1)
    }

    # Render dropdown if active
    if ($pickerState.IsActive) {
        Render-CommandDropdown -StartRow $dropdownRow -Width $Width
    }

    # Update state for next partial render
    $State.LastPickerHeight = $newHeight
}
