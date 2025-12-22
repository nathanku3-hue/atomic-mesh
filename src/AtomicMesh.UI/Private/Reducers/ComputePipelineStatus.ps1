# =============================================================================
# GOLDEN TRANSPLANT: Pipeline Status Reducer (v5 - Full 6-Stage Parity)
# Source: golden Build-PipelineStatus (lines 4558-5100)
#         golden Draw-PipelinePanel (lines 5336-5600)
#         golden Next Hint Chain (lines 4938-5035)
#         golden Optimize stage (lines 4731-4734 - entropy proof markers)
# P8: Doc readiness panel for pre-draft state (right column)
# =============================================================================

<#
.SYNOPSIS
    Width-safe text truncation with ellipsis.
.PARAMETER Text
    The text to fit within width
.PARAMETER Width
    Maximum allowed width
.RETURNS
    Text truncated with "..." if needed
#>
function Fit-Text {
    param(
        [string]$Text,
        [int]$Width
    )
    if (-not $Text) { return "" }
    if ($Text.Length -le $Width) { return $Text }
    if ($Width -le 3) { return $Text.Substring(0, $Width) }
    return $Text.Substring(0, $Width - 3) + "..."
}

<#
.SYNOPSIS
    Formats a progress bar with microbar and percentage for doc readiness.
.DESCRIPTION
    Golden transplant from control_panel_6990922.ps1 lines 5621-5655
    MicroBar: 5 chars using ■ (filled) and □ (empty), Floor rounding
    Color: GREEN (score >= threshold), YELLOW (score >= 50), RED (else)
.PARAMETER Score
    The readiness score (0-100)
.PARAMETER Threshold
    The threshold to pass (e.g., 80 for PRD/SPEC, 30 for DECISION_LOG)
.PARAMETER Exists
    Whether the file exists (MISS forces display regardless of score)
.RETURNS
    @{ MicroBar; Percentage; Color; StateLabel }
#>
function Format-ProgressBar {
    param(
        [int]$Score,
        [int]$Threshold,
        [bool]$Exists = $true
    )

    # Determine color based on score vs threshold
    $Color = if ($Score -ge $Threshold) { "Green" }
    elseif ($Score -ge 50) { "Yellow" }
    else { "Red" }

    # Determine state label (for accessibility/debugging)
    $StateLabel = if (-not $Exists) { "MISS" }
    elseif ($Score -ge $Threshold) { "OK" }
    elseif ($Score -le 40) { "STUB" }
    else { "NEED" }

    # Calculate filled/empty portions (compact microbar: ■□, max 5 chars)
    # Golden: Floor rounding (no minimum 1 block)
    $MicroWidth = 5
    $Filled = [Math]::Floor($Score / 100 * $MicroWidth)
    $Empty = $MicroWidth - $Filled

    $MicroBar = ""
    if ($Filled -gt 0) { $MicroBar += "■" * $Filled }
    if ($Empty -gt 0) { $MicroBar += "□" * $Empty }

    return @{
        MicroBar   = $MicroBar
        Percentage = "{0,3}%" -f $Score
        Color      = $Color
        StateLabel = $StateLabel
    }
}

<#
.SYNOPSIS
    Generates doc readiness directives with progress bars for the right column.
.DESCRIPTION
    Uses DocScores for rated display with MicroBar + percentage.
    Short labels: PRD, SPEC, DEC (to fit in column width)
.PARAMETER Snapshot
    The UiSnapshot containing DocScores hashtable
.PARAMETER MaxWidth
    Maximum width for each line
.RETURNS
    Array of 3 directives for PRD/SPEC/DECISION_LOG with progress bars
