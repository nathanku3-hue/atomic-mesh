# =============================================================================
# GOLDEN TRANSPLANT: Pipeline Status Reducer (v5 - Full 6-Stage Parity)
# Source: golden Build-PipelineStatus (lines 4558-5100)
#         golden Draw-PipelinePanel (lines 5336-5600)
#         golden Next Hint Chain (lines 4938-5035)
#         golden Optimize stage (lines 4731-4734 - entropy proof markers)
# =============================================================================

<#
.SYNOPSIS
    Computes the pipeline status and returns render directives for the right column.
.DESCRIPTION
    Returns an array of render directives with Text + Color coupled.
    This keeps Print-Row decoupled from pipeline semantics.
.PARAMETER Snapshot
    The UiSnapshot containing plan state, lane metrics, and nuance fields
.RETURNS
    Array of hashtables with Text, Color, and optional StageColors
#>
function Get-PipelineRightColumn {
    param(
        $Snapshot
    )

    # Default directives if no snapshot
    # P7: Compact 6-stage format to fit in right column (35 chars)
    if (-not $Snapshot) {
        return @(
            @{ Text = "PIPELINE"; Color = "Cyan" },
            @{ Text = "Source: unknown"; Color = "DarkGray" },
            @{ Text = ""; Color = "White" },
            @{ Text = "[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]"; Color = "DarkGray"; StageColors = @("GRAY","GRAY","GRAY","GRAY","GRAY","GRAY") },
            @{ Text = ""; Color = "White" },
            @{ Text = "Next: /help"; Color = "Cyan" }
        )
    }

    $planState = $Snapshot.PlanState
    $laneMetrics = $Snapshot.LaneMetrics

    # === COMPUTE TASK COUNTS FOR STAGE LOGIC ===
    $totalTasks = 0
    $queuedCount = 0
    $activeCount = 0
    $blockedCount = 0

    if ($laneMetrics -and $laneMetrics.Count -gt 0) {
        foreach ($lane in $laneMetrics) {
            $totalTasks += $lane.Queued + $lane.Active + $lane.Tokens
            $queuedCount += $lane.Queued
            $activeCount += $lane.Active
            # Blocked tasks are tracked via lane state
            if ($lane.State -eq "BLOCKED") {
                $blockedCount += $lane.Queued + $lane.Active
            }
        }
    }

    # === GOLDEN STAGE COLOR LOGIC (6 stages with dependencies) ===
    # Stage 1: Context
    # GREEN = EXECUTION, YELLOW = BOOTSTRAP, RED = PRE_INIT, GRAY = unknown
    $contextState = switch ($planState.Status) {
        "BOOTSTRAP"  { "YELLOW" }
        "PRE_INIT"   { "RED" }
        { $_ -in "ACCEPTED", "RUNNING", "COMPLETED", "DRAFT" } { "GREEN" }
        default      { "GRAY" }
    }

    # Stage 2: Plan (depends on Context not being RED/GRAY)
    # ACCEPTED = GREEN (plan accepted), DRAFT = YELLOW, ERROR/BLOCKED = RED, otherwise depends on tasks
    $planStage = if ($contextState -in "RED", "GRAY") {
        "GRAY"  # Blocked by Context
    } else {
        switch ($planState.Status) {
            "ACCEPTED" { "GREEN" }  # Plan accepted = Plan stage complete
            "RUNNING"  { "GREEN" }  # Execution in progress = Plan was accepted
            "COMPLETED" { "GREEN" } # All done = Plan was accepted
            "DRAFT"    { "YELLOW" }
            "ERROR"    { "RED" }
            "BLOCKED"  { "RED" }
            default    {
                # No plan yet
                if ($planState.HasDraft) { "YELLOW" }
                else { "RED" }
            }
        }
    }

    # Stage 3: Work (depends on Plan not being RED/GRAY)
    # GREEN = activeCount > 0, YELLOW = queuedCount > 0 but not running, RED = blockedCount > 0
    $workState = if ($planStage -in "RED", "GRAY") {
        "GRAY"  # Blocked by Plan
    } else {
        if ($activeCount -gt 0) { "GREEN" }
        elseif ($blockedCount -gt 0) { "RED" }
        elseif ($queuedCount -gt 0) { "YELLOW" }
        elseif ($planState.Accepted -and $totalTasks -gt 0) { "GREEN" }
        else { "GRAY" }
    }

    # Stage 4: Optimize (P7 - depends on Work, uses entropy proof markers)
    # GOLDEN TRANSPLANT: lines 4731-4734 - entropy proof markers
    # GREEN = has entropy proof, YELLOW = tasks exist but no proof, GRAY = no tasks or Work blocked
    $optimizeState = if ($workState -in "RED", "GRAY") {
        "GRAY"  # Blocked by Work
    } else {
        if ($Snapshot.HasAnyOptimized) { "GREEN" }
        elseif ($Snapshot.OptimizeTotalTasks -gt 0) { "YELLOW" }
        else { "GRAY" }
    }

    # Stage 5: Verify (depends on Optimize not being RED/GRAY)
    # GREEN = no HIGH risk or all verified, RED = HIGH risk unverified, GRAY = no tasks
    # For now: simplified - GRAY if no tasks, GREEN if work done
    $verifyState = if ($optimizeState -in "RED", "GRAY") {
        "GRAY"  # Blocked by Optimize
    } else {
        if ($workState -eq "GREEN") { "GREEN" }
        else { "GRAY" }
    }

    # Stage 6: Ship (depends on Verify, uses GitClean from snapshot)
    # GREEN = git clean & Verify=GREEN, YELLOW = uncommitted changes, RED = Verify=RED, GRAY = Verify=GRAY
    $gitClean = $Snapshot.GitClean
    $shipState = if ($verifyState -eq "GRAY") {
        "GRAY"  # Blocked by Verify
    } elseif ($verifyState -eq "RED") {
        "RED"   # Verify failed
    } elseif ($gitClean) {
        "GREEN" # Ready to ship
    } else {
        "YELLOW" # Uncommitted changes
    }

    $stageColors = @($contextState, $planStage, $workState, $optimizeState, $verifyState, $shipState)

    # === GOLDEN SOURCE DISPLAY (Nuance 2) ===
    # Format: "readiness.py (live) / tasks DB" or "readiness.py (fail-open) / tasks DB"
    $readinessMode = if ($Snapshot.ReadinessMode) { $Snapshot.ReadinessMode } else { "live" }
    $source = "snapshot.py ($readinessMode)"
    if ($planState.PlanId) {
        $source += " / task: $($planState.PlanId)"
    }

    # === GOLDEN NEXT HINT LOGIC (Nuance 4 - 13-step priority chain with Optimize) ===
    # P1: Pass task IDs for actionable hints like /reset T-123
    # P7: Include Optimize stage and FirstUnoptimizedTaskId
    $nextHint = Get-NextHintFromStages -ContextState $contextState -PlanState $planStage -WorkState $workState -OptimizeState $optimizeState -VerifyState $verifyState -ShipState $shipState -PlanStatus $planState.Status -HasDraft $planState.HasDraft -QueuedCount $queuedCount -GitClean $gitClean -FirstBlockedTaskId $Snapshot.FirstBlockedTaskId -FirstErrorTaskId $Snapshot.FirstErrorTaskId -FirstUnoptimizedTaskId $Snapshot.FirstUnoptimizedTaskId

    # === BUILD RENDER DIRECTIVES ===
    # P7: Compact 6-stage format to fit in right column (35 chars)
    return @(
        @{ Text = "PIPELINE"; Color = "Cyan" },
        @{ Text = "Source: $source"; Color = "DarkGray" },
        @{ Text = ""; Color = "White" },
        @{ Text = "[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]"; StageColors = $stageColors },
        @{ Text = ""; Color = "White" },
        @{ Text = "Next: $nextHint"; Color = "Cyan" }
    )
}

