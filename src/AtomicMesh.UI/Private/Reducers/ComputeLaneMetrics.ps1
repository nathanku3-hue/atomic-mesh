function Compute-LaneMetrics {
    param($RawSnapshot)  # Accept PSCustomObject from ConvertFrom-Json OR hashtable

    # Stream display order: backend/frontend first, then QA/librarian
    # Map 6 logical lanes → 4 visual slots (v22.0 fold-in strategy)
    $defaultNames = @("BACKEND", "FRONTEND", "QA", "LIBRARIAN")
    $laneMapping = @{
        "backend"   = "BACKEND"
        "ops"       = "BACKEND"
        "frontend"  = "FRONTEND"
        "qa"        = "QA"
        "librarian" = "LIBRARIAN"
        "docs"      = "LIBRARIAN"
    }
    $rawLanes = @()
    $activeTask = $null

    # Safe property access (strict mode compatible)
    if ($RawSnapshot) {
        $hasLanes = $false
        $hasLaneCounts = $false
        $hasActive = $false
        $isDict = $RawSnapshot -is [System.Collections.IDictionary]
        try { $hasLanes = $null -ne $RawSnapshot.PSObject.Properties['lanes'] } catch {}
        try { $hasLaneCounts = $null -ne $RawSnapshot.PSObject.Properties['LaneCounts'] } catch {}
        try { $hasActive = $null -ne $RawSnapshot.PSObject.Properties['active_task'] -or $null -ne $RawSnapshot.PSObject.Properties['ActiveTask'] } catch {}
        if ($isDict) {
            if ($RawSnapshot.ContainsKey('lanes')) { $hasLanes = $true }
            if ($RawSnapshot.ContainsKey('LaneCounts')) { $hasLaneCounts = $true }
            if ($RawSnapshot.ContainsKey('active_task') -or $RawSnapshot.ContainsKey('ActiveTask')) { $hasActive = $true }
        }

        if ($hasLanes -and $RawSnapshot.lanes) {
            $rawLanes = $RawSnapshot.lanes
        }
        elseif ($hasLaneCounts -and $RawSnapshot.LaneCounts) {
            $rawLanes = $RawSnapshot.LaneCounts
        }
        if ($hasActive) {
            try {
                if ($RawSnapshot.active_task) { $activeTask = $RawSnapshot.active_task }
                elseif ($RawSnapshot.ActiveTask) { $activeTask = $RawSnapshot.ActiveTask }
            } catch { $activeTask = $null }
        }
    }

    # Index raw lanes by lower-case name for stable lookup
    # Aggregate counts per lane (case-insensitive)
    $laneAgg = @{}

    foreach ($candidate in $rawLanes) {
        $ln = ""
        $isCandidateDict = $candidate -is [System.Collections.IDictionary]
        try {
            if ($candidate.lane) {
                $ln = $candidate.lane.ToString().ToLowerInvariant()
            } elseif ($candidate.Lane) {
                $ln = $candidate.Lane.ToString().ToLowerInvariant()
            } elseif ($candidate.name) {
                $ln = $candidate.name.ToString().ToLowerInvariant()
            } elseif ($candidate.Name) {
                $ln = $candidate.Name.ToString().ToLowerInvariant()
            } elseif ($isCandidateDict) {
                if ($candidate.ContainsKey('lane') -and $candidate['lane']) { $ln = $candidate['lane'].ToString().ToLowerInvariant() }
                elseif ($candidate.ContainsKey('Lane') -and $candidate['Lane']) { $ln = $candidate['Lane'].ToString().ToLowerInvariant() }
                elseif ($candidate.ContainsKey('name') -and $candidate['name']) { $ln = $candidate['name'].ToString().ToLowerInvariant() }
                elseif ($candidate.ContainsKey('Name') -and $candidate['Name']) { $ln = $candidate['Name'].ToString().ToLowerInvariant() }
            }
        } catch { $ln = "" }
        if (-not $ln) { continue }

        # Map logical lane to visual slot (default: uppercase of lane)
        $displayName = if ($laneMapping.ContainsKey($ln)) { $laneMapping[$ln] } else { $ln.ToUpperInvariant() }
        $displayKey = $displayName.ToLowerInvariant()
        if (-not $displayKey) { continue }

        if (-not $laneAgg.ContainsKey($displayKey)) {
            $laneAgg[$displayKey] = @{ active = 0; queued = 0; tokens = 0; raw = @() }
        }

        $agg = $laneAgg[$displayKey]
        $agg.raw += $candidate

        # Try to pull a status/count combination (LaneCounts style)
        $status = ""
        try {
            if ($candidate.status) { $status = $candidate.status.ToString().ToLowerInvariant() }
            elseif ($candidate.Status) { $status = $candidate.Status.ToString().ToLowerInvariant() }
            elseif ($isCandidateDict) {
                if ($candidate.ContainsKey('status') -and $candidate['status']) { $status = $candidate['status'].ToString().ToLowerInvariant() }
                elseif ($candidate.ContainsKey('Status') -and $candidate['Status']) { $status = $candidate['Status'].ToString().ToLowerInvariant() }
            }
        } catch { $status = "" }

        $count = 0
        try {
            if ($candidate.count) { $count = [int]$candidate.count }
            elseif ($candidate.Count) { $count = [int]$candidate.Count }
            elseif ($candidate.pending) { $count = [int]$candidate.pending }
            elseif ($candidate.queued) { $count = [int]$candidate.queued }
            elseif ($candidate.tokens) { $count = [int]$candidate.tokens }
            elseif ($isCandidateDict) {
                if ($candidate.ContainsKey('count')) { $count = [int]$candidate['count'] }
                elseif ($candidate.ContainsKey('Count')) { $count = [int]$candidate['Count'] }
                elseif ($candidate.ContainsKey('pending')) { $count = [int]$candidate['pending'] }
                elseif ($candidate.ContainsKey('queued')) { $count = [int]$candidate['queued'] }
                elseif ($candidate.ContainsKey('tokens')) { $count = [int]$candidate['tokens'] }
            }
        } catch { $count = 0 }

        if ($status) {
            if ($status -match "in_progress|running|active") {
                $agg.active += $count
            }
            elseif ($status -match "pending|queued|todo") {
                $agg.queued += $count
            }
        }
        else {
            # No status: treat explicit queued/active fields if present
            try {
                $activeVal = $null
                if ($null -ne $candidate.active) { $activeVal = $candidate.active }
                elseif ($null -ne $candidate.Active) { $activeVal = $candidate.Active }
                elseif ($isCandidateDict -and $candidate.ContainsKey('active')) { $activeVal = $candidate['active'] }
                elseif ($isCandidateDict -and $candidate.ContainsKey('Active')) { $activeVal = $candidate['Active'] }
                if ($activeVal -ne $null) { $agg.active += [int]$activeVal }

                $queuedVal = $null
                if ($null -ne $candidate.queued) { $queuedVal = $candidate.queued }
                elseif ($null -ne $candidate.Queued) { $queuedVal = $candidate.Queued }
                elseif ($isCandidateDict -and $candidate.ContainsKey('queued')) { $queuedVal = $candidate['queued'] }
                elseif ($isCandidateDict -and $candidate.ContainsKey('Queued')) { $queuedVal = $candidate['Queued'] }
                if ($queuedVal -ne $null) { $agg.queued += [int]$queuedVal }
            } catch {}
        }
    }

    # Get bar symbols from constants
    $filled = Get-StreamBarFilled
    $empty = Get-StreamBarEmpty
    $dotChar = [char]0x25CF  # ●

    # Detect active lane + progress (if present)
    $activeLaneKey = ""
    $activeProgress = $null
    if ($activeTask) {
        try {
            $laneName = ""
            if ($activeTask.lane) { $laneName = $activeTask.lane.ToString() }
            elseif ($activeTask.Lane) { $laneName = $activeTask.Lane.ToString() }
            elseif ($activeTask.type) { $laneName = $activeTask.type.ToString() }
            elseif ($activeTask.Type) { $laneName = $activeTask.Type.ToString() }
            $laneKey = $laneName.ToLowerInvariant()
            if ($laneMapping.ContainsKey($laneKey)) {
                $activeLaneKey = $laneMapping[$laneKey].ToLowerInvariant()
            } elseif ($laneKey) {
                $activeLaneKey = $laneKey
            }

            # Progress: prefer numeric 0-100, clamp
            $pVal = $null
            if ($null -ne $activeTask.progress) { $pVal = $activeTask.progress }
            elseif ($null -ne $activeTask.Progress) { $pVal = $activeTask.Progress }
            elseif ($null -ne $activeTask.pct) { $pVal = $activeTask.pct }
            elseif ($null -ne $activeTask.Pct) { $pVal = $activeTask.Pct }
            if ($pVal -ne $null) {
                [double]$parsed = 0
                if ([double]::TryParse($pVal.ToString(), [ref]$parsed)) {
                    $activeProgress = [Math]::Max(0, [Math]::Min(100, $parsed))
                }
            }
        } catch { $activeLaneKey = "" }
    }

    # Use hashtables to avoid PowerShell class caching issues
    $metrics = @()

    foreach ($laneName in $defaultNames) {
        $queued = 0
        $active = 0
        $tokens = 0
        $key = $laneName.ToLowerInvariant()
        if ($laneAgg.ContainsKey($key)) {
            $agg = $laneAgg[$key]
            $queued = [int]$agg.queued
            $active = [int]$agg.active
            $tokens = [int]$agg.tokens
        }

        # Golden bar format: 5 chars using ■/□
        $state = "IDLE"
        $bar = "$empty$empty$empty$empty$empty"
        $dotColor = "DarkGray"
        $stateColor = "DarkGray"
        $reason = ""

        $isActiveLane = ($activeLaneKey -and $activeLaneKey -eq $key -and $active -gt 0)
        $blocks = 0
        if ($isActiveLane -and $activeProgress -ne $null) {
            $blocks = [Math]::Round(([double]$activeProgress / 100) * 5)
            if ($blocks -eq 0 -and $activeProgress -gt 0) { $blocks = 1 }  # started but <5%
            $blocks = [Math]::Max(0, [Math]::Min(5, $blocks))
        } elseif ($active -gt 0) {
            $blocks = 5
        } elseif ($queued -gt 0) {
            $blocks = 2
        }

        $bar = ($filled.ToString() * $blocks) + ($empty.ToString() * (5 - $blocks))

        if ($active -gt 0) {
            $state = "RUNNING"
            $dotColor = "Green"
            $stateColor = "Green"
            $reason = if ($isActiveLane -and $activeProgress -ne $null) {
                "Active: $active ($([int][Math]::Round($activeProgress))%)"
            } else { "Active: $active" }
        }
        elseif ($queued -gt 0) {
            $state = "NEXT"      # Golden parity: NEXT not QUEUED
            $dotColor = "Cyan"   # Golden parity: Cyan not Yellow
            $stateColor = "Cyan"
            $reason = "$queued task(s) queued"
        }

        $lane = @{
            Name       = $laneName
            Queued     = $queued
            Active     = $active
            Tokens     = $tokens
            State      = $state
            Bar        = $bar
            DotColor   = $dotColor
            StateColor = $stateColor
            DotChar    = $dotChar
            Reason     = $reason
        }
        $metrics += $lane
    }

    # Optional debug dump: emit lane metrics when enabled via env:MESH_DEBUG_LANES
    if ($env:MESH_DEBUG_LANES -and $env:MESH_DEBUG_LANES -ne "0") {
        try {
            $lines = @("=== LaneMetrics Debug ===")
            foreach ($m in $metrics) {
                $lines += "{0}: active={1} queued={2} tokens={3} state={4} color={5}" -f $m.Name, $m.Active, $m.Queued, $m.Tokens, $m.State, $m.StateColor
            }
            $outPath = Join-Path (Get-Location) "lanemetrics_debug.log"
            $lines | Out-File -FilePath $outPath -Append -Encoding UTF8
        } catch {}
    }

    return $metrics
}

<#
.SYNOPSIS
    Converts LaneMetrics array to StreamRow hashtables for rendering.
.DESCRIPTION
    Returns golden-shaped StreamRow hashtables ready for Render-StreamRow.
    Renderers consume these models without computing state.
#>
function Compute-StreamRows {
    param([array]$LaneMetrics)

    function Get-PropSafe {
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

    $defaultDot = [char]0x25CF  # ●

    $rows = @()
    foreach ($lane in $LaneMetrics) {
        $stateColor = Get-PropSafe $lane "StateColor" (Get-PropSafe $lane "DotColor" "DarkGray")
        $dotChar = Get-PropSafe $lane "DotChar" $defaultDot
        $rows += @{
            Name         = Get-PropSafe $lane "Name" ""
            Bar          = Get-PropSafe $lane "Bar" ""
            BarColor     = $stateColor
            State        = Get-PropSafe $lane "State" ""
            Summary      = Get-PropSafe $lane "Reason" ""
            SummaryColor = if ($stateColor -eq "Green") { "White" } else { $stateColor }
            DotChar      = $dotChar
            DotColor     = $stateColor
        }
    }
    return $rows
}