#>
function Get-DocsDirectives {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [int]$MaxWidth = 32
    )

    # Short labels to fit in column (PRD, SPEC, DEC)
    $docLabels = @{
        PRD = "PRD "
        SPEC = "SPEC"
        DECISION_LOG = "DEC "
    }

    $directives = @()

    # Safe property access (strict mode compatible)
    $docScores = $null
    try { $docScores = $Snapshot.DocScores } catch { $docScores = $null }

    # Librarian feedback (optional, from out-of-band cache)
    $librarianFeedback = $null
    try { $librarianFeedback = $Snapshot.LibrarianDocFeedback } catch { $librarianFeedback = $null }

    # Stale indicator: append * when Librarian cache is >10 min old
    $isStale = $false
    try { $isStale = $Snapshot.LibrarianDocFeedbackStale -eq $true } catch { $isStale = $false }

    foreach ($docName in @('PRD', 'SPEC', 'DECISION_LOG')) {
        $docData = if ($docScores) { $docScores[$docName] } else { $null }
        $score = if ($docData) { [int]$docData.score } else { 0 }
        $exists = if ($docData) { [bool]$docData.exists } else { $false }
        $threshold = if ($docData) { [int]$docData.threshold } else { 90 }

        # Hint priority: 1) Librarian one_liner, 2) readiness.py hint
        # Append * when Librarian hint is stale (>10 min old)
        $hint = ""
        $fromLibrarian = $false
        if ($librarianFeedback -and $librarianFeedback[$docName] -and $librarianFeedback[$docName].one_liner) {
            $hint = [string]$librarianFeedback[$docName].one_liner
            $fromLibrarian = $true
        } elseif ($docData -and $docData.hint) {
            $hint = [string]$docData.hint
        } else {
            $hint = "create file"
        }
        # Stale indicator: only for Librarian hints
        if ($fromLibrarian -and $isStale -and $hint) {
            $hint = "$hint*"
        }

        $bar = Format-ProgressBar -Score $score -Threshold $threshold -Exists $exists
        $label = $docLabels[$docName]

        # Truncate hint to max 14 chars (keeps total line under 32 chars)
        # Format: "PRD  ■■■□□  40% hint" = 4 + 5 + 5 + hint
        $maxHintLen = 14
        if ($hint.Length -gt $maxHintLen) {
            $hint = $hint.Substring(0, $maxHintLen - 1) + "…"
        }

        # Format: "PRD  ■■■□□  60% hint"  (label + bar + percent + hint)
        $text = "$label $($bar.MicroBar) $($bar.Percentage) $hint"

        $directives += @{ Text = $text; Color = $bar.Color }
    }

    return $directives
}

<#
.SYNOPSIS
    Returns right column directives for DOCS panel (pre-draft state).
.DESCRIPTION
    Shows doc readiness with progress bars and "Next: /draft-plan" only when
    all docs pass their thresholds (PRD>=80%, SPEC>=80%, DECISION_LOG>=30%).
    Used in pre-draft state instead of PIPELINE panel.
.PARAMETER Snapshot
    The UiSnapshot containing DocScores and DocsAllPassed
.PARAMETER Width
    Maximum width for text lines
.RETURNS
    Array of 6 directives for consistent row count
