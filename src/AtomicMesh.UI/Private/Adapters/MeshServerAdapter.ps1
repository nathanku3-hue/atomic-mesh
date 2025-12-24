# =============================================================================
# MeshServerAdapter: Backend calls to mesh_server.py for plan operations
# =============================================================================
# v20.0: Eliminates silent failures by calling real backend
# v20.1: Fixed structural bug - nested functions now at module scope
#
# Pattern: ProcessStartInfo + timeout (same as RealAdapter.ps1)
# Returns structured results, never throws to caller.
# =============================================================================

function Get-MeshServerPath {
    <#
    .SYNOPSIS
        Locates mesh_server.py relative to module location.
    #>
    # MeshServerAdapter.ps1 is at: src/AtomicMesh.UI/Private/Adapters/
    # mesh_server.py is at: repo root (4 levels up)
    $moduleRoot = $PSScriptRoot
    $moduleRoot = Split-Path -Parent $moduleRoot  # Adapters/ -> Private/
    $moduleRoot = Split-Path -Parent $moduleRoot  # Private/ -> AtomicMesh.UI/
    $moduleRoot = Split-Path -Parent $moduleRoot  # AtomicMesh.UI/ -> src/
    $moduleRoot = Split-Path -Parent $moduleRoot  # src/ -> repo root
    return $moduleRoot
}

function Get-LatestDraftPlan {
    <#
    .SYNOPSIS
        Finds most recent draft_*.md in docs/PLANS/.
        Golden reference: lines 9976-9990
    .OUTPUTS
        Full path to latest draft, or $null if none exists.
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$ProjectPath
    )

    $baseDir = if ($ProjectPath) { $ProjectPath } else { (Get-Location).Path }
    $plansDir = Join-Path $baseDir "docs\PLANS"

    if (-not (Test-Path $plansDir)) {
        return $null
    }

    $draft = Get-ChildItem $plansDir -Filter "draft_*.md" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending |
             Select-Object -First 1

    if ($draft) {
        return $draft.FullName
    }
    return $null
}

