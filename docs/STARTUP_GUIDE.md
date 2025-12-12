# Atomic Mesh Startup Guide (v13.0.1)

**Purpose:** Unified startup system for mesh server + interactive interfaces.

---

## Quick Start

### Windows

```powershell
# Option 1: Batch file (easiest)
.\mesh.bat

# Option 2: PowerShell script directly
.\start_mesh.ps1

# Option 3: Server only (no UI)
.\start_mesh.ps1 -ServerOnly
```

### What Gets Launched

The unified startup automatically launches **3 components**:

1. **Mesh Server** (background, minimized)
   - MCP server handling all task operations
   - SQLite database management
   - Task state machine
   - Review gate enforcement

2. **Control Panel** (interactive CLI)
   - Slash commands (`/go`, `/status`, `/ship`, etc.)
   - Natural language routing
   - Task management interface
   - Human decision gate

3. **Dashboard** (live TUI)
   - Real-time execution metrics
   - Worker status indicators
   - Cognitive state monitoring
   - Live audit log stream

---

## Component Details

### 1. Mesh Server (`mesh_server.py`)

**What it does:**
- Hosts MCP tools for AI agents
- Manages task lifecycle (PENDING → IN_PROGRESS → REVIEWING → COMPLETED)
- Enforces governance rules (One Gavel, Single-Writer discipline)
- Runs background worker processes

**When to restart:**
- After code changes to `mesh_server.py`
- After database schema migrations
- If server becomes unresponsive

**How to check status:**
```powershell
# Check if running
Get-Process python | Where-Object { $_.CommandLine -like "*mesh_server*" }

# Kill if needed
Stop-Process -Id <PID>
```

### 2. Control Panel (`control_panel.ps1`)

**What it does:**
- Provides human interface to mesh operations
- Executes slash commands
- Routes natural language to AI
- Displays formatted status dashboards

**Key Commands:**
```
/go         Execute next pending task
/status     Show system status
/ship       Pre-flight checks + release
/health     Run health sentinel
/drift      Check for stale review packets
/ops        Quick operator dashboard
```

**Interactive Features:**
- Type `/` to see command picker with arrow navigation
- Type `/a` to filter to commands starting with 'a'
- Tab completion for command names

### 3. Dashboard (`dashboard.ps1`)

**What it does:**
- Auto-refreshing TUI (default: 5 seconds)
- Two-column layout: Execution Resources vs Cognitive State
- Live worker status
- Decision/audit trace from worker logs

**Layout:**
```
┌─────────────────────────┬─────────────────────────┐
│ EXECUTION RESOURCES     │ COGNITIVE STATE         │
├─────────────────────────┼─────────────────────────┤
│ BACKEND [UP]            │ PRODUCT OWNER           │
│ FRONTEND [IDLE]         │ RECENT DECISIONS        │
│ QA/AUDIT Pending: 2     │ REASONING SUMMARY       │
│ LIBRARIAN [CLEAN]       │ LIVE AUDIT LOG          │
└─────────────────────────┴─────────────────────────┘
```

**Customization:**
```powershell
# Change refresh rate
.\dashboard.ps1 -RefreshRate 10  # Refresh every 10 seconds
```

---

## Startup Options

### Full Stack (Default)

```powershell
.\start_mesh.ps1
```
Launches all 3 components in separate windows.

### Server Only

```powershell
.\start_mesh.ps1 -ServerOnly
```
Launches only the mesh server (for headless/CI environments).

### Custom Project Path

```powershell
.\start_mesh.ps1 -ProjectPath "E:\OtherProject"
```
Launches mesh with a different working directory.

---

## Troubleshooting

### Server Won't Start

**Symptom:** Startup script reports "Server failed to start"

**Fixes:**
1. Check Python is installed: `python --version`
2. Check dependencies: `pip install -r requirements.txt`
3. Check for port conflicts (if using HTTP/gRPC)
4. Review logs: `logs\mesh.log`

### Control Panel Commands Fail

**Symptom:** Commands return errors or "not connected"

