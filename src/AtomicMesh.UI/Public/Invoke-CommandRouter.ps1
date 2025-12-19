# P3: Command feedback icons (GOLDEN NUANCE)
$script:Icons = @{
    Success = [char]0x2705  # ✅
    Error   = [char]0x274C  # ❌
    Warning = [char]0x26A0  # ⚠️
    Info    = [char]0x2139  # ℹ️
    Running = [char]0x23F3  # ⏳
}

function Invoke-CommandRouter {
    param(
        [string]$Command,
        [UiState]$State,
        [UiSnapshot]$Snapshot
    )

    if (-not $Command) { return "noop" }
    $trimmed = $Command.Trim()
    if (-not $trimmed) { return "noop" }

    $state = if ($State) { $State } else { [UiState]::new() }
    $snapshotRef = if ($Snapshot) { $Snapshot } else { [UiSnapshot]::new() }

    $cmdText = $trimmed
    if ($cmdText.StartsWith("/")) {
        $cmdText = $cmdText.Substring(1)
    }

    $parts = $cmdText.Split(" ", 2, [System.StringSplitOptions]::RemoveEmptyEntries)
    $verb = $parts[0].ToLowerInvariant()

    $logMessage = "/$verb"

    switch ($verb) {
        "plan" {
            # Golden Contract: /plan switches to PLAN page
            $state.SetPage("PLAN")
            $state.OverlayMode = "None"
            $state.Toast.Set("$($script:Icons.Success) Switched to PLAN", "info", 2)
            $logMessage = "Routed to PLAN"
        }
        "draft-plan" {
            $state.SetPage("PLAN")
            # P5: Show blocking files when BLOCKED/BOOTSTRAP
            $planStatus = $snapshotRef.PlanState.Status
            if ($planStatus -in @("BLOCKED", "BOOTSTRAP", "PRE_INIT")) {
                $blockingFiles = $snapshotRef.BlockingFiles
                if ($blockingFiles -and $blockingFiles.Count -gt 0) {
                    $filesList = ($blockingFiles -join ", ")
                    $state.Toast.Set("$($script:Icons.Warning) BLOCKED: Complete these docs first: $filesList", "warning", 6)
                    $logMessage = "Draft blocked by: $filesList"
                } else {
                    $state.Toast.Set("$($script:Icons.Warning) BLOCKED: Context docs incomplete", "warning", 5)
                    $logMessage = "Draft blocked (no specific files)"
                }
            } else {
                $state.Toast.Set("$($script:Icons.Running) Drafting plan...", "info", 3)
                $logMessage = "Draft plan requested"
            }
        }
        "accept-plan" {
            $snapshotRef.PlanState.Accepted = $true
            $snapshotRef.PlanState.Status = "ACCEPTED"
            $snapshotRef.PlanState.NextHint = "/go"
            # P6: Show task count in feedback
            $taskCount = 0
            if ($snapshotRef.LaneMetrics -and $snapshotRef.LaneMetrics.Count -gt 0) {
                foreach ($lane in $snapshotRef.LaneMetrics) {
                    $taskCount += $lane.Queued + $lane.Active + $lane.Tokens
                }
            }
            if ($taskCount -gt 0) {
                $state.Toast.Set("$($script:Icons.Success) Plan accepted - Created $taskCount task(s)", "info", 3)
                $logMessage = "Accepted plan with $taskCount tasks"
            } else {
                $state.Toast.Set("$($script:Icons.Success) Plan accepted", "info", 3)
                $logMessage = "Accepted plan"
            }
        }
        "go" {
            # P2: /go retry logic (3 retries, 100ms delays for DB locks)
            $maxRetries = 3
            $retryDelayMs = 100
            $success = $false
            $lastError = $null

            for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                try {
                    # Golden Contract: /go SWITCHES to GO page
                    $state.SetPage("GO")
                    $success = $true
                    break
                }
                catch {
                    $lastError = $_.Exception.Message
                    if ($attempt -lt $maxRetries) {
                        Start-Sleep -Milliseconds $retryDelayMs
                    }
                }
            }

            if ($success) {
                $state.Toast.Set("$($script:Icons.Success) Execution started", "info", 2)
                $logMessage = "Go executed"
            }
            else {
                $state.Toast.Set("$($script:Icons.Error) Go failed: $lastError", "error", 5)
                $logMessage = "Go failed after $maxRetries retries"
            }
        }
        "help" {
            # Check for --all flag
            $showAll = $parts.Count -gt 1 -and $parts[1] -match "(?i)--all"

            if ($showAll) {
                # /help --all: Show full command catalog with descriptions
                $allCommands = Get-PickerCommands -Filter ""
                $helpText = "All commands:`n"
                foreach ($cmd in $allCommands) {
                    $helpText += "  /$($cmd.Name) - $($cmd.Desc)`n"
                }
                $state.Toast.Set($helpText.TrimEnd(), "info", 10)
                $logMessage = "Help --all shown"
            }
            else {
                # /help: Show curated command list (most common)
                $curatedCommands = @(
                    "/help       - Show available commands",
                    "/draft-plan - Create a new plan draft",
                    "/accept-plan- Accept the current draft",
                    "/go         - Start execution",
                    "/plan       - Switch to PLAN page",
                    "/quit       - Exit the control panel"
                )
                $state.Toast.Set(($curatedCommands -join "`n"), "info", 8)
                $logMessage = "Help shown"
            }
        }
        "status" {
            $state.Toast.Set("$($script:Icons.Info) Status refreshed", "info", 2)
            $logMessage = "Status requested"
        }
        "clear" {
            if ($state.EventLog -and $state.EventLog.Events) {
                $state.EventLog.Events.Clear()
            }
            $state.Toast.ClearIfExpired([datetime]::UtcNow) | Out-Null
            $state.Toast.Set("$($script:Icons.Success) Logs cleared", "info", 2)
            $logMessage = "Cleared logs"
        }
        "simplify" {
            # P7: /simplify command for Optimize stage
            $taskId = if ($parts.Count -gt 1) { $parts[1] } else { $snapshotRef.FirstUnoptimizedTaskId }
            if ($taskId) {
                $state.Toast.Set("$($script:Icons.Running) Simplifying task $taskId...", "info", 3)
                $logMessage = "Simplify task: $taskId"
            }
            else {
                $state.Toast.Set("$($script:Icons.Info) No tasks need optimization", "info", 2)
                $logMessage = "No tasks to simplify"
            }
        }
        "ship" {
            # P4: /ship HIGH risk blocking
            $highRiskCount = $snapshotRef.HighRiskUnverifiedCount
            if ($highRiskCount -gt 0) {
                $state.Toast.Set("$($script:Icons.Error) Cannot ship: $highRiskCount HIGH risk task(s) unverified", "error", 5)
                $logMessage = "Ship blocked: $highRiskCount HIGH risk unverified"
            }
            elseif (-not $snapshotRef.GitClean) {
                $state.Toast.Set("$($script:Icons.Warning) Uncommitted changes - run git commit first", "warning", 4)
                $logMessage = "Ship blocked: uncommitted changes"
            }
            else {
                $state.Toast.Set("$($script:Icons.Success) Ready to ship!", "info", 3)
                $logMessage = "Ship ready"
            }
        }
        "quit" {
            $logMessage = "Quit requested"
            if ($state.Toast) {
                $state.Toast.Set("$($script:Icons.Info) Exiting...", "info", 1)
            }
            if ($state.EventLog) {
                $state.EventLog.Add([UiEvent]::new("Shutdown requested", "info"))
            }
            return "quit"
        }
        default {
            $state.Toast.Set("$($script:Icons.Error) Unknown command: /$verb", "error", 4)
            $logMessage = "Unknown command /$verb"
        }
    }

    if ($state.EventLog) {
        $state.EventLog.Add([UiEvent]::new($logMessage, "info"))
    }

    if ($state.Cache -and -not $state.Cache.Metadata) {
        $state.Cache.Metadata = @{}
    }
    if ($state.Cache) {
        $state.Cache.Metadata["LastCommand"] = "/$verb"
    }

    return "ok"
}