#>
function Get-DocsRightColumn {
    param(
        $Snapshot,
        [int]$Width = 32
    )

    # Guard nulls robustly (strict mode compatible)
    $planState = $null
    try { $planState = $Snapshot.PlanState } catch { $planState = $null }

    # Get doc status lines with progress bars
    $docsLines = Get-DocsDirectives -Snapshot $Snapshot -MaxWidth $Width

    # B1+B2: Librarian quality indicator + readiness level for DOCS header
    # Format: "DOCS L:4/5 (PASS+)" with optional "*" (stale) or "!" (risks)
    $docsHeader = "DOCS"
    $quality = 0
    $confidence = 0
    $risks = 0
    $stale = $false
    try { $quality = [int]$Snapshot.LibrarianOverallQuality } catch { $quality = 0 }
    try { $confidence = [int]$Snapshot.LibrarianConfidence } catch { $confidence = 0 }
    try { $risks = [int]$Snapshot.LibrarianCriticalRisksCount } catch { $risks = 0 }
    try { $stale = [bool]$Snapshot.LibrarianDocFeedbackStale } catch { $stale = $false }

    # Only show indicator when Librarian data is present (quality or confidence > 0)
    if ($quality -gt 0 -or $confidence -gt 0) {
        $indicator = "L:${quality}/5"
        if ($risks -gt 0) { $indicator += "!" }
        elseif ($stale) { $indicator += "*" }

        # B2: Add readiness level annotation
        $level = Get-DocsReadinessLevel -Snapshot $Snapshot
        # Only show tier label for non-BLOCKED (BLOCKED is doc threshold issue, not librarian)
        if ($level -ne "BLOCKED") {
            $docsHeader = "DOCS $indicator ($level)"
        } else {
            $docsHeader = "DOCS $indicator"
        }
    }

    # Check if all docs pass their thresholds (PRD>=80%, SPEC>=80%, DEC>=30%)
    $allPassed = $false
    try { $allPassed = $Snapshot.DocsAllPassed -eq $true } catch { $allPassed = $false }

    # Check ReadinessMode for degraded states
    $readinessMode = ""
    try { $readinessMode = $Snapshot.ReadinessMode } catch { $readinessMode = "" }

    # Check initialization status
    $isInitialized = $false
    try { $isInitialized = $Snapshot.IsInitialized -eq $true } catch { $isInitialized = $false }

    # No-db mode: show appropriate message based on initialization status
    $isNoDb = $readinessMode -eq "no-db"
    if ($isNoDb) {
        if (-not $isInitialized) {
            # Truly uninitialized: show /init hint
            return @(
                @{ Text = $docsHeader; Color = "Cyan" },
                $docsLines[0],
                $docsLines[1],
                $docsLines[2],
                @{ Text = "tasks.db not found"; Color = "DarkGray" },
                @{ Text = "Next: /init"; Color = "Cyan" }
            )
        }
        # Initialized but no DB yet: show docs status (DB will be created by /draft-plan)
        # Fall through to normal docs display logic below
    }

    # Fail-open mode: show cautious message
    $isFailOpen = $readinessMode -eq "fail-open"
    if ($isFailOpen) {
        $nextText = "Next: /draft-plan (may fail)"
        $nextColor = "DarkGray"
    } elseif ($allPassed) {
        $nextText = "Next: /draft-plan"
        $nextColor = "Cyan"
    } else {
        $nextText = "Next: Complete docs first"
        $nextColor = "DarkGray"
    }

    return @(
        @{ Text = $docsHeader; Color = "Cyan" },
        $docsLines[0],  # PRD  ■■■□□  60%
        $docsLines[1],  # SPEC ■□□□□  20%
        $docsLines[2],  # DEC  ■■□□□  40%
        @{ Text = ""; Color = "DarkGray" },
        @{ Text = $nextText; Color = $nextColor }
    )
}

<#
.SYNOPSIS
    Returns compact docs summary line for pre-draft pipeline display.
.DESCRIPTION
    Format: "Docs: PRD 80|SPEC 60|DEC 40" (with -- for missing scores)
    Width-bounded to fit in right column.
.PARAMETER Snapshot
    The UiSnapshot containing DocScores
.PARAMETER MaxWidth
    Maximum width for the line (default 30)
.RETURNS
    String like "Docs: PRD 80|SPEC 60|DEC 40"
#>
function Get-DocsSummaryLine {
    param(
        $Snapshot,
        [int]$MaxWidth = 30
    )

    # Safe property access
    $docScores = $null
    try { $docScores = $Snapshot.DocScores } catch { $docScores = $null }

    # Short labels
    $labels = @{
        PRD = "PRD"
        SPEC = "SP"
        DECISION_LOG = "DEC"
    }

    $parts = @()
    foreach ($docName in @('PRD', 'SPEC', 'DECISION_LOG')) {
        $docData = if ($docScores) { $docScores[$docName] } else { $null }
        $score = if ($docData -and $docData.exists) { [int]$docData.score } else { $null }
        $label = $labels[$docName]

        # Use -- for missing scores (not 0, avoids misleading "0%")
        $scoreText = if ($null -ne $score) { "$score" } else { "--" }
        $parts += "$label $scoreText"
    }

    $summary = "Docs: " + ($parts -join "|")

    # Truncate if needed
    if ($summary.Length -gt $MaxWidth) {
        $summary = $summary.Substring(0, $MaxWidth)
    }

    return $summary
}