function Invoke-DraftPlan {
    <#
    .SYNOPSIS
        Calls mesh_server.draft_plan() to create a new plan draft.
        Golden reference: lines 3775-3872
    .OUTPUTS
        Hashtable with: Ok, Status, Path, Message, BlockingFiles, TaskCount
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutMs = 2000
    )

    $result = @{
        Ok = $false
        Status = "ERROR"
        Path = $null
        Message = ""
        BlockingFiles = @()
        TaskCount = 0
    }

    # Check for existing draft first (golden pattern)
    $existingDraft = Get-LatestDraftPlan -ProjectPath $ProjectPath
    if ($existingDraft) {
        $result.Ok = $true
        $result.Status = "EXISTS"
        $result.Path = $existingDraft
        $result.Message = "Draft already exists"
        return $result
    }

    # Locate mesh_server.py
    $moduleRoot = Get-MeshServerPath
    $meshServerPath = Join-Path $moduleRoot "mesh_server.py"

    if (-not (Test-Path $meshServerPath)) {
        $result.Message = "Backend not found: mesh_server.py"
        return $result
    }

    # Build python command (golden pattern with logging suppression)
    # v21.0: Suppress INFO logging to prevent log pollution before JSON output
    $escapedRoot = $moduleRoot -replace "\\", "\\\\"
    $pyCode = "import sys, logging; logging.disable(logging.INFO); sys.path.insert(0, r'$moduleRoot'); from mesh_server import draft_plan; print(draft_plan())"

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "python"
        $psi.Arguments = "-c `"$pyCode`""
        $psi.WorkingDirectory = $ProjectPath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            $result.Message = "Failed to start Python process"
            return $result
        }

        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch {}
            $result.Message = "Backend timeout (${TimeoutMs}ms)"
            return $result
        }

        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()

        if ($proc.ExitCode -ne 0) {
            $errLine = if ($stderr) { ($stderr -split "`n")[0] } else { "exit $($proc.ExitCode)" }
            $result.Message = "Backend error: $errLine"
            return $result
        }

        if (-not $stdout) {
            $result.Message = "Backend returned empty output"
            return $result
        }

        # Parse JSON response
        try {
            $response = $stdout | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            # Extract first line for diagnostic
            $firstLine = ($stdout -split "`n")[0]
            if ($firstLine.Length -gt 80) { $firstLine = $firstLine.Substring(0, 80) + "..." }
            $result.Message = "Invalid JSON: $firstLine"
            return $result
        }

        # Handle response statuses (golden pattern: lines 3806-3826)
        switch ($response.status) {
            "OK" {
                $result.Ok = $true
                $result.Status = "OK"
                $result.Path = $response.path
                $result.Message = $response.message
                $result.TaskCount = if ($response.task_count) { [int]$response.task_count } else { 0 }
            }
            "BLOCKED" {
                $result.Status = "BLOCKED"
                $result.Message = if ($response.message) { $response.message } else { "Context docs incomplete" }
                if ($response.blocking_files) {
                    $result.BlockingFiles = @($response.blocking_files)
                }
            }
            "ERROR" {
                $result.Message = if ($response.message) { $response.message } else { "Unknown error" }
            }
            default {
                $result.Message = "Unexpected status: $($response.status)"
            }
        }
    }
    catch {
        $result.Message = "Exception: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-AcceptPlan {
    <#
    .SYNOPSIS
        Calls mesh_server.accept_plan() to hydrate DB from plan file.
        Golden reference: lines 3874-3968
    .OUTPUTS
        Hashtable with: Ok, Status, CreatedCount, Message, SkippedDuplicates
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath,

        [Parameter(Mandatory=$true)]
        [string]$PlanPath,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutMs = 3000
    )

    $result = @{
        Ok = $false
        Status = "ERROR"
        CreatedCount = 0
        SkippedDuplicates = 0
        Message = ""
    }

    # Validate plan path exists
    if (-not (Test-Path $PlanPath)) {
        $result.Message = "Plan file not found: $PlanPath"
        return $result
    }

    # Locate mesh_server.py
    $moduleRoot = Get-MeshServerPath

    # Build python command (golden pattern with raw string for Windows paths)
    # v20.0: Use raw string r'...' for Windows path to avoid backslash escape issues
    # v21.0: Suppress INFO logging to prevent log pollution before JSON output
    $escapedPath = $PlanPath -replace "'", "''"
    $pyCode = "import sys, logging; logging.disable(logging.INFO); sys.path.insert(0, r'$moduleRoot'); from mesh_server import accept_plan; print(accept_plan(r'$escapedPath'))"

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "python"
        $psi.Arguments = "-c `"$pyCode`""
        $psi.WorkingDirectory = $ProjectPath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            $result.Message = "Failed to start Python process"
            return $result
        }

        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch {}
            $result.Message = "Backend timeout (${TimeoutMs}ms)"
            return $result
        }

        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()

        if ($proc.ExitCode -ne 0) {
            $errLine = if ($stderr) { ($stderr -split "`n")[0] } else { "exit $($proc.ExitCode)" }
            $result.Message = "Backend error: $errLine"
            return $result
        }

        if (-not $stdout) {
            $result.Message = "Backend returned empty output"
            return $result
        }

        # Parse JSON response
        try {
            $response = $stdout | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            $firstLine = ($stdout -split "`n")[0]
            if ($firstLine.Length -gt 80) { $firstLine = $firstLine.Substring(0, 80) + "..." }
            $result.Message = "Invalid JSON: $firstLine"
            return $result
        }

        # Handle response statuses (golden pattern: lines 3912-3952)
        switch ($response.status) {
            "OK" {
                $result.Ok = $true
                $result.Status = "OK"
                $result.CreatedCount = if ($response.created_count) { [int]$response.created_count } else { 0 }
                $result.SkippedDuplicates = if ($response.skipped_duplicates) { [int]$response.skipped_duplicates } else { 0 }
                $result.Message = "Accepted"
            }
            "BLOCKED" {
                $result.Status = "BLOCKED"
                $result.Message = if ($response.message) { $response.message } else { "Plan blocked" }
            }
            "ALREADY_ACCEPTED" {
                $result.Status = "ALREADY_ACCEPTED"
                $result.Message = if ($response.message) { $response.message } else { "Plan already accepted" }
            }
            "ERROR" {
                $result.Message = if ($response.message) { $response.message } else { "Unknown error" }
            }
            default {
                $result.Message = "Unexpected status: $($response.status)"
            }
        }
    }
    catch {
        $result.Message = "Exception: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-PickTask {
    <#
    .SYNOPSIS
        Calls mesh_server.pick_task_braided() to claim the next task.
        Golden reference: lines 1556-1650 and 1596-1599 (scheduler call + retries).
    .OUTPUTS
        Hashtable with: Ok, Status, Task, Message, PendingTotal, NoWorkReason, Error, ParseError, Raw
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath,

        [Parameter(Mandatory=$false)]
        [string]$WorkerId = "control_panel",

        [Parameter(Mandatory=$false)]
        [string]$DbPath = $null,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutMs = 2000
    )

    $result = @{
        Ok = $false
        Status = "ERROR"
        Task = $null
        Message = ""
        PendingTotal = $null
        NoWorkReason = $null
        Error = $null
        ParseError = $false
        Raw = ""
    }

    $moduleRoot = Get-MeshServerPath
    $meshServerPath = Join-Path $moduleRoot "mesh_server.py"
    if (-not (Test-Path $meshServerPath)) {
        $result.Message = "Backend not found: mesh_server.py"
        return $result
    }

    $dbPath = Get-DbPath -DbPath $DbPath -ProjectPath $ProjectPath

    $maxRetries = 3
    $retryDelayMs = 500
    $lastError = ""

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            # Build python command (logging suppressed to avoid toast pollution)
            $pyCode = "import sys, logging; logging.disable(logging.INFO); sys.path.insert(0, r'$moduleRoot'); from mesh_server import pick_task_braided; print(pick_task_braided('$WorkerId'))"

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = "python"
            $psi.Arguments = "-c `"$pyCode`""
            $psi.WorkingDirectory = $ProjectPath
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.CreateNoWindow = $true
            if ($dbPath) {
                $psi.EnvironmentVariables["ATOMIC_MESH_DB"] = $dbPath
            }

            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc) {
                $result.Message = "Failed to start Python process"
                return $result
            }

            if (-not $proc.WaitForExit($TimeoutMs)) {
                try { $proc.Kill() } catch {}
                $result.Message = "Scheduler timeout (${TimeoutMs}ms)"
                return $result
            }

            $stdout = $proc.StandardOutput.ReadToEnd().Trim()
            $stderr = $proc.StandardError.ReadToEnd().Trim()
            $result.Raw = $stdout

            if ($proc.ExitCode -ne 0) {
                $errLine = if ($stderr) { ($stderr -split "`n")[0] } else { "exit $($proc.ExitCode)" }
                $result.Message = "Backend error: $errLine"
                $lastError = $result.Message
                # Retry on locked/busy signals in stderr
                if ($errLine -match "locked|busy|timeout" -and $attempt -lt $maxRetries) {
                    Start-Sleep -Milliseconds $retryDelayMs
                    continue
                }
                return $result
            }

            if (-not $stdout) {
                $result.Message = "Backend returned empty output"
                return $result
            }

            # Parse JSON response
            $response = $null
            try {
                $response = $stdout | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                $firstLine = ($stdout -split "`n")[0]
                if ($firstLine.Length -gt 160) { $firstLine = $firstLine.Substring(0, 160) + "..." }
                $result.Message = "Invalid JSON: $firstLine"
                $result.ParseError = $true
                $lastError = $result.Message
                if ($attempt -lt $maxRetries) {
                    Start-Sleep -Milliseconds $retryDelayMs
                    continue
                }
                return $result
            }

            # StrictMode-safe accessor for optional JSON fields
            $getProp = {
                param($obj, [string]$name)
                if (-not $obj -or -not $obj.PSObject) { return $null }
                $prop = $obj.PSObject.Properties[$name]
                if ($prop) { return $prop.Value }
                return $null
            }

            $statusRaw = & $getProp $response "status"
            $status = if ($statusRaw) { $statusRaw.ToString().ToUpperInvariant() } else { "" }
            $result.Status = $status

            switch ($status) {
                "OK" {
                    $result.Ok = $true
                    $id = & $getProp $response "id"
                    $lane = & $getProp $response "lane"
                    $desc = & $getProp $response "description"
                    $preempted = & $getProp $response "preempted"
                    $strictness = & $getProp $response "strictness"
                    $priority = & $getProp $response "priority"
                    $pointerIndex = & $getProp $response "pointer_index"
                    $decisionReason = & $getProp $response "decision_reason"
                    $msg = & $getProp $response "message"

                    $result.Task = @{
                        Id = if ($id) { [string]$id } else { "" }
                        Lane = if ($lane) { [string]$lane } else { "" }
                        Description = if ($desc) { [string]$desc } else { "" }
                        Preempted = [bool]$preempted
                        Strictness = if ($strictness) { [string]$strictness } else { "" }
                        Priority = if ($priority -ne $null) { [int]$priority } else { $null }
                        PointerIndex = if ($pointerIndex -ne $null) { [int]$pointerIndex } else { $null }
                        DecisionReason = if ($decisionReason) { [string]$decisionReason } else { "" }
                    }
                    $result.Message = if ($msg) { [string]$msg } else { "Task picked" }
                    return $result
                }
                "NO_WORK" {
                    $result.Ok = $true
                    $pendingTotal = & $getProp $response "pending_total"
                    $noWorkReason = & $getProp $response "no_work_reason"
                    $msg = & $getProp $response "message"
                    $result.PendingTotal = if ($pendingTotal -ne $null) { [int]$pendingTotal } else { $null }
                    $result.NoWorkReason = if ($noWorkReason) { [string]$noWorkReason } else { "" }
                    $result.Message = if ($msg) { [string]$msg } else { "No work available" }
                    return $result
                }
                "ERROR" {
                    $err = & $getProp $response "error"
                    $msg = & $getProp $response "message"
                    $result.Error = if ($err) { [string]$err } else { "" }
                    $result.Message = if ($msg) { [string]$msg } else { "Scheduler error" }
                    $lastError = $result.Message
                    if ($result.Message -match "locked|busy|timeout" -and $attempt -lt $maxRetries) {
                        Start-Sleep -Milliseconds $retryDelayMs
                        continue
                    }
                    return $result
                }
                default {
                    $result.Message = "Unexpected status: $status"
                    return $result
                }
            }
        }
        catch {
            $lastError = $_.Exception.Message
            $result.Message = "Exception: $lastError"
            if ($lastError -match "locked|busy|timeout" -and $attempt -lt $maxRetries) {
                Start-Sleep -Milliseconds $retryDelayMs
                continue
            }
            return $result
        }
    }

    # Fall-through if retries exhausted
    if (-not $result.Message -and $lastError) {
        $result.Message = $lastError
    }
    return $result
}

