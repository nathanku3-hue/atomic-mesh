function Compute-NextHint {
    param(
        [PlanState]$PlanState,
        [hashtable]$RawSnapshot
    )

    if ($PlanState -and $PlanState.Accepted) {
        return "/go"
    }

    if ($PlanState -and $PlanState.HasDraft) {
        return "/accept-plan"
    }

    return "/draft-plan"
}