<#
.SYNOPSIS
    Returns the next hint based on stage states (13-step priority chain with Optimize).
.DESCRIPTION
    GOLDEN TRANSPLANT: lines 4938-5035
    P7: Added Optimize stage (lines 4731-4734 - entropy proof markers)
    Priority order determines which hint is shown.
#>
function Get-NextHintFromStages {
    param(
        [string]$ContextState,
        [string]$PlanState,
        [string]$WorkState,
        [string]$OptimizeState,
        [string]$VerifyState,
        [string]$ShipState,
        [string]$PlanStatus,
        [bool]$HasDraft,
        [int]$QueuedCount,
        [bool]$GitClean,
        # P1: Task-specific hints
        [string]$FirstBlockedTaskId,
        [string]$FirstErrorTaskId,
        # P7: Optimize stage task ID
        [string]$FirstUnoptimizedTaskId
    )

    # 1. Context=RED → /init
    if ($ContextState -eq "RED") {
        return "/init"
    }

    # 2. Context=YELLOW → /status or edit docs
    if ($ContextState -eq "YELLOW") {
        return "/status"
    }

    # 3-5. Plan stage hints
    if ($PlanState -eq "RED") {
        if ($HasDraft) {
            # 4. Plan=RED + draft exists → /accept-plan
            return "/accept-plan"
        } else {
            # 5. Plan=RED + no draft → /draft-plan
            return "/draft-plan"
        }
    }
    if ($PlanState -eq "YELLOW") {
        # 6. Plan=YELLOW → /accept-plan (draft exists)
        return "/accept-plan"
    }

    # 7-8. Work stage hints
    if ($WorkState -eq "YELLOW") {
        # 7. Work=YELLOW + queued → /go
        return "/go"
    }
    if ($WorkState -eq "RED") {
        # 8. Work=RED → P1: Task-specific hint with ID
        if ($FirstBlockedTaskId) {
            return "/reset $FirstBlockedTaskId"
        }
        if ($FirstErrorTaskId) {
            return "/retry $FirstErrorTaskId"
        }
        return "/status"
    }

    # 9. Optimize=YELLOW → P7: /simplify <id>
    if ($OptimizeState -eq "YELLOW") {
        if ($FirstUnoptimizedTaskId) {
            return "/simplify $FirstUnoptimizedTaskId"
        }
        return "/simplify"
    }

    # 10. Verify=RED → P1: Task-specific hint with ID
    if ($VerifyState -eq "RED") {
        if ($FirstErrorTaskId) {
            return "/verify $FirstErrorTaskId"
        }
        return "/status"
    }

    # 11. Ship=YELLOW → git add . && git commit
    if ($ShipState -eq "YELLOW") {
        return "git commit"
    }

    # 12. Ship=GREEN → /ship
    if ($ShipState -eq "GREEN") {
        return "/ship"
    }

    # 13. All GREEN → ready message
    if ($ContextState -eq "GREEN" -and $PlanState -eq "GREEN" -and $WorkState -eq "GREEN" -and $VerifyState -eq "GREEN") {
        return "/ship"
    }

    # Default fallback based on plan status
    $hint = switch ($PlanStatus) {
        "BOOTSTRAP" { "/status" }
        "UNKNOWN"   { "/draft-plan" }
        "DRAFT"     { "/accept-plan" }
        "ACCEPTED"  { "/go" }
        "RUNNING"   { "(running...)" }
        "COMPLETED" { "/ship" }
        "BLOCKED"   {
            # P1: Include blocked task ID if available
            if ($FirstBlockedTaskId) { "/reset $FirstBlockedTaskId" }
            else { "(blocked)" }
        }
        "ERROR"     {
            # P1: Include error task ID if available
            if ($FirstErrorTaskId) { "/retry $FirstErrorTaskId" }
            else { "/status" }
        }
        default     { "/help" }
    }
    return $hint
}

