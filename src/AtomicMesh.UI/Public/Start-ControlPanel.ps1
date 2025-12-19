# =============================================================================
# Ctrl+C Protection: Requires double-press within timeout to exit
# =============================================================================
$script:CtrlCState = @{
    LastPressUtc = [datetime]::MinValue
    TimeoutMs = 2000
    ShowWarning = $false
}

function Test-CtrlCExit {
    <#
    .SYNOPSIS
        Returns $true if Ctrl+C should exit (second press within timeout).
        Returns $false if this is first press (shows warning, resets timer).
    #>
    param($State)

    $now = [datetime]::UtcNow
    $elapsed = ($now - $script:CtrlCState.LastPressUtc).TotalMilliseconds

    if ($elapsed -le $script:CtrlCState.TimeoutMs) {
        # Second press within timeout - exit
        $script:CtrlCState.ShowWarning = $false
        return $true
    }

    # First press - show warning and start timer
    $script:CtrlCState.LastPressUtc = $now
    $script:CtrlCState.ShowWarning = $true
    if ($State) { $State.MarkDirty("input") }
    return $false
}

function Reset-CtrlCState {
    $script:CtrlCState.LastPressUtc = [datetime]::MinValue
    $script:CtrlCState.ShowWarning = $false
}

function Update-CtrlCWarning {
    <#
    .SYNOPSIS
        Clears the warning if timeout has expired.
    #>
    param($State)

    if (-not $script:CtrlCState.ShowWarning) { return }

    $now = [datetime]::UtcNow
    $elapsed = ($now - $script:CtrlCState.LastPressUtc).TotalMilliseconds

    if ($elapsed -gt $script:CtrlCState.TimeoutMs) {
        $script:CtrlCState.ShowWarning = $false
        if ($State) { $State.MarkDirty("input") }
    }
}