<#
.SYNOPSIS
    Computes the pipeline status and returns render directives for the right column.
.DESCRIPTION
    Returns an array of render directives with Text + Color coupled.
    Always returns PIPELINE (with optional Docs summary line pre-draft).
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
            @{ Text = ""; Color = "DarkGray" },  # No source line in fallback
            @{ Text = ""; Color = "White" },
            @{ Text = "[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]"; Color = "DarkGray"; StageColors = @("GRAY","GRAY","GRAY","GRAY","GRAY","GRAY") },
            @{ Text = ""; Color = "White" },
            @{ Text = "Next: /help"; Color = "Cyan" }
        )
    }

    # Adapter error: suppress doc bars (data is unreliable)
    $hasAdapterError = $false
    try { $hasAdapterError = $Snapshot.AdapterError -and $Snapshot.AdapterError.Length -gt 0 } catch {}
    if (-not $hasAdapterError) {
        try { $hasAdapterError = $Snapshot.Alerts -and $Snapshot.Alerts.AdapterError -and $Snapshot.Alerts.AdapterError.Length -gt 0 } catch {}
    }
    # If docs are already passing and we're in live mode, tolerate transient adapter errors
    try {
        $docsOk = $Snapshot.DocsAllPassed
        $isLive = (-not $Snapshot.ReadinessMode) -or ($Snapshot.ReadinessMode -eq "live")
        if ($hasAdapterError -and $docsOk -and $isLive) {
            # Drop benign doc-gate errors like "Complete docs first"
            if ($Snapshot.AdapterError -match "Complete docs first") {
                $hasAdapterError = $false
            } elseif ($Snapshot.Alerts -and $Snapshot.Alerts.AdapterError -match "Complete docs first") {
                $hasAdapterError = $false
            } else {
                # For other adapter errors, still fail-open if docs are good and mode is live
                $hasAdapterError = $false
            }
        }
    } catch {}
    if ($hasAdapterError) {
        return @(
            @{ Text = "STATUS"; Color = "Cyan" },
            @{ Text = "Backend unavailable"; Color = "Red" },
            @{ Text = ""; Color = "DarkGray" },
            @{ Text = "Check connection and"; Color = "DarkGray" },
            @{ Text = "restart the panel."; Color = "DarkGray" },
            @{ Text = "Next: /status"; Color = "Cyan" }
        )
    }

    # Detect pre-draft state for docs summary line injection
    $planState = $Snapshot.PlanState
    $hasDraft = $planState -and $planState.HasDraft
    $isAccepted = $planState -and $planState.Accepted
    $isPreInit = $planState -and $planState.Status -eq "PRE_INIT"
    $isPreDraft = (-not $hasDraft) -and (-not $isAccepted) -and (-not $isPreInit)

    # Get pipeline summary (always, for all states)
    $summary = Get-PipelineSummary -Snapshot $Snapshot
    if (-not $summary) {
        # Fallback: gray pipeline with docs summary if pre-draft
        $row1Text = if ($isPreDraft) { Get-DocsSummaryLine -Snapshot $Snapshot } else { "" }
        return @(
            @{ Text = "PIPELINE"; Color = "Cyan" },
            @{ Text = $row1Text; Color = "DarkGray" },
            @{ Text = ""; Color = "White" },
            @{ Text = "[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]"; Color = "DarkGray"; StageColors = @("GRAY","GRAY","GRAY","GRAY","GRAY","GRAY") },
            @{ Text = ""; Color = "White" },
            @{ Text = "Next: /help"; Color = "Cyan" }
        )
    }

    $stageColors = $summary.StageColors
    $source = $summary.Source
    $nextHint = $summary.NextHint
    $nextText = if ($nextHint -and $nextHint.Command) { $nextHint.Command } else { "/help" }
    $reasonText = if ($nextHint -and $nextHint.Reason) { $nextHint.Reason } else { "" }
    $reasonColor = if ($reasonText) { "Yellow" } else { "DarkGray" }

    # === BUILD RENDER DIRECTIVES ===
    # Row 1: Docs summary (pre-draft) OR Source (fail-open) OR empty (normal)
    $row1Text = ""
    if ($isPreDraft) {
        $row1Text = Get-DocsSummaryLine -Snapshot $Snapshot
    } elseif ($source) {
        $row1Text = "Source: $source"
    }

    return @(
        @{ Text = "PIPELINE"; Color = "Cyan" },
        @{ Text = $row1Text; Color = "DarkGray" },
        @{ Text = ""; Color = "White" },
        @{ Text = "[Ctx]→[Pln]→[Wrk]→[Opt]→[Ver]→[Shp]"; StageColors = $stageColors },
        @{ Text = "Reason: $reasonText"; Color = $reasonColor },
        @{ Text = "Next: $nextText"; Color = "Cyan" }
    )
}

