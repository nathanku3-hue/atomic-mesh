function Compute-PlanState {
    param($RawSnapshot)  # Accept PSCustomObject from ConvertFrom-Json OR hashtable

    $state = [PlanState]::new()

    if (-not $RawSnapshot) {
        $state.Status = "NO_DATA"
        $state.NextHint = Compute-NextHint -PlanState $state -RawSnapshot $RawSnapshot
        return $state
    }

    $plan = $RawSnapshot.plan
    if ($plan) {
        $state.HasDraft = [bool]$plan.has_draft
        $state.Accepted = [bool]$plan.accepted
        $state.PlanId = if ($plan.id) { [string]$plan.id } else { "" }
        $state.Summary = if ($plan.summary) { [string]$plan.summary } else { "" }
        if ($plan.status) {
            $state.Status = [string]$plan.status
        }
        elseif ($state.Accepted) {
            $state.Status = "ACCEPTED"
        }
        elseif ($state.HasDraft) {
            $state.Status = "DRAFT"
        }
        else {
            $state.Status = "MISSING"
        }
    }
    else {
        $state.Status = "NO_PLAN"
    }

    $state.NextHint = Compute-NextHint -PlanState $state -RawSnapshot $RawSnapshot
    return $state
}