**Fixes:**
1. Verify server is running: `Get-Process python`
2. Check database exists: `Test-Path mesh.db`
3. Verify database has correct schema: `/verify_db`

### Dashboard Shows Stale Data

**Symptom:** Dashboard not updating or shows old data

**Fixes:**
1. Ensure server is running
2. Check SQLite isn't locked (close other DB connections)
3. Restart dashboard: Close window and re-run `.\dashboard.ps1`

### Multiple Servers Running

**Symptom:** "Server already running" warning

**Fixes:**
```powershell
# Find all python processes
Get-Process python

# Kill specific PID
Stop-Process -Id <PID>

# Nuclear option: kill all python
Get-Process python | Stop-Process
```

---

## Clean Shutdown

### Graceful Shutdown Order

**Recommended: Use stop script**
```powershell
.\stop_mesh.ps1
```

**Manual shutdown:**
1. **Stop Server** (triggers cleanup)
   ```powershell
   Stop-Process -Id <SERVER_PID>
   ```

2. **Close Control Panel** (Ctrl+C or `/quit`)

3. **Close Dashboard** (Ctrl+C or close window)

### Emergency Shutdown

**If stop script fails:**
```powershell
.\stop_mesh.ps1 -Force
```

**Nuclear option:**
```powershell
# Kill everything
Get-Process python | Where-Object { $_.CommandLine -like "*mesh*" } | Stop-Process
Get-Process powershell | Where-Object { $_.CommandLine -like "*control_panel*" } | Stop-Process
Get-Process powershell | Where-Object { $_.CommandLine -like "*dashboard*" } | Stop-Process
```

---

## Advanced Configuration

### Environment Variables

```powershell
# Override database path
$env:ATOMIC_MESH_DB = "E:\CustomPath\mesh.db"

# Override base directory (for isolated testing)
$env:MESH_BASE_DIR = "E:\TestEnv"
```

### Multi-Project Setup

See `config\projects.json` for registering multiple projects.

**Launch specific project:**
```powershell
# Via project registry
.\control_panel.ps1 -ProjectName "MyProject"

# Via direct path
.\start_mesh.ps1 -ProjectPath "E:\MyProject"
```

---

## Integration with IDEs

### VSCode

Add to `.vscode/tasks.json`:
```json
{
  "label": "Start Atomic Mesh",
  "type": "shell",
  "command": "powershell",
  "args": ["-File", "${workspaceFolder}\\start_mesh.ps1"],
  "problemMatcher": [],
  "presentation": {
    "reveal": "always",
    "panel": "new"
  }
}
```

### Manual Launch (Debugging)

If you need to debug components separately:

```powershell
# Terminal 1: Server (foreground)
python mesh_server.py

# Terminal 2: Control Panel
.\control_panel.ps1

# Terminal 3: Dashboard
.\dashboard.ps1
```

---

## Connection Architecture

```
┌──────────────────┐
│  Mesh Server     │  ← Python MCP server
│  (mesh_server.py)│
└────────┬─────────┘
         │
         │ SQLite DB (mesh.db)
         │
    ┌────┴────┬──────────┐
    │         │          │
┌───▼────┐ ┌──▼─────┐ ┌─▼────────┐
│Control │ │Dashboard│ │AI Agents │
│Panel   │ │ (TUI)   │ │(MCP)     │
└────────┘ └─────────┘ └──────────┘
```

**Key Points:**
- All components share the same SQLite database
- Server is the single source of truth for task state
- Control Panel and Dashboard are **read-mostly** viewers
- Only Server can transition tasks via `update_task_state()`

---

## Next Steps

After startup:
1. Run `/ops` in Control Panel for quick system health check
2. Run `/ship` to see pre-flight dashboard (without executing)
3. Check Dashboard for live execution metrics

For first-time setup:
1. Run `/init` to auto-detect project profile
2. Create `docs/ACTIVE_SPEC.md` with requirements
3. Run `/plan_gaps` to generate tasks from sources

---

*Startup Guide v13.0.1 - Unified Launcher Edition*