<#
.SYNOPSIS
    Computes readiness UI presentation values (single source of truth).
.DESCRIPTION
    Returns computed fields for header badge color and source line display.
    Renderers consume these precomputed values - no ad-hoc ReadinessMode checks.
.PARAMETER Snapshot
    The UiSnapshot containing ReadinessMode
.RETURNS
    Hashtable with IsFailOpen, HeaderBadgeColor, SourceLine
#>
function Get-ReadinessUi {
    param($Snapshot)

    $isFailOpen = ($Snapshot -and $Snapshot.ReadinessMode -eq "fail-open")

    return @{
        IsFailOpen = $isFailOpen
        HeaderBadgeColor = if ($isFailOpen) { "Red" } else { $null }
        SourceLine = if ($isFailOpen) { "snapshot.py (fail-open)" } else { "" }
    }
}

function Get-PipelineSummary {
    param($Snapshot)

    if (-not $Snapshot) { return $null }

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
            if ($lane.State -eq "BLOCKED") {
                $blockedCount += $lane.Queued + $lane.Active
            }
        }
    }

    # === GOLDEN STAGE COLOR LOGIC (6 stages with dependencies) ===
    # Context stage: based on initialization status + plan status
    # - IsInitialized=true OR has plan data → GREEN (ready to proceed)
    # - BOOTSTRAP → YELLOW (docs incomplete)
    # - PRE_INIT → RED (not initialized)
    # - Otherwise → GRAY
    $contextState = switch ($planState.Status) {
        "BOOTSTRAP"  { "YELLOW" }
        "PRE_INIT"   { "RED" }
        { $_ -in "ACCEPTED", "RUNNING", "COMPLETED", "DRAFT" } { "GREEN" }
        "MISSING"    { if ($Snapshot.IsInitialized) { "GREEN" } else { "GRAY" } }
        "NO_PLAN"    { if ($Snapshot.IsInitialized) { "GREEN" } else { "GRAY" } }
        default      { "GRAY" }
    }

    $planStage = if ($contextState -in "RED", "GRAY") {
        "GRAY"
    } else {
        switch ($planState.Status) {
            "ACCEPTED" { "GREEN" }
            "RUNNING"  { "GREEN" }
            "COMPLETED" { "GREEN" }
            "DRAFT"    { "YELLOW" }
            "ERROR"    { "RED" }
            "BLOCKED"  { "RED" }
            default    {
                if ($planState.HasDraft) { "YELLOW" }
                else { "RED" }
            }
        }
    }

    $workState = if ($planStage -in "RED", "GRAY") {
        "GRAY"
    } else {
        if ($activeCount -gt 0) { "GREEN" }
        elseif ($blockedCount -gt 0) { "RED" }
        elseif ($queuedCount -gt 0) { "YELLOW" }
        elseif ($planState.Accepted -and $totalTasks -gt 0) { "GREEN" }
        else { "GRAY" }
    }

    $optimizeState = if ($workState -in "RED", "GRAY") {
        "GRAY"
    } else {
        if ($Snapshot.HasAnyOptimized) { "GREEN" }
        elseif ($Snapshot.OptimizeTotalTasks -gt 0) { "YELLOW" }
        else { "GRAY" }
    }

    $verifyState = if ($optimizeState -in "RED", "GRAY") {
        "GRAY"
    } else {
        if ($workState -eq "GREEN") { "GREEN" }
        else { "GRAY" }
    }

    $gitClean = $Snapshot.GitClean
    $shipState = if ($verifyState -eq "GRAY") {
        "GRAY"
    } elseif ($verifyState -eq "RED") {
        "RED"
    } elseif ($gitClean) {
        "GREEN"
    } else {
        "YELLOW"
    }

    $stageColors = @($contextState, $planStage, $workState, $optimizeState, $verifyState, $shipState)

    # Readiness UI: Only show source in fail-open mode (single source of truth)
    $readinessUi = Get-ReadinessUi -Snapshot $Snapshot
    $source = $readinessUi.SourceLine
    if ($source -and $planState.PlanId) {
        $source += " / task: $($planState.PlanId)"
    }

    $nextHint = Get-NextHintFromStages -ContextState $contextState -PlanState $planStage -WorkState $workState -OptimizeState $optimizeState -VerifyState $verifyState -ShipState $shipState -PlanStatus $planState.Status -HasDraft $planState.HasDraft -PlanAccepted $planState.Accepted -QueuedCount $queuedCount -GitClean $gitClean -FirstBlockedTaskId $Snapshot.FirstBlockedTaskId -FirstErrorTaskId $Snapshot.FirstErrorTaskId -FirstUnoptimizedTaskId $Snapshot.FirstUnoptimizedTaskId

    $stageStates = @(
        @{ name = "Context"; state = $contextState },
        @{ name = "Plan"; state = $planStage },
        @{ name = "Work"; state = $workState },
        @{ name = "Optimize"; state = $optimizeState },
        @{ name = "Verify"; state = $verifyState },
        @{ name = "Ship"; state = $shipState }
    )

    return @{
        StageStates = $stageStates
        StageColors = $stageColors
        Source = $source
        NextHint = $nextHint
        ReadinessUi = $readinessUi  # For header badge color override
        Counts = @{
            queued  = $queuedCount
            active  = $activeCount
            blocked = $blockedCount
            total   = $totalTasks
        }
    }
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
        [bool]$PlanAccepted,
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
        return @{ Command = "/init"; Reason = "Context not ready"; Stage = "Context" }
    }

    # 2. Context=YELLOW → /status or edit docs
    if ($ContextState -eq "YELLOW") {
        return @{ Command = "/status"; Reason = "Complete context docs"; Stage = "Context" }
    }

    # 3-5. Plan stage hints
    if ($PlanState -eq "RED") {
        if ($HasDraft) {
            return @{ Command = "/accept-plan"; Reason = "Draft exists, accept plan"; Stage = "Plan" }
        } else {
            return @{ Command = "/draft-plan"; Reason = "No draft plan yet"; Stage = "Plan" }
        }
    }
    if ($PlanState -eq "YELLOW") {
        return @{ Command = "/accept-plan"; Reason = "Draft ready to accept"; Stage = "Plan" }
    }

    # 7-8. Work stage hints
    if ($WorkState -eq "YELLOW") {
        if ($PlanAccepted) {
            # Already in work mode - awaiting task execution
            return @{ Command = "/status"; Reason = "Tasks queued ($QueuedCount)"; Stage = "Work" }
        }
        return @{ Command = "/go"; Reason = "Queued work available"; Stage = "Work" }
    }
    if ($WorkState -eq "RED") {
        if ($FirstBlockedTaskId) {
            return @{ Command = "/reset $FirstBlockedTaskId"; Reason = "Blocked task detected"; Stage = "Work" }
        }
        if ($FirstErrorTaskId) {
            return @{ Command = "/retry $FirstErrorTaskId"; Reason = "Error task detected"; Stage = "Work" }
        }
        return @{ Command = "/status"; Reason = "Work blocked"; Stage = "Work" }
    }

    # 9. Optimize=YELLOW → P7: /simplify <id>
    if ($OptimizeState -eq "YELLOW") {
        if ($FirstUnoptimizedTaskId) {
            return @{ Command = "/simplify $FirstUnoptimizedTaskId"; Reason = "Add entropy proof"; Stage = "Optimize" }
        }
        return @{ Command = "/simplify"; Reason = "Optimize tasks"; Stage = "Optimize" }
    }

    # 10. Verify=RED → P1: Task-specific hint with ID
    if ($VerifyState -eq "RED") {
        if ($FirstErrorTaskId) {
            return @{ Command = "/verify $FirstErrorTaskId"; Reason = "Verify failing task"; Stage = "Verify" }
        }
        return @{ Command = "/status"; Reason = "Verification issues"; Stage = "Verify" }
    }

    # 11. Ship=YELLOW → git add . && git commit
    if ($ShipState -eq "YELLOW") {
        return @{ Command = "git commit"; Reason = "Uncommitted changes"; Stage = "Ship" }
    }

    # 12. Ship=GREEN → /ship
    if ($ShipState -eq "GREEN") {
        return @{ Command = "/ship"; Reason = "All checks green"; Stage = "Ship" }
    }

    # 13. All GREEN → ready message
    if ($ContextState -eq "GREEN" -and $PlanState -eq "GREEN" -and $WorkState -eq "GREEN" -and $VerifyState -eq "GREEN") {
        return @{ Command = "/ship"; Reason = "All stages green"; Stage = "Ship" }
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
            if ($FirstBlockedTaskId) { "/reset $FirstBlockedTaskId" }
            else { "(blocked)" }
        }
        "ERROR"     {
            if ($FirstErrorTaskId) { "/retry $FirstErrorTaskId" }
            else { "/status" }
        }
        default     { "/help" }
    }
    return @{
        Command = $hint
        Reason = "Based on plan status"
        Stage = "Plan"
    }
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

