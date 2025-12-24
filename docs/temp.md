# Atomic Mesh UI - Development Reference

> **Remember Forever** - Key learnings, patterns, and decisions from UI development.

---

## Table of Contents

1. [Architecture Patterns](#architecture-patterns)
2. [PowerShell Gotchas](#powershell-gotchas)
3. [Region-Based Dirty Rendering](#region-based-dirty-rendering)
4. [Command Picker / Dropdown](#command-picker--dropdown)
5. [Key Bindings Contract](#key-bindings-contract)
6. [Ctrl+C Protection](#ctrlc-protection)
7. [Command Guards](#command-guards)
8. [Test Coverage](#test-coverage)
9. [Right Arrow Autocomplete](#right-arrow-autocomplete)

---

## Architecture Patterns

### Frame Ownership

**Pattern:** `Start-ControlPanel` owns frame validity (Begin/End).
Render functions assume a valid frame and must not call console APIs outside a frame context.

```powershell
# Start-ControlPanel.ps1 - OWNER
Begin-ConsoleFrame
# ... all rendering happens here ...
End-ConsoleFrame

# CommandPicker.ps1 - CONSUMER (no frame checks inside)
function Render-CommandDropdown { ... }  # Assumes frame is valid
```

**Documented in:** `CommandPicker.ps1` header comment.

### State Management

**Current:** `$script:` scoped variables in individual files.
- `$script:PickerState` in CommandPicker.ps1
- `$script:CtrlCState` in Start-ControlPanel.ps1
- `$script:CommandRegistry` in CommandPicker.ps1

**Future improvement:** Move picker state into UiState class:
```powershell
UiState.Picker = @{ IsActive; Items; Index; Filter; Height; ... }
```
- CommandPicker.ps1 becomes pure functions taking (UiState, Layout)
- No module-scoped variables → no x86 scope surprises

### Two Distinct Paths

**Never confuse these:**
- `ProjectPath`: Where user launched from (header display, DB location)
- `RepoRoot`: Where UI module code lives (imports, tools)

---

## PowerShell Gotchas

### 1. Class Type Mismatch on Module Reload

**Problem:** `Cannot convert "UiSnapshot" value of type "UiSnapshot" to type "UiSnapshot"`

**Cause:** PowerShell classes are scope-bound. Module reload creates a "new" type that can't be assigned to old typed properties.

**Fix:** Use `[object]` instead of specific class types:
```powershell
# BAD
[UiSnapshot]$LastSnapshot

# GOOD
[object]$LastSnapshot
```

**Applied to:** UiState, UiSnapshot, UiCache, UiEventLog properties.

### 2. Function Parameter Type Constraints

**Problem:** Function parameters like `[UiState]$State` reject objects from old class definitions.

**Fix:** Remove type constraints, use duck typing:
```powershell
# BAD
function Render-Plan([UiState]$State) { ... }

# GOOD
function Render-Plan($State) { ... }
```

**Note:** Restart PowerShell session to clear cached old class types.

### 3. x86 PowerShell Scope Issues

**Problem:** Complex operations inside key loops can interfere with state.

**Problematic pattern:**
```powershell
# This broke MarkDirty("picker") on x86!
$debugState = Get-PickerState
$state.Toast.Set("DEBUG: Cmds=$($debugState.Commands.Count)...", 3)
$state.MarkDirty("toast")
$state.MarkDirty("picker")  # Did not persist!
```

**Fix:** Keep key loop simple. Avoid complex string interpolation with state objects.

**Working pattern:**
```powershell
if ($state.InputBuffer.StartsWith("/")) {
    $filter = $state.InputBuffer.Substring(1)
    if (-not $pickerState.IsActive) {
        Open-CommandPicker -InitialFilter $filter
    } else {
        Update-PickerFilter -Filter $filter
    }
    $state.MarkDirty("picker")
}
```

### 4. Array Return Gotcha

**Problem:** Single-element arrays unwrap to scalars.

**Fix:** Use comma operator:
```powershell
return ,$results  # Forces array context
```

### 5. Partial Render Missing End-ConsoleFrame (v22.5 bug)

**Problem:** After typing "/", dropdown appears but "/" doesn't show in input bar.

**Cause:** Partial render path called `Begin-ConsoleFrame` but never called `End-ConsoleFrame`. Full render path did call it (line 538), but partial render skipped it. Without `End-ConsoleFrame`, partial writes weren't flushed to console.

**Fix:** Added `End-ConsoleFrame | Out-Null` at end of partial render block (line 574).

```powershell
# PARTIAL RENDER path - was missing End-ConsoleFrame
if ($state.IsDirty("ctrlc")) {
    Render-CtrlCWarning -RowInput $rowInput -Width $width
}

End-ConsoleFrame | Out-Null  # Flush partial render  <-- ADDED
$state.ClearDirty()
```

**Lesson:** Both render paths (full and partial) must have matching Begin/End frame calls.

### 6. Frame Invalidation Cascades to Unrelated Renders (v22.8 bug)

**Problem:** Typing "/" shows dropdown but "/" doesn't appear in input box.

**Debug trace:**
```
[CALL#1 buf='/' valid=False]
[SKIPPED#1 - frame invalid]
[FRAME:215 PATH:PARTIAL buf='/']
```

**Cause:** In partial render path, `Render-PickerArea` runs before `Render-InputBox`. If picker rendering throws any exception (e.g., cursor position out of bounds), `TrySetPos`/`TryWriteAt` sets `$script:FrameState.Skip = $true`. Later, `Render-InputBox` checks `Get-ConsoleFrameValid()` and returns early because frame is "invalid".

**Bad (picker failures block input):**
```powershell
elseif ($state.HasDirty()) {
    Begin-ConsoleFrame
    if ($state.IsDirty("picker")) {
        Render-PickerArea ...  # If this fails, Skip=true
    }
    if ($state.IsDirty("input")) {
        Render-InputBox ...     # Skipped because Skip=true!
    }
}
```

**Good (isolate input from picker failures):**
```powershell
if ($state.IsDirty("input")) {
    Begin-ConsoleFrame  # Reset frame state before input render
    Render-InputBox ...
}
```

**Lesson:** Each independent partial render region should reset frame state with `Begin-ConsoleFrame` to prevent cascading failures between unrelated UI components.

---

### 7. x86 Object Property in Parameter Expression Bug (v22.7 bug)

**Problem:** After typing "/", buffer shows "/" at call site but Render-InputBox receives empty string.

**Debug trace:**
```
[PRE:len=1 val='/']   # Caller has "/"
[RCV:len=0 val='']    # Function receives ""
```

**Direct TryWriteAt with same `$state.InputBuffer` WORKS** - proves property has value.

**Cause:** PowerShell x86 fails to bind object property access (`$state.InputBuffer`) directly in named parameter expressions.

**Bad (fails on x86):**
```powershell
Render-InputBox -Buffer $state.InputBuffer -RowInput $rowInput -Width $width
```

**Good (works):**
```powershell
$buf = $state.InputBuffer
Render-InputBox -Buffer $buf -RowInput $rowInput -Width $width
```

**Lesson:** On x86 PowerShell, always capture object properties to local variables before passing as function parameters.

---

## Region-Based Dirty Rendering

**Purpose:** Eliminate flicker from full `[Console]::Clear()` on every change.

### Regions

| Region | Triggers | Behavior |
|--------|----------|----------|
| `all` | resize, init | Clear-Screen + full render |
| `content` | data change, page switch, overlay, commands | Clear-Screen + full render |
| `picker` | dropdown open/close/navigate | Partial: clear stale + render dropdown |
| `input` | typing, backspace | Partial: render input box only |
| `toast` | toast set/expire | Partial: render toast line only |
| `footer` | mode change | Partial: render hint bar only |
| `ctrlc` | Ctrl+C warning show/hide | Partial: render warning line only |

### Implementation

```powershell
# UiState.ps1
[HashSet[string]]$DirtyRegions
[void] MarkDirty([string]$region) { $this.DirtyRegions.Add($region) }
[bool] IsDirty([string]$region) { return $this.DirtyRegions.Contains($region) }
[bool] HasDirty() { return $this.DirtyRegions.Count -gt 0 }
[void] ClearDirty() { $this.DirtyRegions.Clear() }
```

### Render Loop

```powershell
$needsFull = $state.IsDirty("all") -or $state.IsDirty("content")

if ($needsFull -and $state.HasDirty()) {
    # FULL RENDER: Clear + everything
    Clear-Screen
    Render-Header; Render-Content; Render-Footer; Render-Input; ...
}
elseif ($state.HasDirty()) {
    # PARTIAL RENDER: Only dirty regions (no Clear)
    if ($state.IsDirty("picker")) { Render-PickerArea ... }
    if ($state.IsDirty("input")) { Render-InputBox ... }
    if ($state.IsDirty("toast")) { Render-ToastLine ... }
    ...
}
$state.ClearDirty()
```

---

## Command Picker / Dropdown

### State

```powershell
$script:PickerState = @{
    IsActive = $false
    Filter = ""
    SelectedIndex = 0
    ScrollOffset = 0
    Commands = @()
}
```

### Functions

| Function | Purpose |
|----------|---------|
| `Get-PickerState` | Returns current state |
| `Reset-PickerState` | Closes dropdown, clears state |
| `Open-CommandPicker` | Opens with initial filter |
| `Update-PickerFilter` | Updates filter, recomputes commands |
| `Navigate-PickerUp/Down` | Move selection |
| `Get-SelectedCommand` | Returns "/command" or $null |
| `Get-PickerCommands` | Filters command registry |

### Rendering

- `Render-PickerArea`: Partial redraw handler (clears stale, renders current)
- `Render-CommandDropdown`: Draws visible items at `$rowInput + 2`
- `Clear-CommandDropdown`: Clears N lines at dropdown position

### Dropdown Position

```
┌─────────────────────────────────────────────┐
│ > /draft-plan                               │ ← rowInput
└─────────────────────────────────────────────┘
> /help           Show available commands       ← rowInput + 2 (dropdown start)
  /draft-plan     Create a new plan draft
  /accept-plan    Accept the current plan
  ...
```

---

## Key Bindings Contract

### When Dropdown IS Active

| Key | Action | Dropdown | Input Buffer |
|-----|--------|----------|--------------|
| Up/Down | Navigate selection | Stays open | Unchanged |
| Tab | Complete + space | **Closes** | `$selected + " "` |
| RightArrow | Autocomplete (no space) | **Stays open** | `$selected` |
| Enter | Execute selected | Closes | Cleared after exec |
| ESC | Close dropdown | **Closes** | Preserved |
| Typing | Filter commands | Stays open | Updated |
| Backspace | Update filter | Stays/closes if no "/" | Updated |

### When Dropdown NOT Active

| Key | Action |
|-----|--------|
| `/` | Opens dropdown |
| Tab | Cycle mode (if buffer empty) |
| F2 | Toggle History overlay |
| ESC | Clear input buffer |
| Enter | Execute command |

---

## Ctrl+C Protection

**Purpose:** Prevent accidental exit - requires double-press within 2 seconds.

### State

```powershell
$script:CtrlCState = @{
    LastPressUtc = [datetime]::MinValue
    TimeoutMs = 2000
    ShowWarning = $false
}
```

### Behavior

1. First Ctrl+C → Warning: "Press Ctrl+C again" (below input box)
2. Second Ctrl+C within 2s → Exit
3. Warning auto-clears after timeout

### Layout

Warning renders at `rowInput + 2` (same as dropdown). Skip warning render when dropdown is active.

```powershell
function Render-CtrlCWarning {
    # Skip if dropdown is active (shares same row)
    $pickerState = Get-PickerState
    if ($pickerState -and $pickerState.IsActive) { return }
    ...
}
```

---

## Command Guards

| Command | Guard | Message if blocked |
|---------|-------|-------------------|
| `/go` | Requires `ACCEPTED` | "Draft not accepted - run /accept-plan first" |
| `/go` | Requires any plan | "No plan - run /draft-plan first" |
| `/accept-plan` | Requires `DRAFT` | "No draft to accept - run /draft-plan first" |

**Implementation:** Inline guards in `Invoke-CommandRouter.ps1` switch cases.

---

## Test Coverage

**72/72 pre-ship sanity checks** covering:
- Render integrity at various widths (60, 80, 120)
- Key bindings (Tab, ESC, F2, Enter, RightArrow)
- Command routing and guards
- Dropdown behavior (filter, navigate, select, RightArrow autocomplete)
- Region-based dirty rendering
- Ctrl+C protection
- Pipeline stage colors
- Golden nuances (path display, health dot, lane counts)

---

## Right Arrow Autocomplete

**Status:** Implemented (v22.5)

### Behavior (pre-migration)

1. User types `/a`
2. Dropdown shows `/accept-plan` at top (selected)
3. User presses **Right Arrow**
4. Input buffer becomes `/accept-plan` (no trailing space)
5. Dropdown stays open
6. User presses **Enter** to execute

### Implementation

```powershell
# In Start-ControlPanel.ps1, inside if ($pickerState.IsActive) block:
if ($key.Key -eq [ConsoleKey]::RightArrow) {
    $selected = Get-SelectedCommand
    if ($selected) {
        $state.InputBuffer = $selected  # No trailing space
        $inputChanged = $true
        # Don't recompute/re-filter - keeps dropdown stable
        $state.MarkDirty("input")
        $state.MarkDirty("picker")
    }
    continue
}
```

### Tab vs RightArrow

| Aspect | Tab | RightArrow |
|--------|-----|------------|
| Trailing space | Yes | No |
| Dropdown | Closes | Stays open |
| Re-filter | N/A | No |

### Guards

- Only when `$pickerState.IsActive`
- Only when `$selected` is not null → if null, just `continue` (no-op)
- Future: Don't interfere if cursor not at end

### Enter Priority After RightArrow

After RightArrow fills the buffer, Enter should execute the **current input buffer** (now the full command). The Enter handler prioritizes:

1. If picker active AND selection exists → execute selected
2. Else → execute buffer

Either path works since buffer now matches selection. CHECK 72 locks this behavior.

### Test Cases

- CHECK 69: RightArrow autocompletes selected command
- CHECK 70: RightArrow keeps dropdown open
- CHECK 71: RightArrow has no trailing space
- CHECK 72: After RightArrow, Enter executes command

---

## Version History

| Version | Tests | Key Changes |
|---------|-------|-------------|
| v22.0 | 62/62 | Golden parity + P7 Optimize stage |
| v22.1 | 64/64 | Command guards |
| v22.2 | 67/67 | Region-based dirty rendering |
| v22.3 | 68/68 | Ctrl+C protection, cursor fixes |
| v22.4 | 68/68 | x86 dropdown fix |
| v22.5 | 72/72 | RightArrow autocomplete (no trailing space, keeps dropdown open) |
| v22.6 | 72/72 | Fix partial render flush (missing End-ConsoleFrame) |
| v22.7 | 72/72 | Fix x86 property-in-param bug (capture to local var first) |
| v22.8 | 72/72 | Fix frame invalidation blocking input rendering |
a