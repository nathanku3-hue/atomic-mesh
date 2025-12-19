# =============================================================================
# GOLDEN TRANSPLANT: Layout Constants (lines 4114-4133)
# Source: golden_control_panel_reference.ps1 commit 6990922
# =============================================================================
# Every element is painted at specific X,Y coordinates - no streaming output

# --- GLOBAL ROW CONSTANTS ---
# Golden line 4114
$script:RowHeader = 0

# Golden line 4115: v19.3 - Header is 4 rows (border+content+blank+border), content starts at row 4
$script:RowDashStart = 4

# Golden line 4116: Keep dropdown small to avoid terminal resize issues
$script:MaxDropdownRows = 5

# Golden lines 4131-4133: Shared left offset for input area alignment
# Aligns input bar with "  Next:" label (2-space indent)
$script:InputLeft = 2

# Accessor functions
function Get-RowHeader { return $script:RowHeader }
function Get-RowDashStart { return $script:RowDashStart }
function Get-MaxDropdownRows { return $script:MaxDropdownRows }
function Get-InputLeft { return $script:InputLeft }

# =============================================================================
# GOLDEN TRANSPLANT: Get-PromptLayout (lines 4148-4166)
# Returns fresh layout values (single source of truth)
# =============================================================================
function Get-PromptLayout {
    param(
        [int]$Width = 0,
        [int]$Height = 0
    )

    # Use provided dimensions or get from console
    $w = if ($Width -gt 0) { $Width } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Width -gt 0) { $window.Width } else { 80 }
    }
    $h = if ($Height -gt 0) { $Height } else {
        $window = $Host.UI.RawUI.WindowSize
        if ($window.Height -gt 0) { $window.Height } else { 24 }
    }

    # Golden line 4126: Input row at 75% height (bottom 1/4 reserved for input area)
    $inputRow = [Math]::Floor($h * 0.75)

    # Golden line 4152: Cap to avoid writing past terminal
    $inputRow = [Math]::Min($inputRow, $h - 5)

    # Ensure minimum content space (at least 6 rows between header and input)
    $inputRow = [Math]::Max($inputRow, $script:RowDashStart + 6)

    # Golden lines 4153-4158: Editor-style footer layout
    #   RowInput - 2: Footer bar (Next: left, [MODE] right)
    #   RowInput - 1: Top border ┌───┐
    #   RowInput:     Input line │ > │
    #   RowInput + 1: Bottom border └───┘
    #   RowInput + 2: Dropdown starts here (when picker is open)
    return @{
        RowInput      = $inputRow
        RowInputTop   = $inputRow - 1    # Top border of input box
        RowInputBottom = $inputRow + 1   # Bottom border of input box
        RowFooter     = $inputRow - 2    # Footer/hint bar row
        RowToast      = $inputRow - 3    # Toast message row
        DropdownRow   = $inputRow + 2    # Below bottom border (golden line 4161)
        Width         = $w
        Height        = $h
        MaxVisible    = [Math]::Min(8, $h - $inputRow - 3)  # Don't exceed terminal
        ContentStart  = $script:RowDashStart
        ContentEnd    = $inputRow - 3    # Last row for main content (before toast)
    }
}