<#
.SYNOPSIS
    Maps a stage state to console color.
.PARAMETER State
    One of: GREEN, YELLOW, RED, GRAY
#>
function Get-PipelineStageColor {
    param([string]$State)

    # Golden color map (lines 5361-5367)
    switch ($State.ToUpper()) {
        "GREEN"  { return "Green" }
        "YELLOW" { return "Yellow" }
        "RED"    { return "Red" }
        "GRAY"   { return "DarkGray" }
        default  { return "DarkGray" }
    }
}

<#
.SYNOPSIS
    Renders a single pipeline row with stage colors.
.PARAMETER Text
    The text template like "[Ctx] → [Pln] → [Wrk] → [Opt] → [Ver] → [Shp]"
.PARAMETER StageColors
    Array of colors for each stage: @("Green", "Yellow", "DarkGray", "DarkGray", "DarkGray", "DarkGray")
.PARAMETER Row
    Console row to render on
.PARAMETER Col
    Starting column
.PARAMETER Width
    Maximum width for the row
#>
function Render-PipelineStagesRow {
    param(
        [string]$Text,
        [string[]]$StageColors,
        [int]$Row,
        [int]$Col,
        [int]$Width
    )

    if (-not (Get-ConsoleFrameValid)) { return }

    # Stage abbreviations (golden lines 5411-5418 + P7 Optimize)
    # P7: With 6 stages, use compact arrows to fit in right column (35 chars vs 45)
    $stageNames = @("Ctx", "Pln", "Wrk", "Opt", "Ver", "Shp")
    $arrow = "→"  # Compact: no spaces (saves 10 chars for 5 arrows)

    $currentCol = $Col
    for ($i = 0; $i -lt $stageNames.Count; $i++) {
        $stageName = $stageNames[$i]
        $stageText = "[$stageName]"
        $color = if ($StageColors -and $i -lt $StageColors.Count) {
            Get-PipelineStageColor -State $StageColors[$i]
        } else {
            "DarkGray"
        }

        TryWriteAt -Row $Row -Col $currentCol -Text $stageText -Color $color | Out-Null
        $currentCol += $stageText.Length

        # Add arrow between stages (except after last)
        if ($i -lt $stageNames.Count - 1) {
            TryWriteAt -Row $Row -Col $currentCol -Text $arrow -Color "DarkGray" | Out-Null
            $currentCol += $arrow.Length
        }
    }

    # Pad to width
    $remaining = $Width - ($currentCol - $Col)
    if ($remaining -gt 0) {
        TryWriteAt -Row $Row -Col $currentCol -Text (" " * $remaining) -Color "White" | Out-Null
    }
}
