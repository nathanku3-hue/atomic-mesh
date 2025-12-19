function Compute-LaneMetrics {
    param([hashtable]$RawSnapshot)

    $defaultNames = @("BACKEND", "FRONTEND", "QA/AUDIT", "LIBRARIAN")
    $rawLanes = @()
    if ($RawSnapshot -and $RawSnapshot.lanes) {
        $rawLanes = $RawSnapshot.lanes
    }

    $metrics = [System.Collections.Generic.List[LaneMetrics]]::new()

    foreach ($laneName in $defaultNames) {
        $rawLane = $null
        foreach ($candidate in $rawLanes) {
            if ($candidate.name -and $candidate.name -ieq $laneName) {
                $rawLane = $candidate
                break
            }
        }

        $lane = [LaneMetrics]::CreateDefault($laneName)
        if ($rawLane) {
            $lane.Queued = [int]$rawLane.queued
            $lane.Active = [int]$rawLane.active
            $lane.Tokens = [int]$rawLane.tokens
        }

        $workload = [Math]::Min($lane.Queued + $lane.Active, 10)
        $lane.Bar = ("#" * $workload).PadRight(10, ".")

        if ($lane.Active -gt 0) {
            $lane.State = "RUNNING"
            $lane.DotColor = "Green"
            $lane.Reason = "Active: $($lane.Active)"
        }
        elseif ($lane.Queued -gt 0) {
            $lane.State = "QUEUED"
            $lane.DotColor = "Yellow"
            $lane.Reason = "Queued: $($lane.Queued)"
        }
        else {
            $lane.State = "PENDING"
            $lane.DotColor = "DarkGray"
            $lane.Reason = ""
        }

        $metrics.Add($lane) | Out-Null
    }

    return $metrics.ToArray()
}
