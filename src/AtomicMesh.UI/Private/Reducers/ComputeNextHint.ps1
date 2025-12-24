function Compute-NextHint {
    param(
        $PlanState,
        $RawSnapshot  # Accept PSCustomObject from ConvertFrom-Json OR hashtable
    )

    if ($PlanState -and $PlanState.Accepted) {
        # Check if there's already active work running
        $hasActive = $false
        try {
            $hasActive = $RawSnapshot -and $RawSnapshot.DistinctLaneCounts -and $RawSnapshot.DistinctLaneCounts.active -gt 0
        } catch {}

        if ($hasActive) {
            return "[F2] to monitor"  # Work already running, suggest monitor view
        }
        return "/go"
    }

    if ($PlanState -and $PlanState.HasDraft) {
        return "/accept-plan"
    }

    return "/draft-plan"
}