# =============================================================================
# Tier 2: Docs Readiness Level (NOT RENDERED YET - for future use)
# =============================================================================

<#
.SYNOPSIS
    Computes 4-tier readiness level from snapshot fields.
    NOT RENDERED YET - for future use in Step B.
.DESCRIPTION
    Tiers:
    - BLOCKED: DocsAllPassed = false (docs below threshold)
    - PASS: Basic docs pass, no Librarian data or low confidence
    - PASS+: High quality (4+/5) + high confidence (80%+)
    - REVIEW: Has critical risks flagged by Librarian
.PARAMETER Snapshot
    The UiSnapshot with DocScores and Librarian Tier 2 fields
.RETURNS
    String: BLOCKED | PASS | PASS+ | REVIEW
#>
function Get-DocsReadinessLevel {
    param($Snapshot)

    # Guard: no snapshot
    if (-not $Snapshot) { return "BLOCKED" }

    # BLOCKED: DocsAllPassed = false
    $docsAllPassed = $false
    try { $docsAllPassed = [bool]$Snapshot.DocsAllPassed } catch { $docsAllPassed = $false }
    if (-not $docsAllPassed) { return "BLOCKED" }

    # Check Librarian Tier 2 fields
    $quality = 0
    $confidence = 0
    $risks = 0
    try { $quality = [int]$Snapshot.LibrarianOverallQuality } catch { $quality = 0 }
    try { $confidence = [int]$Snapshot.LibrarianConfidence } catch { $confidence = 0 }
    try { $risks = [int]$Snapshot.LibrarianCriticalRisksCount } catch { $risks = 0 }

    # Check if any Librarian data is present (not coupled to LibrarianDocFeedbackPresent)
    $hasLibrarianData = ($quality -gt 0) -or ($confidence -gt 0)

    # PASS: No Librarian data or low confidence (<50)
    if (-not $hasLibrarianData -or $confidence -lt 50) { return "PASS" }

    # REVIEW: Has critical risks
    if ($risks -gt 0) { return "REVIEW" }

    # PASS+: High quality (4+/5) + high confidence (80%+)
    if ($quality -ge 4 -and $confidence -ge 80) { return "PASS+" }

    # Default to PASS
    return "PASS"
}
