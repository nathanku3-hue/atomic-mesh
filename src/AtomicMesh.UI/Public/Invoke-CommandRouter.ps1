# ---------------------------------------------------------
# COMPONENT: INTERFACE (sys:cli)
# FILE: Invoke-CommandRouter.ps1
# MAPPING: User CLI, Command Parsing, State Dispatch
# EXPORTS: Invoke-CommandRouter
# CONSUMES: sys:scheduler
# VERSION: v22.0
# ---------------------------------------------------------
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
        $State,
        $Snapshot,
        # Injectable gate for /go safety check (tests can stub this)
        [scriptblock]$GoBlockerCheck = $null
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

    # Extract paths from state metadata (fallback to cwd when missing)
    $projectPath = $null
    $moduleRoot = $null
    if ($state.Cache -and $state.Cache.Metadata) {
        $projectPath = $state.Cache.Metadata["ProjectPath"]
        $moduleRoot = $state.Cache.Metadata["ModuleRoot"]
    }
    if (-not $projectPath) {
        $projectPath = (Get-Location).Path
    }

    # Fallback: derive ModuleRoot from script location if not in metadata
    if (-not $moduleRoot) {
        $moduleRoot = Split-Path -Parent $PSScriptRoot   # Public/ → AtomicMesh.UI/
        $moduleRoot = Split-Path -Parent $moduleRoot     # AtomicMesh.UI/ → src/
        $moduleRoot = Split-Path -Parent $moduleRoot     # src/ → repo root
    }

    # Extract args (everything after verb)
    $cmdArgs = if ($parts.Count -gt 1) { $parts[1] } else { "" }

    switch ($verb) {
        "init" {
            # Check if already initialized (uses projectPath for detection)
            $initStatus = Test-RepoInitialized -Path $projectPath -RepoRoot $moduleRoot

            if ($initStatus.initialized -and $cmdArgs -notmatch "--force") {
                $state.Toast.Set("$($script:Icons.Warning) Already initialized ($($initStatus.reason)). Use --force to re-scaffold.", "warning", 5)
                $logMessage = "Init blocked: $($initStatus.reason)"
            }
            else {
                # Perform initialization
                # - Path = projectPath (where docs/ will be created)
                # - TemplateRoot = moduleRoot (where library/templates/ lives)
                $forceFlag = $cmdArgs -match "--force"
                $initResult = Invoke-ProjectInit -Path $projectPath -TemplateRoot $moduleRoot -Force:$forceFlag

                if ($initResult.Success) {
                    $createdCount = $initResult.Created.Count
                    $skippedCount = $initResult.Skipped.Count
                    $state.Toast.Set("$($script:Icons.Success) Initialized: $createdCount created, $skippedCount skipped", "info", 4)
                    $logMessage = "Init success: $($initResult.Created -join ', ')"

                    # Leave BOOTSTRAP and go to PLAN
                    $state.SetPage("PLAN")
                    # Force immediate data refresh to update snapshot status
                    $state.ForceDataRefresh = $true
                    $state.MarkDirty("content")
                }
                else {
                    $state.Toast.Set("$($script:Icons.Error) Init failed: $($initResult.Error)", "error", 5)
                    $logMessage = "Init failed: $($initResult.Error)"
                }
            }
        }
        "plan" {
            # Golden Contract: /plan switches to PLAN page
            $state.SetPage("PLAN")
            $state.OverlayMode = "None"
            $state.Toast.Set("$($script:Icons.Success) Switched to PLAN", "info", 2)
            $logMessage = "Routed to PLAN"
        }
        "draft-plan" {
            # v20.0: Real backend call (no more silent no-op)
            # Guard: must be post-init
            $guard = Test-CanDraftPlan -Snapshot $snapshotRef -State $state

            if (-not $guard.Ok) {
                $icon = if ($guard.Severity -eq "warning") { $script:Icons.Warning } else { $script:Icons.Info }
                $msg = if ($guard.Message) { $guard.Message } else { "Draft blocked" }
                $state.Toast.Set("$icon $msg", $guard.Severity, $guard.DurationSec)
                $logMessage = "Draft blocked: $msg"
            }
            else {
                $state.SetPage("PLAN")
                # Call backend to create draft
                $draftResult = Invoke-DraftPlan -ProjectPath $projectPath

                switch ($draftResult.Status) {
                    "OK" {
                        $leafName = Split-Path $draftResult.Path -Leaf
                        $state.Toast.Set("$($script:Icons.Success) Draft created: $leafName", "info", 5)
                        $state.ForceDataRefresh = $true
                        $logMessage = "Draft created: $($draftResult.Path)"
                    }
                    "EXISTS" {
                        $leafName = Split-Path $draftResult.Path -Leaf
                        $state.Toast.Set("$($script:Icons.Info) Draft exists: $leafName (run /accept-plan)", "info", 4)
                        $logMessage = "Draft already exists: $($draftResult.Path)"
                    }
                    "BLOCKED" {
                        $filesList = if ($draftResult.BlockingFiles.Count -gt 0) {
                            $draftResult.BlockingFiles -join ", "
                        } else { "context docs" }
                        $state.Toast.Set("$($script:Icons.Warning) BLOCKED: Complete $filesList first", "warning", 6)
                        $logMessage = "Draft blocked: $filesList"
                    }
                    default {
                        # ERROR or unexpected
                        $msg = if ($draftResult.Message) { $draftResult.Message } else { "Unknown error" }
                        $state.Toast.Set("$($script:Icons.Error) Draft failed: $msg", "error", 5)
                        $logMessage = "Draft error: $msg"
                    }
                }
            }
        }
        "accept-plan" {
            # v20.0: Real backend call (no more local-only state mutation)
            # Guard: must have draft + not already accepted
            $guard = Test-CanAcceptPlan -Snapshot $snapshotRef -State $state
            $expectedCreated = 0
            try {
                foreach ($laneMetric in @($snapshotRef.LaneMetrics)) {
                    if ($laneMetric -and $laneMetric.Queued) {
                        $expectedCreated += [int]$laneMetric.Queued
                    }
                }
            } catch {}
            if (-not $guard.Ok) {
                $icon = if ($guard.Severity -eq "warning") { $script:Icons.Warning } else { $script:Icons.Info }
                $msg = if ($guard.Message) { $guard.Message } else { "Accept blocked" }
                $state.Toast.Set("$icon $msg", $guard.Severity, $guard.DurationSec)
                $logMessage = "Accept blocked: $msg"
            }
            else {
                # Get latest draft path (golden pattern: lines 3879-3890)
                $planPath = Get-LatestDraftPlan -ProjectPath $projectPath
                if (-not $planPath) {
                    $state.Toast.Set("$($script:Icons.Warning) No draft found. Run /draft-plan first", "warning", 4)
                    $logMessage = "Accept blocked: no draft"
                }
                else {
                    # Call backend to accept plan and hydrate DB
                    $acceptResult = Invoke-AcceptPlan -ProjectPath $projectPath -PlanPath $planPath

                    switch ($acceptResult.Status) {
                        "OK" {
                            $count = if ($acceptResult.CreatedCount -gt 0) { $acceptResult.CreatedCount } else { $expectedCreated }
                            if ($acceptResult.CreatedCount -le 0 -and $expectedCreated -gt 0) {
                                $fallbackMsg = "Backend missing created_count; used lane queued total $expectedCreated"
                                if ($state.EventLog) {
                                    $state.EventLog.Add([UiEvent]::new($fallbackMsg, "info"))
                                }
                                $logMessage = "Accepted plan with fallback count ($fallbackMsg)"
                            }
                            $state.Toast.Set("$($script:Icons.Success) Accepted: $count task(s) created", "info", 4)
                            $state.ForceDataRefresh = $true
                            if (-not $logMessage) {
                                $logMessage = "Accepted plan: $count tasks created"
                            }
                        }
                        "ALREADY_ACCEPTED" {
                            $state.Toast.Set("$($script:Icons.Info) Plan already accepted", "info", 3)
                            $logMessage = "Plan already accepted"
                        }
                        "BLOCKED" {
                            $msg = if ($acceptResult.Message) { $acceptResult.Message } else { "Plan blocked" }
                            $state.Toast.Set("$($script:Icons.Warning) BLOCKED: $msg", "warning", 5)
                            $logMessage = "Accept blocked: $msg"
                        }
                        default {
                            # ERROR or unexpected
                            $msg = if ($acceptResult.Message) { $acceptResult.Message } else { "Unknown error" }
                            if ($expectedCreated -gt 0) {
                                $msg = "$msg (expected $expectedCreated task(s))"
                            }
                            $state.Toast.Set("$($script:Icons.Error) Accept failed: $msg", "error", 5)
                            $logMessage = "Accept error: $msg"
                        }
                    }
                }
            }
        }
        "go" {
            # Guard: must have accepted plan before /go
            $setToast = {
                param($msg, $severity = "info", $dur = 4)
                if ($state -and $state.Toast -and $state.Toast.Set) {
                    $state.Toast.Set($msg, $severity, $dur)
                }
                else {
                    Write-Host $msg -ForegroundColor Cyan
                }
            }

            # Refresh snapshot from tools/snapshot.py to avoid stale readiness/docs state
            try {
                $moduleRootFresh = $PSScriptRoot | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent
                $snapScript = Join-Path $moduleRootFresh "tools\snapshot.py"
                if (Test-Path $snapScript) {
                    $rawSnapText = python $snapScript "$projectPath" 2>$null | Out-String
                    if ($rawSnapText) {
                        try {
                            $rawSnapObj = $rawSnapText | ConvertFrom-Json -ErrorAction Stop
                            $snapshotRef = Convert-RawSnapshotToUi -Raw $rawSnapObj
                        } catch {}
                    }
                }
            } catch {}

            # Debug: show readiness inputs
            try {
                $dbgInit = $false
                $dbgDocs = $false
                $dbgMode = ""
                $dbgBlocks = @()
                try { $dbgInit = [bool]$snapshotRef.IsInitialized } catch {}
                try { $dbgDocs = [bool]$snapshotRef.DocsAllPassed } catch {}
                try { $dbgMode = [string]$snapshotRef.ReadinessMode } catch {}
                try { if ($snapshotRef.BlockingFiles) { $dbgBlocks = @($snapshotRef.BlockingFiles) } } catch {}
                Write-Host ("Go guard snapshot: IsInitialized={0} DocsAllPassed={1} ReadinessMode={2} BlockingFiles={3}" -f $dbgInit, $dbgDocs, $dbgMode, ($dbgBlocks -join ",")) -ForegroundColor DarkGray
            } catch {}

            $guard = Test-CanGo -Snapshot $snapshotRef -State $state
            if (-not $guard.Ok) {
                Write-Host "Go blocked (guard): $($guard.Message)" -ForegroundColor Yellow
                $icon = if ($guard.Severity -eq "warning") { $script:Icons.Warning } else { $script:Icons.Info }
                & $setToast "$icon $($guard.Message)" $guard.Severity $guard.DurationSec
                $logMessage = "Go blocked: $($guard.Message)"
            }
            else {
                Write-Host "Go starting orchestration..." -ForegroundColor Cyan
                $dbPathForGo = $null
                if ($state.Cache -and $state.Cache.Metadata) { $dbPathForGo = $state.Cache.Metadata["DbPath"] }

                # Safety gates: decision blockers and auditor escalations
                # Injectable for testing - default uses real blocker check
                $blockCheck = if ($GoBlockerCheck) {
                    & $GoBlockerCheck $projectPath $dbPathForGo
                } else {
                    Invoke-CheckGoBlockers -ProjectPath $projectPath -DbPath $dbPathForGo
                }
                switch ($blockCheck.Status) {
                    "DECISION" {
                        $dec = $blockCheck.Decision
                        $id = if ($dec -and $dec.id) { $dec.id } else { "?" }
                        $question = if ($dec -and $dec.question) { $dec.question } else { "" }
                        Write-Host "Go blocked: decision [$id] $question" -ForegroundColor Yellow
                        & $setToast "🔴 Decision required: [$id] $question" "error" 6
                        if ($state.EventLog) {
                            $state.EventLog.Add([UiEvent]::new("Go blocked: decision [$id] $question", "warning"))
                        }
                        $logMessage = "Go blocked: decision [$id]"
                        break
                    }
                    "STUCK" {
                        $task = $blockCheck.Task
                        $id = if ($task -and $task.id) { $task.id } else { "?" }
                        $desc = if ($task -and $task.desc) { $task.desc } else { "" }
                        Write-Host "Go blocked: stuck task T-$id $desc" -ForegroundColor Yellow
                        & $setToast "🔴 STUCK: Auditor escalated T-$id" "error" 6
                        if ($state.EventLog) {
                            $state.EventLog.Add([UiEvent]::new("Go blocked: stuck task T-$id $desc".Trim(), "warning"))
                        }
                        $logMessage = "Go blocked: stuck task T-$id"
                        break
                    }
                    "ERROR" {
                        $msg = if ($blockCheck.Message) { $blockCheck.Message } else { "Blocker check failed" }
                        Write-Host "Go blocked: safety check error: $msg" -ForegroundColor Yellow
                        & $setToast "$($script:Icons.Warning) Go safety check failed: $msg" "warning" 5
                        if ($state.EventLog) {
                            $state.EventLog.Add([UiEvent]::new("Go safety check failed: $msg", "warning"))
                        }
                        $logMessage = "Go blocked: safety check error"
                        break
                    }
                }

                if ($blockCheck.Status -ne "OK") {
                    Write-Host " Blocked: $($blockCheck.Message)" -ForegroundColor Red
                    return
                }

                # v24.0: Queue-aware orchestration using ToolLauncher (multi-lane aware)
                # Get paths for worker spawn + launcher bridge
                $moduleRoot = if ($state.Cache -and $state.Cache.Metadata) {
                    $state.Cache.Metadata["ModuleRoot"]
                } else {
                    $PSScriptRoot | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent
                }
                $workerPath = Join-Path $moduleRoot "worker.ps1"
                $launcherPath = Join-Path $moduleRoot "ToolLauncher\Launcher.ps1"
                $dbPathResolved = Get-DbPath -DbPath $dbPathForGo -ProjectPath $projectPath
                Write-Host "Go paths: moduleRoot=$moduleRoot worker=$workerPath launcher=$launcherPath db=$dbPathResolved" -ForegroundColor DarkGray

                if (-not (Test-Path $workerPath)) {
                    Write-Host "Go failed: worker not found at $workerPath" -ForegroundColor Red
                    $state.Toast.Set("$($script:Icons.Error) Worker not found: $workerPath", "error", 5)
                    $logMessage = "Go failed: worker.ps1 not found"
                    return
                }

                # Helper: query pending tasks by lane directly from DB
                $queueSummary = @{
                    Status = "ERROR"
                    Message = ""
                    Lanes = @{}
                }
                try {
                    $pyCode = @"
import os, json, sqlite3
db = os.environ.get('ATOMIC_MESH_DB', r'$dbPathResolved')
out = {'status': 'ERROR', 'lanes': {}}
try:
    conn = sqlite3.connect(db)
    cur = conn.cursor()
    rows = cur.execute("select lower(trim(coalesce(lane,''))) as lane, count(*) from tasks where status='pending' group by lane").fetchall()
    lanes = {}
    for lane, count in rows:
        key = (lane or '').strip().lower() or 'backend'
        lanes[key] = int(count)
    out['status'] = 'OK'
    out['lanes'] = lanes
    conn.close()
except Exception as e:
    out['message'] = str(e)[:200]
print(json.dumps(out))
"@

                    $tmpPy = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "mesh_queue_{0}.py" -f ([Guid]::NewGuid().ToString("N")))
                    Set-Content -Path $tmpPy -Value $pyCode -Encoding UTF8 -Force

                    $psiQueue = [System.Diagnostics.ProcessStartInfo]::new()
                    $psiQueue.FileName = "python"
                    $psiQueue.Arguments = "`"$tmpPy`""
                    $psiQueue.WorkingDirectory = $projectPath
                    $psiQueue.UseShellExecute = $false
                    $psiQueue.RedirectStandardOutput = $true
                    $psiQueue.RedirectStandardError = $true
                    $psiQueue.CreateNoWindow = $true
                    $psiQueue.EnvironmentVariables["ATOMIC_MESH_DB"] = $dbPathResolved

                    $procQueue = [System.Diagnostics.Process]::Start($psiQueue)
                    if ($procQueue -and $procQueue.WaitForExit(1500)) {
                        $stdoutQ = $procQueue.StandardOutput.ReadToEnd().Trim()
                        $stderrQ = $procQueue.StandardError.ReadToEnd().Trim()
                        $exitQ = $procQueue.ExitCode
                        if ($stdoutQ) {
                            $queueParsed = $stdoutQ | ConvertFrom-Json -ErrorAction Stop
                            $queueSummary.Status = if ($queueParsed.status) { $queueParsed.status.ToString().ToUpperInvariant() } else { "ERROR" }
                            if ($queueParsed.lanes) { $queueSummary.Lanes = $queueParsed.lanes }
                            if ($queueParsed.message) { $queueSummary.Message = [string]$queueParsed.message }
                        }
                        else {
                            if ($stderrQ) {
                                $firstErr = ($stderrQ -split "`n")[0]
                                $queueSummary.Message = "Queue query stderr: $firstErr"
                            }
                            else {
                                $queueSummary.Message = "Queue query returned no output (exit $exitQ)"
                            }
                        }
                    }
                    else {
                        $queueSummary.Message = "Queue query timed out"
                    }
                    Remove-Item $tmpPy -ErrorAction SilentlyContinue
                }
                catch {
                    $queueSummary.Message = $_.Exception.Message
                }

                if ($queueSummary.Status -ne "OK") {
                    $msg = if ($queueSummary.Message) { $queueSummary.Message } else { "Queue query failed" }
                    Write-Host "Go queue check failed: $msg" -ForegroundColor Yellow
                    & $setToast "$($script:Icons.Warning) Queue check failed: $msg" "warning" 5
                    $logMessage = "Go blocked: queue query error"
                    return
                }

                try {
                    # Build lane-aware worker plan
                    $laneCounts = @{}
                    if ($queueSummary.Lanes) {
                        $laneKeys = @()
                        $laneIsDict = $queueSummary.Lanes -is [System.Collections.IDictionary]
                        if ($laneIsDict) {
                            $laneKeys = $queueSummary.Lanes.Keys
                        }
                        else {
                            $laneKeys = $queueSummary.Lanes.PSObject.Properties.Name
                        }
                        foreach ($k in $laneKeys) {
                            $laneKey = $k.ToLowerInvariant()
                            $laneVal = 0
                            if ($laneIsDict) {
                                $laneVal = $queueSummary.Lanes[$k]
                            }
                            else {
                                $prop = $queueSummary.Lanes.PSObject.Properties[$k]
                                if ($prop) { $laneVal = $prop.Value }
                            }
                            $laneCounts[$laneKey] = [int]$laneVal
                        }
                    }
                    $laneReport = $laneCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "  $($_.Name): $($_.Value)" }
                    if (-not $laneReport) { $laneReport = @('  (none)') }
                    Write-Host "Go queue lanes:`n$($laneReport -join "`n")" -ForegroundColor DarkGray

                    function Get-RecommendedCount([int]$queued) {
                        if ($queued -le 0) { return 0 }
                        $c = [math]::Ceiling($queued / 3.0)
                        if ($c -gt 3) { $c = 3 }
                        return [int][math]::Max(1, $c)
                    }

                    $maxWorkers = 9  # testing cap to avoid swarm overload
                    $planEntries = New-Object System.Collections.Generic.List[object]
                    $summaryLines = New-Object System.Collections.Generic.List[string]
                    $backendQueued = if ($laneCounts.ContainsKey("backend")) { $laneCounts["backend"] } else { 0 }
                    $opsQueued = if ($laneCounts.ContainsKey("ops")) { $laneCounts["ops"] } else { 0 }
                    $frontendQueued = if ($laneCounts.ContainsKey("frontend")) { $laneCounts["frontend"] } else { 0 }
                    $docsQueued = 0
                    if ($laneCounts.ContainsKey("docs")) { $docsQueued += $laneCounts["docs"] }
                    if ($laneCounts.ContainsKey("librarian")) { $docsQueued += $laneCounts["librarian"] }
                    $qaQueued = if ($laneCounts.ContainsKey("qa")) { $laneCounts["qa"] } else { 0 }

                    $requests = @(
                        @{ tool="codex"; type="backend"; lane="Backend"; queued=$backendQueued; want=(Get-RecommendedCount $backendQueued) },
                        @{ tool="codex"; type="ops";     lane="Ops";     queued=$opsQueued;     want=(Get-RecommendedCount $opsQueued) },
                        @{ tool="claude"; type="frontend";lane="Frontend";queued=$frontendQueued;want=(Get-RecommendedCount $frontendQueued) },
                        @{ tool="claude"; type="docs";    lane="Docs";    queued=$docsQueued;    want=(Get-RecommendedCount $docsQueued) },
                        @{ tool="codex"; type="qa";       lane="QA";      queued=$qaQueued;      want=(Get-RecommendedCount $qaQueued) }
                    )

                    $totalPlanned = 0
                    foreach ($req in $requests) {
                        $remaining = $maxWorkers - $totalPlanned
                        if ($remaining -le 0) { break }
                        $alloc = [Math]::Min([int]$req.want, $remaining)
                        if ($alloc -le 0) { continue }
                        for ($i = 0; $i -lt $alloc; $i++) {
                            $titleIdx = $i + 1
                            $planEntries.Add([pscustomobject]@{
                                Tool        = $req.tool
                                Type        = $req.type
                                ProjectPath = $projectPath
                                Title       = "$($req.tool) ($($req.type)) #$titleIdx"
                                Command     = "`$env:ATOMIC_MESH_DB = '$dbPathResolved'; & '$workerPath' -Type $($req.type) -Tool $($req.tool) -ProjectPath '$projectPath' -SingleShot"
                            })
                        }
                        $totalPlanned += $alloc
                        $summaryLines.Add("   - $($req.lane): $($req.queued) task(s) -> Launch ${alloc}x $($req.tool.ToUpper()) ($($req.type))")
                    }
                    $desiredTotal = 0
                    foreach ($req in $requests) {
                        if ($req -and $req.ContainsKey('want') -and $req.want -ne $null) {
                            $desiredTotal += [int]$req.want
                        }
                    }
                    if ($totalPlanned -lt $desiredTotal) {
                        $summaryLines.Add("   - Capped to $maxWorkers worker(s) for test mode")
                    }

                    if ($planEntries.Count -eq 0) {
                        Write-Host "Go: no pending tasks detected in DB." -ForegroundColor Yellow
                        & $setToast "$($script:Icons.Info) No pending tasks to launch" "info" 4
                        $logMessage = "Go skipped: zero queued tasks"
                        return
                    }

                    $summaryText = "📊 Workload Detected:`n" + ($summaryLines -join "`n")
                    Write-Host ""
                    Write-Host $summaryText -ForegroundColor Cyan
                    # Non-blocking: auto-accept (prompting would freeze UI thread)
                    & $setToast $summaryText "info" 6

                # Prefer ToolLauncher for layout-aware spawning; fallback to direct spawns
                $pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
                $launcherExists = Test-Path $launcherPath
                $goDebugLog = Join-Path $projectPath "logs\go_debug.log"
                "$(Get-Date -Format o) launcherPath=$launcherPath exists=$launcherExists moduleRoot=$moduleRoot" | Out-File $goDebugLog -Append
                Write-Host "Go: launcherPath=$launcherPath exists=$launcherExists" -ForegroundColor Magenta
                if ($launcherExists) {
                    try {
                        # Ensure log directory for capturing fast-failing stderr
                        $logDir = Join-Path $projectPath "logs"
                        if (-not (Test-Path $logDir)) {
                            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
                        }

                        # Build codex plan per entry (one window per lane, cap enforced above)
                        # MCP is configured via ~/.codex/config.toml, not CLI flags
                        $planItems = @()
                        $workerIndex = 0
                        $serverScript = "$moduleRoot\tools\stdio_server.py"
                        foreach ($entry in $planEntries) {
                            $laneType = $entry.Type
                            $workerIndex++
                            # Unique log file per worker (add index to prevent collision)
                            $logFile = Join-Path $logDir ("go_{0}_{1}_{2}.log" -f $laneType, (Get-Date -Format "yyyyMMdd_HHmmss"), $workerIndex)
                            $rolePrompt = "You are a $laneType worker daemon. Immediately call pick_task_braided with worker_type='$laneType' to get a task. Execute the task, then call complete_task. Loop forever: pick -> execute -> complete -> pick again. Start NOW by calling pick_task_braided."
                            # Configure MCP server dynamically, then run codex
                            $cmdText = @"
`$ErrorActionPreference = 'Continue'
`$env:ATOMIC_MESH_DB = '$dbPathResolved'
if (-not (Test-Path '$logDir')) { New-Item -ItemType Directory -Force -Path '$logDir' | Out-Null }
"`$(Get-Date -Format o) lane=$laneType worker=$workerIndex starting" | Out-File -FilePath '$logFile' -Append

# Add MCP server for this session (if not already configured)
Write-Host "Configuring MCP server..." -ForegroundColor Cyan
codex mcp add mesh_$laneType --env ATOMIC_MESH_DB='$dbPathResolved' -- python "$serverScript" --db-path "$dbPathResolved" 2>&1 | Out-Null

# Run codex in interactive TUI mode (no piping - codex requires a real terminal)
Write-Host "Starting codex for $laneType lane..." -ForegroundColor Green
Write-Host "Log file: $logFile" -ForegroundColor DarkGray
codex --dangerously-bypass-approvals-and-sandbox -m gpt-5.1-codex-max "$rolePrompt"
`$exitCode = `$LASTEXITCODE
"`$(Get-Date -Format o) lane=$laneType worker=$workerIndex exited with code `$exitCode" | Out-File -FilePath '$logFile' -Append
if (`$exitCode -ne 0) { Write-Host "codex exit `$exitCode" -ForegroundColor Red; Start-Sleep -Seconds 3600 }
"@.Trim()

                            $planItems += [pscustomobject]@{
                                Tool        = "codex"
                                Type        = $laneType
                                ProjectPath = $entry.ProjectPath
                                Title       = "$($entry.Tool) ($laneType)"
                                Command     = $cmdText
                            }
                        }

                        $planJson = $planItems | ConvertTo-Json -Depth 6 -Compress
                        $planEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($planJson))
                        Start-Process $pwshExe -ArgumentList @(
                            "-NoProfile",
                            "-File", $launcherPath,
                            "-CommandPlanBase64", $planEncoded
                        ) -WorkingDirectory (Split-Path $launcherPath -Parent)

                        Write-Host "Go launching $($planEntries.Count) window(s) via ToolLauncher." -ForegroundColor Green
                        & $setToast "$($script:Icons.Success) Launched $($planEntries.Count) window(s) via ToolLauncher" "info" 4
                        if ($state.EventLog) {
                            $state.EventLog.Add([UiEvent]::new("Go launched $($planEntries.Count) worker window(s) via ToolLauncher", "info"))
                        }
                        $state.ForceDataRefresh = $true
                        $logMessage = "Go launched swarm via ToolLauncher"
                    }
                    catch {
                        $errMsg = $_.Exception.Message
                        "$(Get-Date -Format o) ERROR ToolLauncher: $errMsg" | Out-File $goDebugLog -Append
                        $_ | Out-File $goDebugLog -Append
                        Write-Host "Go: ToolLauncher spawn failed: $errMsg" -ForegroundColor Yellow
                        & $setToast "$($script:Icons.Warning) ToolLauncher spawn failed: $errMsg" "warning" 5
                        $logMessage = "Go warning: launcher spawn failed"
                    }
                }
                else {
                    "$(Get-Date -Format o) FALLBACK: launcher not found" | Out-File $goDebugLog -Append
                        # Fallback: spawn workers directly (no layout aid)
                        foreach ($entry in $planItems) {
                            try {
                                $workerCmd = $entry.Command
                                Start-Process $pwshExe -ArgumentList @(
                                    "-NoExit",
                                    "-Command", $workerCmd
                                ) -WorkingDirectory $entry.ProjectPath
                                Start-Sleep -Milliseconds 300
                            }
                            catch {
                                $errMsg = $_.Exception.Message
                                Write-Host "Go: worker launch failed: $errMsg" -ForegroundColor Yellow
                                & $setToast "$($script:Icons.Warning) Worker launch failed: $errMsg" "warning" 5
                            }
                        }
                        Write-Host "Go launched $($planEntries.Count) window(s) via direct fallback." -ForegroundColor Green
                        & $setToast "$($script:Icons.Success) Launched $($planEntries.Count) window(s)" "info" 4
                        $logMessage = "Go launched swarm (direct fallback)"
                        $state.ForceDataRefresh = $true
                    }
                }
                catch {
                    $errMsg = $_.Exception.Message
                    $fullErr = $_ | Out-String
                    "$(Get-Date -Format o) OUTER CATCH: $errMsg`n$fullErr" | Out-File $goDebugLog -Append
                    Write-Host "Go orchestration failed: $errMsg" -ForegroundColor Red
                    & $setToast "$($script:Icons.Error) Go orchestration failed: $errMsg" "error" 6
                    $logMessage = "Go failed: $errMsg"
                }
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
                    "/stream be  - View backend worker logs",
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
        "stream" {
            # Golden Parity: /stream backend|frontend - show worker logs
            $streamType = if ($cmdArgs) { $cmdArgs.ToLowerInvariant() } else { "" }
            $validTypes = @("backend", "be", "frontend", "fe")

            if ($streamType -eq "be") { $streamType = "backend" }
            if ($streamType -eq "fe") { $streamType = "frontend" }

            if ($streamType -notin @("backend", "frontend")) {
                $state.Toast.Set("$($script:Icons.Warning) Usage: /stream backend|frontend", "warning", 4)
                $logMessage = "Stream: invalid type '$streamType'"
            }
            else {
                # Find latest log file matching *-<type>.log
                $logsDir = Join-Path $projectPath "logs"
                $logPattern = "*-$streamType.log"
                $logFile = $null

                if (Test-Path $logsDir) {
                    $logFile = Get-ChildItem "$logsDir\$logPattern" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1
                }

                if (-not $logFile) {
                    $state.Toast.Set("$($script:Icons.Info) No logs for $streamType worker", "info", 4)
                    $logMessage = "Stream: no logs for $streamType"
                }
                else {
                    # Read tail 15 lines
                    $lines = Get-Content $logFile.FullName -Tail 15 -ErrorAction SilentlyContinue
                    $lineCount = if ($lines) { $lines.Count } else { 0 }

                    # Add to event log for visibility
                    if ($state.EventLog) {
                        $state.EventLog.Add([UiEvent]::new("=== $($streamType.ToUpper()) STREAM ($lineCount lines) ===", "info"))
                        foreach ($line in $lines) {
                            $state.EventLog.Add([UiEvent]::new("  $line", "info"))
                        }
                    }

                    $state.Toast.Set("$($script:Icons.Success) Loaded $lineCount lines from $($logFile.Name)", "info", 4)
                    $logMessage = "Stream: loaded $lineCount lines from $($logFile.Name)"
                }
            }
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