function Render-CtrlCWarning {
    <#
    .SYNOPSIS
        Renders Ctrl+C warning below input box, aligned with left edge.
        Skips when dropdown is active (shares same row).
    #>
    param(
        [int]$RowInput,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Skip if dropdown is active (it uses the same row)
    $pickerState = Get-PickerState
    if ($pickerState.IsActive) { return }

    $warningRow = $RowInput + 2  # Below input box bottom border
    $left = 2  # Align with input box left edge (InputLeft)

    if ($script:CtrlCState.ShowWarning) {
        $msg = "Press Ctrl+C again within 2s to exit"
        $padded = $msg.PadRight($Width - $left)
        TryWriteAt -Row $warningRow -Col $left -Text $padded -Color "Yellow" | Out-Null
    } else {
        # Clear the line
        $blank = " " * ($Width - $left)
        TryWriteAt -Row $warningRow -Col $left -Text $blank -Color "White" | Out-Null
    }
}

# =============================================================================
# Data Refresh Helpers
# =============================================================================
function Get-IsDataRefreshDue {
    param(
        [datetime]$LastRefresh,
        [int]$IntervalMs,
        [datetime]$NowUtc
    )

    if (-not $IntervalMs -or $IntervalMs -le 0) { return $true }
    if (-not $LastRefresh -or $LastRefresh -eq [datetime]::MinValue) { return $true }
    $elapsed = ($NowUtc - $LastRefresh).TotalMilliseconds
    return $elapsed -ge $IntervalMs
}

function Get-SnapshotSignature {
    param($RawSnapshot)

    if (-not $RawSnapshot) { return "" }
    $obj = [PSCustomObject]@{}
    $skip = @("GeneratedAtUtc")

    if ($RawSnapshot -is [System.Collections.IDictionary]) {
        $keys = $RawSnapshot.Keys | Sort-Object
        foreach ($key in $keys) {
            if ($skip -contains $key) { continue }
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $RawSnapshot[$key] -Force
        }
    }
    else {
        $properties = $RawSnapshot.PSObject.Properties | Sort-Object Name
        foreach ($prop in $properties) {
            if ($skip -contains $prop.Name) { continue }
            $obj | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
        }
    }
    return ($obj | ConvertTo-Json -Depth 10 -Compress)
}

function Normalize-AdapterError {
    param(
        [string]$Message,
        [int]$MaxLength = 160
    )

    if (-not $Message) { return "" }
    $oneLine = ($Message -replace "[`r`n]+", " ").Trim()
    if ($MaxLength -gt 0 -and $oneLine.Length -gt $MaxLength) {
        return $oneLine.Substring(0, $MaxLength)
    }
    return $oneLine
}

function Get-SnapshotHash {
    param($Snapshot)

    if (-not $Snapshot) { return "null" }

    $parts = @()

    # PlanState - all meaningful fields
    if ($Snapshot.PlanState) {
        $p = $Snapshot.PlanState
        $parts += "plan:$($p.Status)|$($p.HasDraft)|$($p.Accepted)|$($p.PlanId)|$($p.Summary)|$($p.NextHint)"
    }

    # LaneMetrics - ordered by name for stability
    if ($Snapshot.LaneMetrics -and $Snapshot.LaneMetrics.Count -gt 0) {
        $laneStrings = $Snapshot.LaneMetrics | Sort-Object Name | ForEach-Object {
            "$($_.Name):$($_.Queued)/$($_.Active)/$($_.Tokens)/$($_.State)/$($_.DotColor)"
        }
        $parts += "lanes:" + ($laneStrings -join ";")
    }

    # SchedulerDecision
    if ($Snapshot.SchedulerDecision) {
        $s = $Snapshot.SchedulerDecision
        $parts += "sched:$($s.NextAction)|$($s.Reason)"
    }

    # Alerts
    if ($Snapshot.Alerts -and $Snapshot.Alerts.Messages) {
        $parts += "alerts:" + ($Snapshot.Alerts.Messages -join ";")
    }

    # NOTE: AdapterError excluded - tracked separately to avoid perma-dirty on repeated errors

    return ($parts -join "##")
}

function Invoke-DataRefreshTick {
    param(
        $State,
        [int]$DataIntervalMs,
        [datetime]$NowUtc,
        [ScriptBlock]$SnapshotLoader,
        [string]$RepoRoot
    )

    if (-not $State.Cache.LastSnapshot) {
        $State.Cache.LastSnapshot = [UiSnapshot]::new()
    }

    # Skip data refresh if auto-refresh is disabled
    if (-not $State.AutoRefreshEnabled) {
        return $State.Cache.LastSnapshot
    }

    if (-not (Get-IsDataRefreshDue -LastRefresh $State.LastDataRefreshUtc -IntervalMs $DataIntervalMs -NowUtc $NowUtc)) {
        return $State.Cache.LastSnapshot
    }

    try {
        $raw = & $SnapshotLoader $RepoRoot
        $signature = Get-SnapshotSignature -RawSnapshot $raw

        # If nothing meaningful changed, skip replacing the snapshot but clear any stale errors.
        if ($signature -and $State.Cache.LastRawSignature -eq $signature) {
            $State.Cache.LastSnapshot.AdapterError = ""
            $State.LastAdapterError = ""
            $State.LastDataRefreshUtc = $NowUtc
            $State.DataRefreshes++
            return $State.Cache.LastSnapshot
        }

        $snapshot = Convert-RawSnapshotToUi -Raw $raw
        $snapshot.AdapterError = ""

        # Check if snapshot meaningfully changed
        $newHash = Get-SnapshotHash -Snapshot $snapshot
        if ($newHash -ne $State.LastSnapshotHash) {
            $State.MarkDirty("content")  # Data change = content redraw
            $State.LastSnapshotHash = $newHash
        }

        $State.Cache.LastSnapshot = $snapshot
        $State.Cache.LastRawSignature = $signature
        $State.LastAdapterError = ""
        $State.LastDataRefreshUtc = $NowUtc
        $State.DataRefreshes++
        return $snapshot
    }
    catch {
        $message = Normalize-AdapterError -Message $_.Exception.Message
        $newError = "Snapshot error: $message"

        # Only mark dirty if error message changed
        if ($newError -ne $State.LastAdapterError) {
            $State.Cache.LastSnapshot.AdapterError = $newError
            $State.LastAdapterError = $newError
            $State.MarkDirty("content")  # Error display = content redraw
        }

        return $State.Cache.LastSnapshot
    }
}

function Start-ControlPanel {
    param(
        [string]$ProjectName = "Standalone",
        [string]$ProjectPath = "",
        [string]$DbPath = "",
        [int]$RenderIntervalMs = 50,
        [int]$DataIntervalMs = 500,
        [ScriptBlock]$SnapshotLoader,
        [switch]$Dev  # Explicit flag to enable dev hints (F5/F6) - never auto-enabled
    )

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    $state.InputBuffer = ""

    # GOLDEN NUANCE FIX: Two distinct roots (never confuse them)
    # - ProjectPath: Where user is operating (launch cwd). Used for header + DB/config
    # - RepoRoot: Where UI code lives (module location). Used for imports/tools
    $projectPath = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }
    $repoRoot = Get-RepoRoot -HintPath $projectPath

    # DB lookup uses ProjectPath (where user is working), not RepoRoot
    $dbPathResolved = Get-DbPath -DbPath $DbPath -ProjectPath $projectPath

    # Store both paths separately in cache
    $state.Cache.Metadata["ProjectPath"] = $projectPath  # For header display
    $state.Cache.Metadata["RepoRoot"] = $repoRoot        # For module/tool paths

    if (-not $SnapshotLoader) {
        $SnapshotLoader = { param($root) Get-RealSnapshot -RepoRoot $root }
    }

    try {
        [Console]::Title = "Atomic Mesh :: $ProjectName"
        [Console]::TreatControlCAsInput = $true  # Capture Ctrl+C as key input
    }
    catch {}

    Reset-CtrlCState  # Initialize Ctrl+C protection

    $snapshot = [UiSnapshot]::new()
    $state.Cache.LastSnapshot = $snapshot

    $stopRequested = $false

    while (-not $stopRequested) {
        $now = [datetime]::UtcNow
        $state.NowUtc = $now

        # Check for toast expiry (marks dirty if toast cleared)
        if ($state.Toast -and $state.Toast.Message) {
            $cleared = $state.Toast.ClearIfExpired($now)
            if ($cleared) {
                $state.MarkDirty("toast")
            }
        }

        # Check for Ctrl+C warning expiry (auto-clear after timeout)
        Update-CtrlCWarning -State $state

        # Data refresh (marks dirty only if data meaningfully changed)
        # Uses ProjectPath for DB/snapshot location (where user is working)
        $snapshot = Invoke-DataRefreshTick -State $state -DataIntervalMs $DataIntervalMs -NowUtc $now -SnapshotLoader $SnapshotLoader -RepoRoot $projectPath

        # Check for resize
        $window = $Host.UI.RawUI.WindowSize
        $width = if ($window.Width -gt 0) { $window.Width } else { 80 }
        $height = if ($window.Height -gt 0) { $window.Height } else { 24 }
        if ($width -ne $state.LastWidth -or $height -ne $state.LastHeight) {
            $state.LastWidth = $width
            $state.LastHeight = $height
            $state.MarkDirty("all")  # Resize = full redraw
        }

        # Input handling with GOLDEN DROPDOWN CONTRACT
        # Source: golden Read-StableInput (lines 8962-9600)
        $inputChanged = $false
        $pickerState = Get-PickerState
        try {
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # Ctrl+C protection: require double-press within 2s to exit
                if ($key.Key -eq [ConsoleKey]::C -and $key.Modifiers -band [ConsoleModifiers]::Control) {
                    if (Test-CtrlCExit -State $state) {
                        $stopRequested = $true
                        break
                    }
                    continue
                }

                # DROPDOWN: Up/Down arrows navigate when dropdown is active
                if ($pickerState.IsActive) {
                    if ($key.Key -eq [ConsoleKey]::UpArrow) {
                        Navigate-PickerUp
                        $state.MarkDirty("picker")
                        continue
                    }
                    if ($key.Key -eq [ConsoleKey]::DownArrow) {
                        Navigate-PickerDown
                        $state.MarkDirty("picker")
                        continue
                    }

                    # DROPDOWN: Tab inserts selected command + trailing space, closes dropdown
                    if ($key.Key -eq [ConsoleKey]::Tab) {
                        $selected = Get-SelectedCommand
                        if ($selected) {
                            $state.InputBuffer = $selected + " "
                            $inputChanged = $true
                        }
                        Reset-PickerState
                        $state.MarkDirty("picker")
                        continue
                    }

                    # DROPDOWN: Enter executes selected command, closes dropdown
                    if ($key.Key -eq [ConsoleKey]::Enter) {
                        $selected = Get-SelectedCommand
                        if ($selected) {
                            $state.InputBuffer = $selected
                        }
                        Reset-PickerState
                        $result = Invoke-CommandRouter -Command $state.InputBuffer -State $state -Snapshot $snapshot
                        $state.InputBuffer = ""
                        $inputChanged = $true
                        $state.MarkDirty("content")  # Commands change content
                        $state.MarkDirty("input")    # Input cleared
                        if ($result -eq "quit") {
                            $stopRequested = $true
                            break
                        }
                        continue
                    }

                    # DROPDOWN: ESC closes dropdown first (before clearing buffer)
                    if ($key.Key -eq [ConsoleKey]::Escape) {
                        Reset-PickerState
                        $state.MarkDirty("picker")
                        continue
                    }
                }

                # Golden key handling: Tab, F2, Escape (when dropdown not active)
                # These may change content (overlay, mode) - KeyRouter marks appropriate regions
                if ($key.Key -in [ConsoleKey]::Tab, [ConsoleKey]::F2, [ConsoleKey]::Escape) {
                    Invoke-KeyRouter -KeyInfo $key -State $state | Out-Null
                    continue
                }

                if ($key.Key -eq [ConsoleKey]::Enter) {
                    $result = Invoke-CommandRouter -Command $state.InputBuffer -State $state -Snapshot $snapshot
                    $state.InputBuffer = ""
                    $inputChanged = $true
                    $state.MarkDirty("content")  # Commands change content
                    $state.MarkDirty("input")    # Input cleared
                    if ($result -eq "quit") {
                        $stopRequested = $true
                        break
                    }
                    continue
                }

                if ($key.Key -eq [ConsoleKey]::Backspace) {
                    if ($state.InputBuffer.Length -gt 0) {
                        $state.InputBuffer = $state.InputBuffer.Substring(0, $state.InputBuffer.Length - 1)
                        $inputChanged = $true
                        # Update dropdown filter when backspacing
                        if ($state.InputBuffer.StartsWith("/")) {
                            Update-PickerFilter -Filter $state.InputBuffer.Substring(1)
                        } else {
                            Reset-PickerState
                        }
                    }
                    continue
                }

                if (-not [char]::IsControl($key.KeyChar)) {
                    $state.InputBuffer += $key.KeyChar
                    $inputChanged = $true

                    # DROPDOWN: Open/update dropdown when input starts with /
                    if ($state.InputBuffer.StartsWith("/")) {
                        $filter = $state.InputBuffer.Substring(1)
                        if (-not $pickerState.IsActive) {
                            Open-CommandPicker -InitialFilter $filter
                        } else {
                            Update-PickerFilter -Filter $filter
                        }
                        $state.MarkDirty("picker")
                    } else {
                        # Close dropdown if input no longer starts with /
                        if ($pickerState.IsActive) {
                            Reset-PickerState
                            $state.MarkDirty("picker")
                        }
                    }
                }

                # Refresh picker state for next iteration
                $pickerState = Get-PickerState
            }
        }
        catch {
            # Key read failures should not break the loop.
        }

        # Track input buffer changes separately (for partial redraw)
        if ($state.InputBuffer -ne $state.LastInputBuffer) {
            $state.LastInputBuffer = $state.InputBuffer
            $inputChanged = $true
            $state.MarkDirty("input")
        }

        # Layout constants (needed for all render paths)
        $layout = Get-PromptLayout -Width $width -Height $height
        $rowInput = $layout.RowInput
        $footerRow = $layout.RowFooter
        $toastRow = $layout.RowToast
        $contentStartRow = 4

        # Determine if full render needed
        $needsFull = $state.IsDirty("all") -or $state.IsDirty("content")

        if ($needsFull -and $state.HasDirty()) {
            # FULL RENDER: Clear screen and render everything
            Begin-ConsoleFrame
            try {
                [Console]::CursorVisible = $false
                Clear-Screen
            }
            catch {}

            # Golden render order:
            # 1. Header (rows 0-3)
            # 2. Screen content (rows 4+)
            # 3. Footer/hint bar
            # 4. Input line

            # Render header at row 0
            Render-Header -StartRow 0 -Width $width -Snapshot $snapshot -State $state

            # Render content with frame-fill to footer row
            switch ($state.CurrentPage.ToUpper()) {
                "PLAN" { Render-Plan -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                "GO" { Render-Go -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                "BOOTSTRAP" { Render-Bootstrap -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                default { Render-Plan -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
            }

            # Golden overlays: only History (F2)
            if ($state.OverlayMode -eq "History") {
                Render-HistoryOverlay -State $state -StartRow $contentStartRow
            }

            # Render footer bar at golden position
            Render-HintBar -Row $footerRow -Width $width -State $state
            Render-ToastLine -Toast $state.Toast -Row $toastRow -Width $width
            # Render golden boxed input (3-row structure)
            Render-InputBox -Buffer $state.InputBuffer -RowInput $rowInput -Width $width

            # Render Ctrl+C warning below input box (aligned with left edge)
            Render-CtrlCWarning -RowInput $rowInput -Width $width

            # DROPDOWN: Render command picker below input box if active
            $pickerState = Get-PickerState
            if ($pickerState.IsActive) {
                $dropdownRow = $rowInput + 2  # Below input box bottom border
                Render-CommandDropdown -StartRow $dropdownRow -Width $width
                $state.LastPickerHeight = (Get-PickerState).FilteredCommands.Count
            } else {
                $state.LastPickerHeight = 0
            }

            $frameOk = End-ConsoleFrame
            if ($frameOk) {
                $state.RenderFrames++
            }
            else {
                $state.SkippedFrames++
            }

            $state.ClearDirty()
        }
        elseif ($state.HasDirty()) {
            # PARTIAL RENDER: Only update dirty regions (no Clear)
            try { [Console]::CursorVisible = $false } catch {}

            if ($state.IsDirty("picker")) {
                # Picker partial redraw with clearing
                Render-PickerArea -State $state -RowInput $rowInput -Width $width
            }

            if ($state.IsDirty("input")) {
                Render-InputBox -Buffer $state.InputBuffer -RowInput $rowInput -Width $width
                # Also render Ctrl+C warning (shares "input" region)
                Render-CtrlCWarning -RowInput $rowInput -Width $width
            }

            if ($state.IsDirty("toast")) {
                Render-ToastLine -Toast $state.Toast -Row $toastRow -Width $width
            }

            if ($state.IsDirty("footer")) {
                Render-HintBar -Row $footerRow -Width $width -State $state
            }

            $state.ClearDirty()
        }

        Start-Sleep -Milliseconds $RenderIntervalMs
    }

    # Cleanup: restore console state
    try {
        [Console]::CursorVisible = $true
        [Console]::TreatControlCAsInput = $false  # Restore normal Ctrl+C behavior
    }
    catch {}
}