function Invoke-CheckGoBlockers {
    <#
    .SYNOPSIS
        Runs safety gates before /go:
        1) Pending RED decisions (blocks until /decide)
        2) Auditor escalations or tasks with high retry (blocks until /reset)
    .OUTPUTS
        Hashtable with: Status (OK|DECISION|STUCK|ERROR), Decision, Task, Message
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectPath,

        [Parameter(Mandatory=$false)]
        [string]$DbPath = $null,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutMs = 1200
    )

    $result = @{
        Status = "ERROR"
        Decision = $null
        Task = $null
        Message = ""
    }

    $dbPathResolved = Get-DbPath -DbPath $DbPath -ProjectPath $ProjectPath
    if (-not $dbPathResolved) {
        $result.Message = "DB path not resolved"
        return $result
    }

    $pyCode = @"
import os, json, sqlite3
db = os.environ.get('ATOMIC_MESH_DB', r'$dbPathResolved')
try:
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    dec = cur.execute(\"SELECT id, question FROM decisions WHERE status='pending' AND priority='red' LIMIT 1\").fetchone()
    if dec:
        print(json.dumps({'status':'DECISION','decision':{'id': dec['id'], 'question': dec['question']}}))
        conn.close()
        raise SystemExit
    stuck = cur.execute(\"SELECT id, desc FROM tasks WHERE auditor_status='escalated' OR retry_count >= 3 LIMIT 1\").fetchone()
    if stuck:
        print(json.dumps({'status':'STUCK','task':{'id': stuck['id'], 'desc': stuck['desc']}}))
        conn.close()
        raise SystemExit
    conn.close()
    print(json.dumps({'status':'OK'}))
except Exception as e:
    print(json.dumps({'status':'ERROR','message': str(e)[:200]}))
"@

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = "python"
        $psi.Arguments = "-c `"$pyCode`""
        $psi.WorkingDirectory = $ProjectPath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["ATOMIC_MESH_DB"] = $dbPathResolved

        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            $result.Message = "Failed to start Python process"
            return $result
        }

        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch {}
            $result.Message = "Blocker check timeout (${TimeoutMs}ms)"
            return $result
        }

        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        $stderr = $proc.StandardError.ReadToEnd().Trim()

        if ($proc.ExitCode -ne 0 -and -not $stdout) {
            $errLine = if ($stderr) { ($stderr -split "`n")[0] } else { "exit $($proc.ExitCode)" }
            $result.Message = "Blocker check error: $errLine"
            return $result
        }

        if (-not $stdout) {
            $result.Message = "Blocker check returned empty output"
            return $result
        }

        try {
            $resp = $stdout | ConvertFrom-Json -ErrorAction Stop
            $status = if ($resp.status) { $resp.status.ToString().ToUpperInvariant() } else { "" }
            $result.Status = $status
            switch ($status) {
                "DECISION" { $result.Decision = $resp.decision; $result.Message = "Decision blocker" }
                "STUCK"    { $result.Task = $resp.task; $result.Message = "Stuck task" }
                "OK"       { $result.Message = "OK" }
                default    { $result.Message = if ($resp.message) { [string]$resp.message } else { "Unknown blocker status" } }
            }
        }
        catch {
            $firstLine = ($stdout -split "`n")[0]
            if ($firstLine.Length -gt 160) { $firstLine = $firstLine.Substring(0, 160) + "..." }
            $result.Status = "ERROR"
            $result.Message = "Invalid blocker JSON: $firstLine"
        }
    }
    catch {
        $result.Status = "ERROR"
        $result.Message = $_.Exception.Message
    }

    return $result
}
