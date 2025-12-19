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
    param([UiSnapshot]$Snapshot)

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
        [UiState]$State,
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
            $State.MarkDirty("data")
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
            $State.MarkDirty("error")
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
        [ScriptBlock]$SnapshotLoader
    )

    $state = [UiState]::new()
    $state.CurrentPage = "PLAN"
    $state.InputBuffer = ""

    $repoRoot = Get-RepoRoot -HintPath $ProjectPath
    $dbPathResolved = Get-DbPath -DbPath $DbPath -RepoRoot $repoRoot
    if (-not $SnapshotLoader) {
        $SnapshotLoader = { param($root) Get-RealSnapshot -RepoRoot $root }
    }

    try {
        [Console]::Title = "Atomic Mesh :: $ProjectName"
    }
    catch {}

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

        # Data refresh (marks dirty only if data meaningfully changed)
        $snapshot = Invoke-DataRefreshTick -State $state -DataIntervalMs $DataIntervalMs -NowUtc $now -SnapshotLoader $SnapshotLoader -RepoRoot $repoRoot

        # Check for resize
        $window = $Host.UI.RawUI.WindowSize
        $width = if ($window.Width -gt 0) { $window.Width } else { 80 }
        $height = if ($window.Height -gt 0) { $window.Height } else { 24 }
        if ($width -ne $state.LastWidth -or $height -ne $state.LastHeight) {
            $state.LastWidth = $width
            $state.LastHeight = $height
            $state.MarkDirty("resize")
        }

        # Input handling
        $inputChanged = $false
        try {
            while ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)

                # F5 toggles auto-refresh
                if ($key.Key -eq [ConsoleKey]::F5) {
                    $state.AutoRefreshEnabled = -not $state.AutoRefreshEnabled
                    $msg = if ($state.AutoRefreshEnabled) { "Auto-refresh ON" } else { "Auto-refresh OFF (F5 to resume)" }
                    $state.Toast.Set($msg, 2000)
                    $state.MarkDirty("toggle")
                    continue
                }

                # F6 toggles render stats overlay
                if ($key.Key -eq [ConsoleKey]::F6) {
                    if ($state.OverlayMode -eq "RenderStats") {
                        $state.OverlayMode = "None"
                    }
                    else {
                        $state.OverlayMode = "RenderStats"
                    }
                    $state.MarkDirty("overlay")
                    continue
                }

                if ($key.Key -in [ConsoleKey]::Tab, [ConsoleKey]::F2, [ConsoleKey]::F4, [ConsoleKey]::Escape) {
                    Invoke-KeyRouter -KeyInfo $key -State $state | Out-Null
                    $state.MarkDirty("overlay")
                    continue
                }

                if ($key.Key -eq [ConsoleKey]::Enter) {
                    $result = Invoke-CommandRouter -Command $state.InputBuffer -State $state -Snapshot $snapshot
                    $state.InputBuffer = ""
                    $inputChanged = $true
                    $state.MarkDirty("command")
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
                    }
                    continue
                }

                if (-not [char]::IsControl($key.KeyChar)) {
                    $state.InputBuffer += $key.KeyChar
                    $inputChanged = $true
                }
            }
        }
        catch {
            # Key read failures should not break the loop.
        }

        # Track input buffer changes separately (for partial redraw)
        if ($state.InputBuffer -ne $state.LastInputBuffer) {
            $state.LastInputBuffer = $state.InputBuffer
            $inputChanged = $true
        }

        # Only render when dirty
        if ($state.IsDirty) {
            Begin-ConsoleFrame
            try {
                [Console]::CursorVisible = $false
                [Console]::Clear()
            }
            catch {}

            switch ($state.CurrentPage.ToUpper()) {
                "PLAN" { Render-Plan -Snapshot $snapshot -State $state }
                "GO" { Render-Go -Snapshot $snapshot -State $state }
                "BOOTSTRAP" { Render-Bootstrap -Snapshot $snapshot -State $state }
                default { Render-Plan -Snapshot $snapshot -State $state }
            }

            if ($state.OverlayMode -eq "History") {
                Render-HistoryOverlay -State $state
            }
            elseif ($state.OverlayMode -eq "StreamDetails") {
                Render-StreamDetailsOverlay -State $state
            }
            elseif ($state.OverlayMode -eq "RenderStats") {
                Render-StatsOverlay -State $state -Width $width
            }

            $toastRow = [Math]::Max(0, $height - 2)
            $inputRow = [Math]::Max(0, $height - 1)
            $hintRow = [Math]::Max(0, $toastRow - 1)

            Render-HintBar -Row $hintRow -Width $width
            Render-ToastLine -Toast $state.Toast -Row $toastRow -Width $width
            Render-InputLine -Buffer $state.InputBuffer -Row $inputRow -Width $width

            $frameOk = End-ConsoleFrame
            if ($frameOk) {
                $state.RenderFrames++
            }
            else {
                $state.SkippedFrames++
            }

            $state.ClearDirty()
        }
        elseif ($inputChanged) {
            # Partial redraw: only update input line when input changes but nothing else is dirty
            $inputRow = [Math]::Max(0, $height - 1)
            Render-InputLine -Buffer $state.InputBuffer -Row $inputRow -Width $width
        }

        Start-Sleep -Milliseconds $RenderIntervalMs
    }

    try {
        [Console]::CursorVisible = $true
    }
    catch {}
}
