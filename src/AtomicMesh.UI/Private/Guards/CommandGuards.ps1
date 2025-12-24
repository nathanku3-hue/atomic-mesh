# =============================================================================
# Command Guards: Pre-condition checks for main loop commands
# =============================================================================
# Progression: /init -> /draft-plan -> /accept-plan -> /go
#
# Status values and what they allow:
#   NO_DATA, NO_PLAN, MISSING, BOOTSTRAP, PRE_INIT, ERROR, "" = Pre-init (only /init)
#   DRAFT = Post-init, has draft (can /draft-plan, /accept-plan)
#   ACCEPTED, RUNNING, COMPLETED = Post-accept (can do everything)
# =============================================================================

function New-GuardResult {
    <#
    .SYNOPSIS
        Creates a uniform guard result object.
    #>
    param(
        [bool]$Ok = $true,
        [string]$Message = "",
        [string]$Severity = "info",
        [int]$DurationSec = 4
    )
    return @{
        Ok = $Ok
        Message = $Message
        Severity = $Severity
        DurationSec = $DurationSec
    }
}

function Test-CanDraftPlan {
    <#
    .SYNOPSIS
        Guards /draft-plan command using snapshot readiness fields only.
    #>
    param($Snapshot, $State)

    $snap = $Snapshot
    if (-not $snap) { return New-GuardResult -Ok $false -Message "Run /init first" -Severity "warning" }

    $isInitialized = $false
    try { $isInitialized = [bool]$snap.IsInitialized } catch { $isInitialized = $false }

    $blockingFiles = @()
    try { if ($snap.BlockingFiles) { $blockingFiles = @($snap.BlockingFiles) } } catch {}

    $docsAllPassed = $false
    try { $docsAllPassed = [bool]$snap.DocsAllPassed } catch { $docsAllPassed = $false }

    $readinessMode = ""
    try { $readinessMode = [string]$snap.ReadinessMode } catch { $readinessMode = "" }

    # PS5 compat: Where-Object can return $null; wrap and guard the count before using it
    $isBlockingDoc = @($blockingFiles | Where-Object { $_ -in @("PRD","SPEC","DECISION_LOG") })
    $hasBlockingDoc = $isBlockingDoc -and ($isBlockingDoc.Count -gt 0)
    $failOpenBlocked = ($readinessMode -eq "fail-open") -and (-not $docsAllPassed)

    if (-not $isInitialized -or $hasBlockingDoc -or $failOpenBlocked) {
        $msg = "Run /init first"
        if ($isInitialized) {
            if ($hasBlockingDoc) {
                $msg = "BLOCKED: Complete these docs first: " + ($isBlockingDoc -join ", ")
            } elseif ($failOpenBlocked) {
                $msg = "BLOCKED: Complete docs first"
            }
        }
        return New-GuardResult -Ok $false -Message $msg -Severity "warning"
    }

    return New-GuardResult -Ok $true
}

function Test-CanAcceptPlan {
    <#
    .SYNOPSIS
        Guards /accept-plan command. Blocks on readiness and requires draft.
    #>
    param($Snapshot, $State)

    $snap = $Snapshot
    if (-not $snap) { return New-GuardResult -Ok $false -Message "Run /init first" -Severity "warning" }

    $status = if ($snap.PlanState) { $snap.PlanState.Status } else { "" }
    $hasDraft = $snap.PlanState -and $snap.PlanState.HasDraft

    $initGuard = Test-CanDraftPlan -Snapshot $snap -State $State
    if (-not $initGuard.Ok) { return $initGuard }

    if ($status -in @("ACCEPTED", "RUNNING", "COMPLETED")) {
        return New-GuardResult -Ok $false -Message "Plan already accepted" -Severity "info"
    }

    if (-not $hasDraft) {
        return New-GuardResult -Ok $false -Message "Run /draft-plan first" -Severity "warning"
    }

    return New-GuardResult -Ok $true
}

function Test-CanGo {
    <#
    .SYNOPSIS
        Guards /go command. Blocks on readiness and requires plan acceptance.
    #>
    param($Snapshot, $State)

    $snap = $Snapshot
    if (-not $snap) { return New-GuardResult -Ok $false -Message "Run /init first" -Severity "warning" }

    $status = if ($snap.PlanState) { $snap.PlanState.Status } else { "" }

    $initGuard = Test-CanDraftPlan -Snapshot $snap -State $State
    if (-not $initGuard.Ok) { return $initGuard }

    $acceptedStates = @("ACCEPTED", "RUNNING", "COMPLETED")
    if ($status -notin $acceptedStates) {
        return New-GuardResult -Ok $false -Message "Run /accept-plan first" -Severity "warning"
    }

    return New-GuardResult -Ok $true
}
