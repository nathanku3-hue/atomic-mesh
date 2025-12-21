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
    if ($State) { $State.MarkDirty("ctrlc") }
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
        if ($State) { $State.MarkDirty("ctrlc") }
    }
}

function Render-CtrlCWarning {
    <#
    .SYNOPSIS
        Renders Ctrl+C warning below input box, aligned with left edge.
        Skips when dropdown or toast is active (shares same row).
    #>
    param(
        [int]$RowInput,
        [int]$Width,
        $Toast = $null
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Skip if dropdown is active (it uses the same row)
    try {
        $pickerState = Get-PickerState
        if ($pickerState -and $pickerState.IsActive) { return }
    } catch {
        # Get-PickerState not available, continue rendering
    }

    # Skip if toast is active (shares same row)
    if ($Toast -and $Toast.Message) { return }

    $warningRow = $RowInput + 2  # Below input box bottom border
    $left = 2  # Align with input box left edge (InputLeft)

    if ($script:CtrlCState.ShowWarning) {
        $msg = "Press Ctrl+C again"
        $padded = $msg.PadRight($Width - $left)
        TryWriteAt -Row $warningRow -Col $left -Text $padded -Color "Yellow" | Out-Null
    } else {
        # Clear the line (only if no toast)
        $blank = " " * ($Width - $left)
        TryWriteAt -Row $warningRow -Col $left -Text $blank -Color "White" | Out-Null
    }
}

function Invoke-HistoryHotkey {
    param(
        $State,
        [char]$Char
    )

    if (-not $State -or -not $Char) { return $false }
    if ($State.OverlayMode -ne "History") { return $false }
    if (-not [string]::IsNullOrEmpty($State.InputBuffer)) { return $false }

    $upper = $Char.ToString().ToUpperInvariant()
    switch ($upper) {
        "D" {
            $State.HistoryDetailsVisible = -not $State.HistoryDetailsVisible
            $State.MarkDirty("content")
            return $true
        }
        "V" {
            if ($State.Toast) {
                $State.Toast.Set("Verify (stub): no history data", "info", 2)
                $State.MarkDirty("toast")
            }
            $State.MarkDirty("content")
            return $true
        }
        default { return $false }
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

function Update-AutoPageFromPlanStatus {
    <#
    .SYNOPSIS
        Auto-switch page based on initialization status.
        - Uninitialized + on PLAN → switch to BOOTSTRAP
        - Initialized + on BOOTSTRAP → switch to PLAN
        Only switches when on PLAN or BOOTSTRAP to avoid yanking user from GO/HISTORY.

        IMPORTANT: Uses actual initialization check (marker/docs), NOT plan status.
        After /init, repo is initialized even if no draft exists yet.

        Also stores IsInitialized flag in state for header rendering (single source of truth).
    #>
    param($State, $Snapshot)

    # Get ProjectPath from state metadata
    $projectPath = if ($State.Cache -and $State.Cache.Metadata) {
        $State.Cache.Metadata["ProjectPath"]
    } else {
        (Get-Location).Path
    }

    # Check ACTUAL initialization status (marker or 2/3 docs)
    # DERIVED VALUE: Compute IsInitialized from ground truth (4-tier detection) on EVERY tick.
    # This is NOT a latch - it's recomputed each refresh so broken repos won't pass guards.
    # Ground truth = marker file OR 2/3 golden docs, NOT the plan status which may be "BLOCKED"/"NO_DATA".
    $initStatus = Test-RepoInitialized -Path $projectPath
    $isInitialized = $initStatus.initialized

    # Store in state metadata - single source of truth for guards and header rendering
    # Refreshed every tick, so guards always see current initialization state
    if ($State.Cache -and $State.Cache.Metadata) {
        $State.Cache.Metadata["IsInitialized"] = $isInitialized
    }

    # Page auto-switching based on initialization status
    # - Uninitialized + on PLAN → switch to BOOTSTRAP (guard against invalid state)
    # - Initialized + on BOOTSTRAP → switch to PLAN (after /init succeeds)
    $previousPage = $State.CurrentPage
    if (-not $isInitialized -and $State.CurrentPage -eq "PLAN") {
        $State.SetPage("BOOTSTRAP")
    }
    elseif ($isInitialized -and $State.CurrentPage -eq "BOOTSTRAP") {
        $State.SetPage("PLAN")
    }

    # Debug: Log page transitions for drift diagnosis (only when logging enabled)
    if ($State.CurrentPage -ne $previousPage -and $State.EnableSnapshotLogging) {
        $State.LastDebug = "AutoPage: $previousPage→$($State.CurrentPage) init=$isInitialized reason=$($initStatus.reason)"
    }
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

    # Check if force refresh is requested (e.g., after /init)
    $forceRefresh = $State.ForceDataRefresh
    if ($forceRefresh) {
        $State.ForceDataRefresh = $false  # Reset flag immediately
    }

    # Apply a minimum backoff when the last refresh failed to avoid hammering the backend
    $errorBackoffMs = 500
    $effectiveIntervalMs = $DataIntervalMs
    if ($State.LastAdapterError) {
        $effectiveIntervalMs = [Math]::Max($DataIntervalMs, $errorBackoffMs)
    }

    if (-not $forceRefresh -and -not (Get-IsDataRefreshDue -LastRefresh $State.LastDataRefreshUtc -IntervalMs $effectiveIntervalMs -NowUtc $NowUtc)) {
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

        # Update the last refresh timestamp even on failure so we respect the backoff
        $State.LastDataRefreshUtc = $NowUtc
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

    # Snapshot logging flag: opt-in via -Dev or env:MESH_LOG_SNAPSHOTS
    $envLog = $env:MESH_LOG_SNAPSHOTS
    $loggingEnabled = $Dev -or ($envLog -and $envLog -ne "0")
    $state.EnableSnapshotLogging = [bool]$loggingEnabled

    # GOLDEN NUANCE FIX: Three distinct roots (never confuse them)
    # - ProjectPath: Where user is operating (launch cwd). Used for header + DB + docs target
    # - ModuleRoot: Where mesh module repo lives (for library/templates/). Derived from script location.
    # - RepoRoot: Legacy alias for project discovery. May be same as ProjectPath.
    $projectPath = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }
    $repoRoot = Get-RepoRoot -HintPath $projectPath

    # ModuleRoot = mesh repo root where library/templates/ lives
    # From Public/Start-ControlPanel.ps1 → go up 3 levels to repo root
    $moduleRoot = Split-Path -Parent $PSScriptRoot           # Public/ → AtomicMesh.UI/
    $moduleRoot = Split-Path -Parent $moduleRoot             # AtomicMesh.UI/ → src/
    $moduleRoot = Split-Path -Parent $moduleRoot             # src/ → repo root

    # DB lookup uses ProjectPath (where user is working), not RepoRoot
    $dbPathResolved = Get-DbPath -DbPath $DbPath -ProjectPath $projectPath

    # Store all paths in cache
    $state.Cache.Metadata["ProjectPath"] = $projectPath  # For header display + docs target
    $state.Cache.Metadata["ModuleRoot"] = $moduleRoot    # For library/templates/ lookup
    $state.Cache.Metadata["RepoRoot"] = $repoRoot        # Legacy: project discovery
    $state.Cache.Metadata["DbPath"] = $dbPathResolved    # For backend calls that need DB path

    if (-not $SnapshotLoader) {
        $SnapshotLoader = { param($root) Get-RealSnapshot -RepoRoot $root }
    }

    try {
        [Console]::Title = "Atomic Mesh :: $ProjectName"
        [Console]::TreatControlCAsInput = $true  # Capture Ctrl+C as key input
    }
    catch {}

    Reset-CtrlCState  # Initialize Ctrl+C protection
    Reset-PickerState  # Initialize command picker state

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

        # Auto-switch page based on initialization status
        Update-AutoPageFromPlanStatus -State $state -Snapshot $snapshot

        # Optional: pipeline snapshot logging (opt-in)
        Write-PipelineSnapshotIfEnabled -State $state -Snapshot $snapshot -ProjectPath $projectPath

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

                    # DROPDOWN: RightArrow autocompletes (no trailing space), keeps dropdown open
                    if ($key.Key -eq [ConsoleKey]::RightArrow) {
                        $selected = Get-SelectedCommand
                        if ($selected) {
                            $state.InputBuffer = $selected  # No trailing space
                            $inputChanged = $true
                            # Don't re-filter - keeps dropdown stable with current selection
                            $state.MarkDirty("input")
                            $state.MarkDirty("picker")
                        }
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

                # History navigation: Up/Down adjust selection when overlay active and input empty
                if ($state.OverlayMode -eq "History" -and [string]::IsNullOrEmpty($state.InputBuffer)) {
                    $rows = @()
                    try {
                        $snap = $state.Cache.LastSnapshot
                        if ($snap) {
                            switch ($state.HistorySubview) {
                                "TASKS" { if ($snap.HistoryTasks) { $rows = @($snap.HistoryTasks) } }
                                "DOCS"  { if ($snap.HistoryDocs)  { $rows = @($snap.HistoryDocs) } }
                                "SHIP"  { if ($snap.HistoryShip)  { $rows = @($snap.HistoryShip) } }
                            }
                        }
                    } catch {}
                    $maxIdx = [Math]::Max(0, $rows.Count - 1)
                    if ($key.Key -eq [ConsoleKey]::UpArrow) {
                        if ($state.HistorySelectedRow -gt 0) {
                            $state.HistorySelectedRow--
                            $state.MarkDirty("content")
                        }
                        continue
                    }
                    if ($key.Key -eq [ConsoleKey]::DownArrow) {
                        if ($state.HistorySelectedRow -lt $maxIdx) {
                            $state.HistorySelectedRow++
                            $state.MarkDirty("content")
                        }
                        continue
                    }
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
                        $state.MarkDirty("input")  # Mark input dirty immediately
                        # Update dropdown filter when backspacing
                        if ($state.InputBuffer.StartsWith("/")) {
                            Update-PickerFilter -Filter $state.InputBuffer.Substring(1)
                            $state.MarkDirty("picker")
                        } else {
                            Reset-PickerState
                            $state.MarkDirty("picker")
                        }
                    }
                    continue
                }

                if (-not [char]::IsControl($key.KeyChar)) {
                    # History hotkeys (buffer must be empty)
                    if ($state.OverlayMode -eq "History" -and [string]::IsNullOrEmpty($state.InputBuffer)) {
                        if (Invoke-HistoryHotkey -State $state -Char $key.KeyChar) {
                            $inputChanged = $true
                            continue
                        }
                    }

                    # D key: Toggle doc details (PLAN + pre-draft + empty input + no overlay)
                    # Guard: only when buffer is empty and we're in pre-draft DOCS panel state
                    if ($key.KeyChar -eq 'd' -or $key.KeyChar -eq 'D') {
                        $inputEmpty = [string]::IsNullOrEmpty($state.InputBuffer)
                        $isPreDraft = $false
                        try {
                            $planState = $snapshot.PlanState
                            $hasDraft = $planState -and $planState.Status -and $planState.Status -ne "EMPTY"
                            $isPreDraft = -not $hasDraft
                        } catch { $isPreDraft = $true }

                        if ($inputEmpty -and $state.CurrentPage -eq "PLAN" -and $isPreDraft -and $state.OverlayMode -eq "None") {
                            $state.ToggleDocDetails()
                            continue
                        }
                    }

                    $state.InputBuffer += $key.KeyChar
                    $inputChanged = $true
                    $state.MarkDirty("input")  # Mark input dirty immediately

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
        $state.RenderFrames++

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
            # OVERLAY FIX: Skip main page render when overlay is active to prevent bleed-through
            if ($state.OverlayMode -eq "History") {
                Render-HistoryOverlay -State $state -StartRow $contentStartRow -BottomRow $footerRow
            }
            else {
                switch ($state.CurrentPage.ToUpper()) {
                    "PLAN" { Render-Plan -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                    "GO" { Render-Go -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                    "BOOTSTRAP" { Render-Bootstrap -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                    default { Render-Plan -Snapshot $snapshot -State $state -StartRow $contentStartRow -BottomRow $footerRow }
                }
            }

            # Render footer bar at golden position
            Render-HintBar -Row $footerRow -Width $width -State $state
            Render-ToastLine -Toast $state.Toast -Row $toastRow -Width $width
            # Render golden boxed input (3-row structure)
            # x86 fix: capture to local var before passing (direct property access fails)
            $buf = $state.InputBuffer
            Render-InputBox -Buffer $buf -RowInput $rowInput -Width $width

            # Render Ctrl+C warning below input box (aligned with left edge)
            # Skip if toast is active (shares same row)
            Render-CtrlCWarning -RowInput $rowInput -Width $width -Toast $state.Toast

            # DROPDOWN: Render command picker below input box if active
            $pickerState = Get-PickerState
            if ($pickerState.IsActive) {
                $dropdownRow = $rowInput + 2  # Below input box bottom border
                Render-CommandDropdown -StartRow $dropdownRow -Width $width
                $state.LastPickerHeight = (Get-PickerState).Commands.Count
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
            Begin-ConsoleFrame  # Ensure frame is valid for partial renders
            try { [Console]::CursorVisible = $false } catch {}

            if ($state.IsDirty("picker")) {
                # Picker partial redraw with clearing
                Render-PickerArea -State $state -RowInput $rowInput -Width $width
            }

            if ($state.IsDirty("input")) {
                # Reset frame state - picker failures should not block input rendering
                Begin-ConsoleFrame
                # x86 fix: capture to local var before passing (direct property access fails)
                $buf = $state.InputBuffer
                Render-InputBox -Buffer $buf -RowInput $rowInput -Width $width
            }

            if ($state.IsDirty("toast")) {
                Render-ToastLine -Toast $state.Toast -Row $toastRow -Width $width
            }

            if ($state.IsDirty("footer")) {
                Render-HintBar -Row $footerRow -Width $width -State $state
            }

            if ($state.IsDirty("ctrlc")) {
                Render-CtrlCWarning -RowInput $rowInput -Width $width -Toast $state.Toast
            }

            End-ConsoleFrame | Out-Null  # Flush partial render
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
