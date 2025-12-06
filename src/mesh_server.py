import sqlite3
import json
import time
import os
from datetime import date, datetime
from enum import Enum
from mcp.server.fastmcp import FastMCP
from typing import List, Dict

# FIX #3: Environment Variable for DB Path - allows isolation between environments
DB_FILE = os.getenv("ATOMIC_MESH_DB", os.path.join(os.getcwd(), "mesh.db"))
DOCS_DIR = os.getenv("ATOMIC_MESH_DOCS", os.path.join(os.getcwd(), "docs"))
MODE_FILE = ".mesh_mode"
MILESTONE_FILE = ".milestone_date"

# Server startup time for uptime tracking
SERVER_START_TIME = time.time()

# =============================================================================
# DREAM TEAM MODEL CONFIGURATION (v7.8)
# =============================================================================
# Logic Cluster: GPT-5.1/4o for Backend, Librarian, QA1, Commander
MODEL_LOGIC_MAX = os.getenv("MODEL_LOGIC_MAX", "gpt-4o")

# Creative Cluster: Claude Sonnet for Frontend, QA2
MODEL_CREATIVE_FAST = os.getenv("MODEL_CREATIVE_FAST", "claude-3-5-sonnet-20241022")

# The Heavy: Claude Opus for complex refactoring
MODEL_REASONING_ULTRA = os.getenv("MODEL_REASONING_ULTRA", "claude-3-5-opus-20241022")

# Complexity triggers for Opus escalation
COMPLEXITY_TRIGGERS = [
    "refactor", "rewrite", "migrate", "architecture",
    "redesign", "microservices", "overhaul", "rebuild",
    "from scratch", "entire system", "major change"
]

mcp = FastMCP("AtomicMesh")


# FIX #4: Input Validation Helpers
def validate_task_id(task_id: int) -> bool:
    """Ensures Task ID is a safe, positive integer within bounds."""
    return isinstance(task_id, int) and 0 < task_id < 1_000_000

def validate_port(port: int) -> bool:
    """Ensures port is within valid range."""
    return isinstance(port, int) and 0 < port < 65536

class TaskType(str, Enum):
    FRONTEND = "frontend"
    BACKEND = "backend"
    QA = "qa"

class Mode(str, Enum):
    VIBE = "vibe"       # Fast iteration, tests optional
    CONVERGE = "converge"  # Unit tests required
    SHIP = "ship"       # Full E2E, changelog required

class AgentRole(str, Enum):
    """Defines the roles for RBAC tool access."""
    COMMANDER = "commander"      # Orchestrator - plans and delegates
    WORKER = "worker"            # Builder - writes code (Codex, Claude)
    AUDITOR = "auditor"          # Reviewer - QA, security checks
    LIBRARIAN = "librarian"      # Organizer - file structure, cleanup

# =============================================================================
# ROLE-BASED ACCESS CONTROL (RBAC) FOR MCP TOOLS
# =============================================================================
# 
# Each agent role gets access to specific tools based on their responsibilities.
# This enables Workers to be "Senior Engineers" who can query the library themselves.
#
# COMMANDER (Orchestrator):
#   - Read-only + planning tools
#   - Can detect profiles, check standards, but delegates execution
#
# WORKER (Codex/Claude):
#   - Full execution tools + knowledge access
#   - Can read/write files, run commands, AND consult standards
#   - This is the key to "Seniority" - autonomous lookup
#
# AUDITOR (QA):
#   - Read-only + test execution
#   - Can read files, run tests, check standards
#   - Cannot write code directly
#
# LIBRARIAN:
#   - File organization tools
#   - Can move/delete files, check git, learn structures
#

TOOL_PERMISSIONS = {
    AgentRole.COMMANDER: {
        "allowed": [
            # Knowledge
            "consult_standard",
            "detect_project_profile", 
            "list_library_standards",
            "get_reference",
            # Planning
            "add_task",
            "get_pending_tasks",
            "get_project_status",
            "system_health_check",
            # Read-only
            "read_file",
            "list_directory",
        ],
        "denied": ["write_file", "run_shell", "delete_file", "move_file"]
    },
    
    AgentRole.WORKER: {
        "allowed": [
            # Execution (KEY: Workers can write and run)
            "write_file",
            "read_file",
            "run_shell",
            "edit_file",
            # Knowledge (KEY: Workers can self-lookup)
            "consult_standard",
            "get_reference",
            "list_library_standards",
            # Context
            "list_directory",
            "update_task_status",
            "record_decision",
        ],
        "denied": ["delete_file", "add_task"]  # Workers don't delete or create tasks
    },
    
    AgentRole.AUDITOR: {
        "allowed": [
            # Read-only code access
            "read_file",
            "list_directory",
            # Knowledge (KEY: Auditor verifies against standards)
            "consult_standard",
            "get_reference",
            # Testing
            "run_shell",  # For running test commands
            # Reporting
            "add_audit_entry",
            "get_audit_log",
            "update_task_status",
        ],
        "denied": ["write_file", "edit_file", "delete_file", "add_task"]
    },
    
    AgentRole.LIBRARIAN: {
        "allowed": [
            # File organization
            "read_file",
            "move_file",
            "delete_file",
            "list_directory",
            # Knowledge
            "consult_standard",
            "get_reference",
            "detect_project_profile",
            # Git awareness
            "run_shell",  # For git commands
            # Librarian-specific
            "librarian_scan",
            "librarian_approve",
            "librarian_execute",
            # Priority checking (MUST check before touching files)
            "check_file_priority",
            "request_file_access",
        ],
        "denied": ["write_file", "add_task"]  # Librarian moves, doesn't create
    }
}

def get_tools_for_role(role: AgentRole) -> list:
    """
    Returns the list of allowed tool names for a given agent role.
    Used by the MCP dispatcher to filter available tools.
    """
    perms = TOOL_PERMISSIONS.get(role, {})
    return perms.get("allowed", [])

def is_tool_allowed(role: AgentRole, tool_name: str) -> bool:
    """
    Checks if a specific tool is allowed for a given role.
    """
    perms = TOOL_PERMISSIONS.get(role, {})
    allowed = perms.get("allowed", [])
    denied = perms.get("denied", [])
    
    # Explicit deny takes precedence
    if tool_name in denied:
        return False
    
    # Check if explicitly allowed
    return tool_name in allowed


# =============================================================================
# PRIORITY-AWARE RESOURCE ARBITER (v7.6.3)
# =============================================================================
#
# Handles concurrent file access with priority-based locking.
#
# PRIORITY LEVELS:
#   P3 (Critical) - AUDITOR: Exclusive lock. Can preempt anyone.
#   P2 (High)     - BACKEND: Standard lock. Blocks Frontend/Librarian.
#   P2 (High)     - FRONTEND: Standard lock. Blocks Librarian.
#   P0 (Low)      - LIBRARIAN: Passive. Yields to everyone.
#
# RULES:
#   1. Higher priority can preempt (cancel) lower priority operations
#   2. Equal priority waits (first-come-first-served)
#   3. Librarian MUST check locks before touching ANY file
#   4. Auditor freezes files - no edits until audit complete
#

class Priority:
    """Priority levels for resource contention."""
    CRITICAL = 3  # Auditor - Safety gatekeeper
    HIGH = 2      # Backend/Frontend Workers
    MEDIUM = 1    # Reserved for future use
    LOW = 0       # Librarian - Maintenance only

AGENT_PRIORITY = {
    AgentRole.AUDITOR: Priority.CRITICAL,
    AgentRole.WORKER: Priority.HIGH,
    AgentRole.COMMANDER: Priority.HIGH,
    AgentRole.LIBRARIAN: Priority.LOW,
}

# More granular priority for task types
TASK_TYPE_PRIORITY = {
    "audit": Priority.CRITICAL,
    "security_scan": Priority.CRITICAL,
    "backend": Priority.HIGH,
    "frontend": Priority.HIGH,
    "qa": Priority.HIGH,
    "cleanup": Priority.LOW,
    "reorganize": Priority.LOW,
    "librarian": Priority.LOW,
}

def get_agent_priority(role: AgentRole, task_type: str = None) -> int:
    """
    Returns the priority level for an agent, optionally considering task type.
    """
    # Task type can override role priority
    if task_type and task_type.lower() in TASK_TYPE_PRIORITY:
        return TASK_TYPE_PRIORITY[task_type.lower()]
    
    return AGENT_PRIORITY.get(role, Priority.LOW)

def get_active_file_locks(file_paths: List[str] = None) -> List[Dict]:
    """
    Returns all active file locks, optionally filtered by specific files.
    
    Returns list of:
    {
        "file": "/path/to/file",
        "agent_role": "worker",
        "task_id": 123,
        "priority": 2,
        "locked_at": timestamp
    }
    """
    try:
        with get_db() as conn:
            if file_paths:
                # Check specific files
                placeholders = ",".join(["?" for _ in file_paths])
                query = f"""
                    SELECT id, type, assignee, active_file_lock, updated_at 
                    FROM tasks 
                    WHERE status = 'in_progress' 
                    AND active_file_lock IN ({placeholders})
                """
                rows = conn.execute(query, file_paths).fetchall()
            else:
                # Get all active locks
                rows = conn.execute("""
                    SELECT id, type, assignee, active_file_lock, updated_at 
                    FROM tasks 
                    WHERE status = 'in_progress' 
                    AND active_file_lock IS NOT NULL
                """).fetchall()
            
            locks = []
            for row in rows:
                task_type = row["type"] or "unknown"
                priority = TASK_TYPE_PRIORITY.get(task_type.lower(), Priority.HIGH)
                
                locks.append({
                    "file": row["active_file_lock"],
                    "agent_role": row["assignee"] or "worker",
                    "task_id": row["id"],
                    "task_type": task_type,
                    "priority": priority,
                    "locked_at": row["updated_at"]
                })
            
            return locks
    except Exception as e:
        server_logger.error(f"Error fetching file locks: {e}")
        return []

def can_access_file(requesting_role: AgentRole, file_path: str, task_type: str = None) -> Dict:
    """
    Determines if an agent can access a file based on priority rules.
    
    Returns:
        {
            "allowed": bool,
            "reason": str,
            "blocked_by": optional dict with blocker info,
            "action": "proceed" | "wait" | "abort"
        }
    """
    my_priority = get_agent_priority(requesting_role, task_type)
    
    # Get active locks on this file
    active_locks = get_active_file_locks([file_path])
    
    if not active_locks:
        return {
            "allowed": True,
            "reason": "File is not locked",
            "action": "proceed"
        }
    
    for lock in active_locks:
        holder_priority = lock["priority"]
        
        # RULE 1: Cannot touch files held by higher or equal priority
        if holder_priority >= my_priority:
            action = "abort" if requesting_role == AgentRole.LIBRARIAN else "wait"
            return {
                "allowed": False,
                "reason": f"File locked by {lock['agent_role']} (priority {holder_priority} >= {my_priority})",
                "blocked_by": lock,
                "action": action
            }
        
        # RULE 2: Can preempt lower priority (but only Auditor should do this)
        if holder_priority < my_priority and requesting_role == AgentRole.AUDITOR:
            return {
                "allowed": True,
                "reason": f"Auditor preempting {lock['agent_role']} (task {lock['task_id']})",
                "preempt_task": lock["task_id"],
                "action": "preempt"
            }
    
    return {
        "allowed": True,
        "reason": "Access granted",
        "action": "proceed"
    }

def preempt_task(task_id: int, reason: str = "Preempted by higher priority") -> bool:
    """
    Forcibly stops a task due to preemption by higher priority agent.
    """
    try:
        with get_db() as conn:
            conn.execute("""
                UPDATE tasks 
                SET status = 'preempted', 
                    error = ?,
                    active_file_lock = NULL,
                    updated_at = ?
                WHERE id = ?
            """, (reason, int(time.time()), task_id))
            conn.commit()
            
            server_logger.warning(f"Task {task_id} preempted: {reason}")
            return True
    except Exception as e:
        server_logger.error(f"Failed to preempt task {task_id}: {e}")
        return False

def get_safe_files_for_librarian(file_list: List[str]) -> List[str]:
    """
    Filters a list of files to only those safe for Librarian to touch.
    The Librarian is "cowardly" - it yields to everyone.
    
    Returns:
        List of files with no active locks from higher priority agents.
    """
    all_locks = get_active_file_locks()
    locked_files = {lock["file"] for lock in all_locks}
    
    safe_files = []
    skipped = []
    
    for f in file_list:
        if f in locked_files:
            skipped.append(f)
        else:
            safe_files.append(f)
    
    if skipped:
        server_logger.info(f"Librarian yielding on {len(skipped)} files with active work")
    
    return safe_files

def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    # WAL mode for concurrent access - set once per connection
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA busy_timeout=5000;")
    return conn

# Setup logging for server (Issue #1, #8)
import logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
server_logger = logging.getLogger("MeshServer")

def init_db():
    """Initialize database schema. WAL mode is already set in get_db()."""
    try:
        with get_db() as conn:
            # Note: WAL mode already enabled in get_db(), no duplicate needed (Issue #6)
            
            conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type TEXT NOT NULL,
                desc TEXT NOT NULL,
                deps TEXT DEFAULT '[]',
                status TEXT DEFAULT 'pending',
                output TEXT,
                worker_id TEXT,
                updated_at INTEGER,
                retry_count INTEGER DEFAULT 0,
                priority INTEGER DEFAULT 1,
                files_changed TEXT DEFAULT '[]',
                test_result TEXT DEFAULT 'SKIPPED',
                strictness TEXT DEFAULT 'normal',
                auditor_status TEXT DEFAULT 'pending',
                auditor_feedback TEXT DEFAULT '[]'
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS artifacts (
                key TEXT PRIMARY KEY,
                value TEXT,
                worker_id TEXT,
                updated_at INTEGER
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS config (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
        # Decisions table for red/yellow/green priority queue
        conn.execute("""
            CREATE TABLE IF NOT EXISTS decisions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                priority TEXT NOT NULL,
                question TEXT NOT NULL,
                context TEXT,
                status TEXT DEFAULT 'pending',
                answer TEXT,
                created_at INTEGER
            )
        """)
        # NEW: Audit log table for Auditor agent
        conn.execute("""
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER,
                action TEXT,
                strictness TEXT,
                reason TEXT,
                retry_count INTEGER,
                created_at INTEGER
            )
        """)
        # NEW: Librarian operations log
        conn.execute("""
            CREATE TABLE IF NOT EXISTS librarian_ops (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                manifest_id TEXT,
                action TEXT,
                from_path TEXT,
                to_path TEXT,
                risk_level TEXT,
                status TEXT DEFAULT 'pending',
                blocked_reason TEXT,
                created_at INTEGER,
                executed_at INTEGER
            )
        """)
        # NEW: Restore points for librarian
        conn.execute("""
            CREATE TABLE IF NOT EXISTS restore_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                manifest_id TEXT,
                script_path TEXT,
                operations_json TEXT,
                created_at INTEGER,
                expires_at INTEGER,
                status TEXT DEFAULT 'active'
            )
        """)
        # Initialize config if not exists
        conn.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('mode', 'vibe')")
        conn.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('last_review', ?)", (str(int(time.time())),))
    
    except sqlite3.Error as e:
        server_logger.critical(f"Database initialization failed: {e}")
        raise  # Critical failure - cannot proceed without DB
    except Exception as e:
        server_logger.critical(f"Unexpected error during DB init: {e}")
        raise

init_db()

# --- HEALTH CHECK (Issue #12) ---

@mcp.tool()
def system_health_check() -> str:
    """
    Returns system vitals for monitoring and status commands.
    Used by monitoring scripts, 'status' command, and external integrations.
    """
    try:
        # 1. Check DB Connection
        db_ok = False
        task_count = 0
        with get_db() as conn:
            conn.execute("SELECT 1")
            db_ok = True
            task_count = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
        
        # 2. Calculate uptime
        uptime_seconds = time.time() - SERVER_START_TIME
        uptime_human = f"{int(uptime_seconds // 3600)}h {int((uptime_seconds % 3600) // 60)}m"
        
        # 3. Check docs directory
        docs_exist = os.path.isdir(DOCS_DIR)
        
        return json.dumps({
            "status": "HEALTHY",
            "component": "Atomic Mesh Server v7.4",
            "database": {
                "path": DB_FILE,
                "connected": db_ok,
                "wal_mode": True,
                "task_count": task_count
            },
            "uptime": uptime_human,
            "uptime_seconds": uptime_seconds,
            "docs_directory": DOCS_DIR,
            "docs_exist": docs_exist,
            "timestamp": time.time()
        })
    
    except sqlite3.Error as e:
        server_logger.error(f"Health check DB error: {e}")
        return json.dumps({
            "status": "UNHEALTHY",
            "component": "Atomic Mesh Server v7.4",
            "error": f"Database error: {e}",
            "timestamp": time.time()
        })
    except Exception as e:
        server_logger.error(f"Health check failed: {e}")
        return json.dumps({
            "status": "UNHEALTHY",
            "component": "Atomic Mesh Server v7.4",
            "error": str(e),
            "timestamp": time.time()
        })

# =============================================================================
# CENTRAL LIBRARY SYSTEM (v7.6)
# =============================================================================

# Library root - can be overridden via environment variable
LIBRARY_ROOT = os.getenv("ATOMIC_MESH_LIB", os.path.join(os.path.dirname(__file__), "library"))

@mcp.tool()
def consult_standard(topic: str, profile: str = "general") -> str:
    """
    Retrieves Golden Standard guidelines from the Central Library.
    
    Args:
        topic: The standard to retrieve. Options: 'security', 'architecture', 
               'folder_structure', 'testing', 'git', 'code_review', 'components'
        profile: The project profile. Options: 'python_backend', 'typescript_next',
                'infrastructure', 'general'
    
    Returns:
        The content of the standard file, prefixed with metadata.
    """
    # Load profile configuration
    profile_path = os.path.join(LIBRARY_ROOT, "profiles", f"{profile}.json")
    
    # Fallback to general if specific profile missing
    if not os.path.exists(profile_path):
        if profile != "general":
            return consult_standard(topic, "general")
        return f"⚠️ Profile '{profile}' not found in library."
    
    try:
        with open(profile_path, 'r', encoding='utf-8') as f:
            profile_data = json.load(f)
        
        # Get the relative path for this topic
        standards_map = profile_data.get("standards", {})
        rel_path = standards_map.get(topic)
        
        if not rel_path:
            return f"⚠️ No standard defined for '{topic}' in profile '{profile}'."
        
        # Read the standard file
        full_path = os.path.join(LIBRARY_ROOT, "standards", rel_path)
        
        if not os.path.exists(full_path):
            return f"⚠️ Standard file missing: {rel_path}"
        
        with open(full_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        return f"[STANDARD: {topic.upper()} | Profile: {profile}]\n\n{content}"
        
    except json.JSONDecodeError as e:
        return f"⚠️ Invalid profile JSON: {e}"
    except Exception as e:
        server_logger.error(f"Error reading standard: {e}")
        return f"⚠️ Error reading standard: {e}"

@mcp.tool()
def detect_project_profile(project_root: str) -> str:
    """
    Auto-detects the technology stack of a project directory.
    
    Args:
        project_root: Absolute path to the project directory.
    
    Returns:
        The detected profile name (e.g., 'python_backend', 'typescript_next').
    """
    try:
        if not os.path.isdir(project_root):
            return "general"
        
        files = os.listdir(project_root)
        files_lower = [f.lower() for f in files]
        
        # Check for Node.js / TypeScript projects
        if "package.json" in files_lower:
            pkg_path = os.path.join(project_root, "package.json")
            try:
                with open(pkg_path, 'r', encoding='utf-8') as f:
                    content = f.read().lower()
                
                if "next" in content:
                    return "typescript_next"
                if "react" in content and "next" not in content:
                    return "typescript_react"
                if "vue" in content:
                    return "vue_frontend"
                if "express" in content or "fastify" in content:
                    return "node_backend"
                    
                return "node_general"
            except:
                return "node_general"
        
        # Check for Python projects
        if "requirements.txt" in files_lower or "pyproject.toml" in files_lower or "setup.py" in files_lower:
            # Try to detect specific framework
            for check_file in ["requirements.txt", "pyproject.toml"]:
                check_path = os.path.join(project_root, check_file)
                if os.path.exists(check_path):
                    try:
                        with open(check_path, 'r', encoding='utf-8') as f:
                            content = f.read().lower()
                        if "fastapi" in content or "django" in content or "flask" in content:
                            return "python_backend"
                        if "pandas" in content or "numpy" in content or "scikit" in content:
                            return "python_data"
                    except:
                        pass
            return "python_backend"
        
        # Check for Infrastructure projects
        if any(f.endswith(".tf") for f in files_lower):
            return "infrastructure"
        if "docker-compose.yml" in files_lower or "docker-compose.yaml" in files_lower:
            return "infrastructure"
        if "kubernetes" in str(files_lower) or any("k8s" in f for f in files_lower):
            return "infrastructure"
        
        return "general"
        
    except Exception as e:
        server_logger.warning(f"Profile detection failed: {e}")
        return "general"

@mcp.tool()
def get_reference(reference_type: str, profile: str = "general") -> str:
    """
    Retrieves a reference code sample from the Central Library.
    
    Args:
        reference_type: Type of reference (e.g., 'api_route', 'service', 'component', 'test')
        profile: The project profile (e.g., 'python_backend', 'typescript_next')
    
    Returns:
        The reference code content with metadata.
    """
    profile_path = os.path.join(LIBRARY_ROOT, "profiles", f"{profile}.json")
    
    if not os.path.exists(profile_path):
        return f"⚠️ Profile '{profile}' not found."
    
    try:
        with open(profile_path, 'r', encoding='utf-8') as f:
            profile_data = json.load(f)
        
        references_map = profile_data.get("references", {})
        rel_path = references_map.get(reference_type)
        
        if not rel_path:
            return f"⚠️ No reference for '{reference_type}' in profile '{profile}'."
        
        full_path = os.path.join(LIBRARY_ROOT, "references", rel_path)
        
        if not os.path.exists(full_path):
            return f"⚠️ Reference file missing: {rel_path}"
        
        with open(full_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        return f"[REFERENCE: {reference_type} | Profile: {profile}]\n\n{content}"
        
    except Exception as e:
        server_logger.error(f"Error reading reference: {e}")
        return f"⚠️ Error: {e}"

@mcp.tool()
def list_library_standards(profile: str = "general") -> str:
    """
    Lists all available standards for a given profile.
    
    Args:
        profile: The project profile to list standards for.
    
    Returns:
        JSON with available standards and references.
    """
    profile_path = os.path.join(LIBRARY_ROOT, "profiles", f"{profile}.json")
    
    if not os.path.exists(profile_path):
        # List available profiles
        profiles_dir = os.path.join(LIBRARY_ROOT, "profiles")
        if os.path.isdir(profiles_dir):
            available = [f.replace(".json", "") for f in os.listdir(profiles_dir) if f.endswith(".json")]
            return json.dumps({
                "error": f"Profile '{profile}' not found",
                "available_profiles": available
            })
        return json.dumps({"error": "Library not initialized"})
    
    try:
        with open(profile_path, 'r', encoding='utf-8') as f:
            profile_data = json.load(f)
        
        return json.dumps({
            "profile": profile,
            "name": profile_data.get("name", "Unknown"),
            "description": profile_data.get("description", ""),
            "standards": list(profile_data.get("standards", {}).keys()),
            "references": list(profile_data.get("references", {}).keys())
        }, indent=2)
        
    except Exception as e:
        return json.dumps({"error": str(e)})

@mcp.tool()
def get_agent_tools(role: str) -> str:
    """
    Returns the list of MCP tools available for a specific agent role.
    Used by orchestrators to understand what each agent can do.
    
    Args:
        role: The agent role. Options: 'commander', 'worker', 'auditor', 'librarian'
    
    Returns:
        JSON with allowed and denied tools for the role.
    """
    try:
        agent_role = AgentRole(role.lower())
    except ValueError:
        return json.dumps({
            "error": f"Unknown role: {role}",
            "valid_roles": [r.value for r in AgentRole]
        })
    
    perms = TOOL_PERMISSIONS.get(agent_role, {})
    
    return json.dumps({
        "role": agent_role.value,
        "allowed_tools": perms.get("allowed", []),
        "denied_tools": perms.get("denied", []),
        "description": {
            "commander": "Orchestrator - plans, delegates, reads. Cannot write or execute.",
            "worker": "Builder - writes code, runs commands, AND consults standards autonomously.",
            "auditor": "Reviewer - reads code, runs tests, checks standards. Cannot write.",
            "librarian": "Organizer - moves files, checks structure. Cannot write new code."
        }.get(agent_role.value, "")
    }, indent=2)

@mcp.tool()
def validate_tool_access(role: str, tool_name: str) -> str:
    """
    Checks if a specific tool is allowed for a given agent role.
    Use this before executing sensitive operations.
    
    Args:
        role: The agent role (commander, worker, auditor, librarian)
        tool_name: The name of the tool to check
    
    Returns:
        JSON with allowed status and reason.
    """
    try:
        agent_role = AgentRole(role.lower())
    except ValueError:
        return json.dumps({"allowed": False, "reason": f"Unknown role: {role}"})
    
    allowed = is_tool_allowed(agent_role, tool_name)
    
    perms = TOOL_PERMISSIONS.get(agent_role, {})
    denied_list = perms.get("denied", [])
    
    if tool_name in denied_list:
        reason = f"Tool '{tool_name}' is explicitly denied for role '{role}'"
    elif allowed:
        reason = f"Tool '{tool_name}' is allowed for role '{role}'"
    else:
        reason = f"Tool '{tool_name}' is not in the allowed list for role '{role}'"
    
    return json.dumps({
        "allowed": allowed,
        "role": role,
        "tool": tool_name,
        "reason": reason
    })

# =============================================================================
# PRIORITY-AWARE FILE ACCESS TOOLS
# =============================================================================

@mcp.tool()
def check_file_priority(file_path: str, requesting_role: str = "worker") -> str:
    """
    Checks if a file can be accessed based on priority rules.
    MUST be called by Librarian before touching ANY file.
    
    Args:
        file_path: Path to the file to check
        requesting_role: The role requesting access (worker, auditor, librarian)
    
    Returns:
        JSON with access status, reason, and recommended action.
    """
    try:
        role = AgentRole(requesting_role.lower())
    except ValueError:
        return json.dumps({
            "allowed": False,
            "reason": f"Unknown role: {requesting_role}",
            "action": "abort"
        })
    
    result = can_access_file(role, file_path)
    return json.dumps(result, indent=2)

@mcp.tool()
def request_file_access(file_path: str, requesting_role: str, task_type: str = None) -> str:
    """
    Requests access to a file, potentially preempting lower priority tasks.
    Only Auditor can preempt. Others must wait or abort.
    
    Args:
        file_path: Path to the file
        requesting_role: Role requesting access
        task_type: Optional task type for priority override
    
    Returns:
        JSON with access result and any preemption actions taken.
    """
    try:
        role = AgentRole(requesting_role.lower())
    except ValueError:
        return json.dumps({
            "granted": False,
            "reason": f"Unknown role: {requesting_role}"
        })
    
    access_result = can_access_file(role, file_path, task_type)
    
    # Handle preemption for Auditor
    if access_result.get("action") == "preempt" and "preempt_task" in access_result:
        task_id = access_result["preempt_task"]
        preempt_success = preempt_task(task_id, f"Preempted by {requesting_role} for file: {file_path}")
        
        return json.dumps({
            "granted": True,
            "preempted_task": task_id,
            "preempt_success": preempt_success,
            "reason": access_result["reason"]
        })
    
    return json.dumps({
        "granted": access_result["allowed"],
        "action": access_result.get("action", "unknown"),
        "reason": access_result["reason"],
        "blocked_by": access_result.get("blocked_by")
    }, indent=2)

@mcp.tool()
def get_active_locks() -> str:
    """
    Returns all currently active file locks in the system.
    Useful for dashboards and debugging contention issues.
    
    Returns:
        JSON array of active locks with file, agent, task, and priority info.
    """
    locks = get_active_file_locks()
    
    return json.dumps({
        "total_locks": len(locks),
        "locks": locks,
        "priority_legend": {
            "3": "CRITICAL (Auditor)",
            "2": "HIGH (Worker)",
            "1": "MEDIUM",
            "0": "LOW (Librarian)"
        }
    }, indent=2)

@mcp.tool()
def get_safe_librarian_files(files: str) -> str:
    """
    Filters a list of files to only those safe for Librarian to touch.
    Librarian is 'cowardly' - yields to everyone.
    
    Args:
        files: Comma-separated list of file paths, or JSON array
    
    Returns:
        JSON with safe files and skipped files.
    """
    # Parse input
    if files.startswith("["):
        try:
            file_list = json.loads(files)
        except:
            file_list = [f.strip() for f in files.split(",")]
    else:
        file_list = [f.strip() for f in files.split(",")]
    
    safe = get_safe_files_for_librarian(file_list)
    skipped = [f for f in file_list if f not in safe]
    
    return json.dumps({
        "safe_files": safe,
        "safe_count": len(safe),
        "skipped_files": skipped,
        "skipped_count": len(skipped),
        "message": f"Librarian can safely touch {len(safe)}/{len(file_list)} files"
    }, indent=2)


# =============================================================================
# BOOTSTRAP SEED PACKAGE TOOLS (v7.7)
# =============================================================================

@mcp.tool()
def get_active_spec() -> str:
    """
    Reads the ACTIVE_SPEC.md from the current project.
    Essential for Commander to understand scope and for Auditor to validate.
    
    Returns:
        The contents of docs/ACTIVE_SPEC.md
    """
    spec_path = os.path.join(os.getcwd(), "docs", "ACTIVE_SPEC.md")
    
    if not os.path.exists(spec_path):
        return json.dumps({
            "error": "ACTIVE_SPEC.md not found",
            "hint": "Run /init to bootstrap seed documents"
        })
    
    try:
        with open(spec_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return f"[ACTIVE SPECIFICATION]\n\n{content}"
    except Exception as e:
        return json.dumps({"error": str(e)})

@mcp.tool()
def get_tech_stack() -> str:
    """
    Reads the TECH_STACK.md from the current project.
    Workers MUST consult this before importing any library.
    
    Returns:
        The contents of docs/TECH_STACK.md
    """
    stack_path = os.path.join(os.getcwd(), "docs", "TECH_STACK.md")
    
    if not os.path.exists(stack_path):
        return json.dumps({
            "error": "TECH_STACK.md not found",
            "hint": "Run /init to bootstrap seed documents"
        })
    
    try:
        with open(stack_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return f"[TECH STACK CONTRACT]\n\n{content}"
    except Exception as e:
        return json.dumps({"error": str(e)})

@mcp.tool()
def append_decision(decision: str, context: str) -> str:
    """
    Logs a major decision to docs/DECISION_LOG.md.
    Called by Router/Commander when significant choices are made.
    Prevents re-litigation of past decisions.
    
    Args:
        decision: What was decided (e.g., "Use FastAPI for backend")
        context: Why it was decided (e.g., "Team familiar with Python async")
    
    Returns:
        Confirmation of logged decision with ID.
    """
    log_path = os.path.join(os.getcwd(), "docs", "DECISION_LOG.md")
    
    if not os.path.exists(log_path):
        return json.dumps({
            "error": "DECISION_LOG.md not found",
            "hint": "Run /init to bootstrap seed documents"
        })
    
    try:
        decision_id = int(time.time())
        date_str = datetime.now().strftime("%Y-%m-%d")
        
        # Escape pipe characters in decision/context
        decision_clean = decision.replace("|", "\\|")
        context_clean = context.replace("|", "\\|")
        
        entry = f"| {decision_id} | {date_str} | {decision_clean} | {context_clean} | ✅ |\n"
        
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(entry)
        
        return json.dumps({
            "logged": True,
            "id": decision_id,
            "decision": decision,
            "date": date_str
        })
    except Exception as e:
        return json.dumps({"error": str(e)})

@mcp.tool()
def bootstrap_project(project_path: str = None) -> str:
    """
    Creates the Seed Package (ACTIVE_SPEC.md, TECH_STACK.md, DECISION_LOG.md)
    in the specified project directory.
    
    Args:
        project_path: Path to the project root. Defaults to current directory.
    
    Returns:
        JSON with list of created files.
    """
    import shutil
    
    if not project_path:
        project_path = os.getcwd()
    
    # Template mapping
    templates = {
        "ACTIVE_SPEC.template.md": "docs/ACTIVE_SPEC.md",
        "TECH_STACK.template.md": "docs/TECH_STACK.md",
        "DECISION_LOG.template.md": "docs/DECISION_LOG.md",
        "env_template.txt": ".env.example"
    }
    
    template_dir = os.path.join(LIBRARY_ROOT, "templates")
    docs_dir = os.path.join(project_path, "docs")
    
    # Create docs folder
    os.makedirs(docs_dir, exist_ok=True)
    
    created = []
    skipped = []
    
    for src_name, dst_rel in templates.items():
        src_path = os.path.join(template_dir, src_name)
        dst_path = os.path.join(project_path, dst_rel)
        
        if os.path.exists(dst_path):
            skipped.append(dst_rel)
            continue
        
        if os.path.exists(src_path):
            # Create parent dir if needed
            os.makedirs(os.path.dirname(dst_path), exist_ok=True)
            
            # Copy and replace placeholders
            with open(src_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Replace common placeholders
            project_name = os.path.basename(project_path)
            content = content.replace("{{PROJECT_NAME}}", project_name)
            content = content.replace("{{DATE}}", datetime.now().strftime("%Y-%m-%d"))
            content = content.replace("{{AUTHOR}}", "Atomic Mesh")
            
            with open(dst_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            created.append(dst_rel)
    
    return json.dumps({
        "success": True,
        "project": project_path,
        "created": created,
        "skipped": skipped,
        "message": f"Seed Package: {len(created)} files created, {len(skipped)} skipped (already exist)"
    }, indent=2)

@mcp.tool()
def get_decision_log() -> str:
    """
    Reads the full DECISION_LOG.md from the current project.
    Use this to check what has already been decided.
    
    Returns:
        The contents of docs/DECISION_LOG.md
    """
    log_path = os.path.join(os.getcwd(), "docs", "DECISION_LOG.md")
    
    if not os.path.exists(log_path):
        return json.dumps({
            "error": "DECISION_LOG.md not found",
            "hint": "Run /init to bootstrap seed documents"
        })
    
    try:
        with open(log_path, 'r', encoding='utf-8') as f:
            content = f.read()
        return f"[DECISION LOG]\n\n{content}"
    except Exception as e:
        return json.dumps({"error": str(e)})


# =============================================================================
# DREAM TEAM MODEL ROUTING (v7.8)
# =============================================================================

@mcp.tool()
def get_model_for_role(role: str, complexity: str = "normal") -> str:
    """
    Routes to the optimal SOTA model based on agent role and task complexity.
    
    The Dream Team:
      - Logic Cluster (GPT-5.1/4o): Backend, Librarian, QA1, Commander
      - Creative Cluster (Sonnet): Frontend, QA2
      - The Heavy (Opus): Complex refactoring tasks
    
    Args:
        role: Agent role (backend, frontend, qa1, qa2, librarian, commander)
        complexity: Task complexity ("normal" or "high")
    
    Returns:
        JSON with selected model and reasoning.
    """
    role_lower = role.lower()
    
    # The Heavy for complex tasks
    if complexity == "high":
        return json.dumps({
            "model": MODEL_REASONING_ULTRA,
            "role": role,
            "tier": "The Heavy",
            "reason": "Complex task requiring deep reasoning (Opus)"
        })
    
    # Role-based routing
    # Logic Cluster (GPT)
    if role_lower in ["backend", "librarian", "qa1", "commander", "orchestrator", "auditor"]:
        return json.dumps({
            "model": MODEL_LOGIC_MAX,
            "role": role,
            "tier": "Logic Cluster",
            "reason": "Hard logic, security, architecture (GPT)"
        })
    
    # Creative Cluster (Claude Sonnet)
    if role_lower in ["frontend", "qa2", "writer", "designer"]:
        return json.dumps({
            "model": MODEL_CREATIVE_FAST,
            "role": role,
            "tier": "Creative Cluster",
            "reason": "Visuals, style, readability (Sonnet)"
        })
    
    # Default fallback
    return json.dumps({
        "model": MODEL_LOGIC_MAX,
        "role": role,
        "tier": "Default",
        "reason": "Unknown role, using Logic Cluster"
    })

@mcp.tool()
def analyze_complexity(user_input: str) -> str:
    """
    Analyzes task complexity to determine if The Heavy (Opus) is needed.
    
    Looks for trigger words like "refactor", "rewrite", "migrate", etc.
    Also considers prompt length as a heuristic.
    
    Args:
        user_input: The user's task description
    
    Returns:
        JSON with complexity level and detected triggers.
    """
    input_lower = user_input.lower()
    detected_triggers = []
    
    # Check for trigger phrases
    for trigger in COMPLEXITY_TRIGGERS:
        if trigger in input_lower:
            detected_triggers.append(trigger)
    
    # Word count heuristic
    word_count = len(user_input.split())
    long_prompt = word_count > 150
    
    # Multiple file mentions
    file_mentions = sum(1 for ext in [".py", ".ts", ".tsx", ".js", ".jsx", ".sql"] 
                       if ext in input_lower)
    
    # Determine complexity
    if detected_triggers or long_prompt or file_mentions >= 3:
        complexity = "high"
        recommended_model = MODEL_REASONING_ULTRA
        reason = "Complex task detected"
    else:
        complexity = "normal"
        recommended_model = None
        reason = "Standard task"
    
    return json.dumps({
        "complexity": complexity,
        "triggers_found": detected_triggers,
        "word_count": word_count,
        "file_mentions": file_mentions,
        "recommended_model": recommended_model,
        "reason": reason
    }, indent=2)

@mcp.tool()
def get_model_roster() -> str:
    """
    Returns the current Dream Team model configuration.
    
    Shows which models are assigned to which roles.
    """
    return json.dumps({
        "version": "7.8",
        "name": "Dream Team",
        "roster": {
            "logic_cluster": {
                "model": MODEL_LOGIC_MAX,
                "roles": ["backend", "librarian", "qa1", "commander", "auditor"],
                "specialization": "Hard logic, security, architecture"
            },
            "creative_cluster": {
                "model": MODEL_CREATIVE_FAST,
                "roles": ["frontend", "qa2", "writer"],
                "specialization": "Visuals, style, readability"
            },
            "the_heavy": {
                "model": MODEL_REASONING_ULTRA,
                "trigger": "complexity=high",
                "specialization": "Complex refactoring, architecture redesign"
            }
        },
        "qa_protocol": {
            "qa1": {
                "name": "The Compiler",
                "model": MODEL_LOGIC_MAX,
                "focus": "Security, types, architecture"
            },
            "qa2": {
                "name": "The Critic",
                "model": MODEL_CREATIVE_FAST,
                "focus": "Readability, style, spaghetti detection"
            }
        }
    }, indent=2)

@mcp.tool()
def request_dual_qa(code_content: str, context: str = "") -> str:
    """
    Submits code for Dual QA review (Zero-Spaghetti Protocol).
    
    Code must pass BOTH:
      - QA1 (Compiler): Hard logic checks
      - QA2 (Critic): Style/readability checks
    
    Args:
        code_content: The code to review
        context: Optional context about the code
    
    Returns:
        JSON with QA result (APPROVED/REJECTED) and issues.
    
    Note: This is a placeholder for the async Dual QA.
    Full implementation requires LLM client integration.
    """
    # This is a stub - actual implementation in qa_protocol.py
    return json.dumps({
        "status": "PENDING",
        "message": "Dual QA request queued",
        "qa1_model": MODEL_LOGIC_MAX,
        "qa2_model": MODEL_CREATIVE_FAST,
        "code_length": len(code_content),
        "context": context or "No context provided",
        "note": "Full Dual QA requires async LLM integration"
    }, indent=2)


def get_mode() -> str:
    """Get current mode, with auto-detection based on milestone date."""
    # Check for milestone file
    if os.path.exists(MILESTONE_FILE):
        try:
            with open(MILESTONE_FILE, 'r') as f:
                milestone = date.fromisoformat(f.read().strip())
            days_left = (milestone - date.today()).days
            
            if days_left <= 2:
                return "ship"
            elif days_left <= 7:
                return "converge"
            else:
                return "vibe"
        except:
            pass
    
    # Fall back to manual mode
    with get_db() as conn:
        row = conn.execute("SELECT value FROM config WHERE key='mode'").fetchone()
        return row[0] if row else "vibe"

def run_watchdog(conn):
    """Resets tasks stuck 'in_progress'."""
    now = int(time.time())
    conn.execute("""
        UPDATE tasks SET status='pending', worker_id=NULL, retry_count=retry_count+1 
        WHERE status='in_progress' AND type IN ('frontend', 'qa') AND updated_at < ?
    """, (now - 300,))
    conn.execute("""
        UPDATE tasks SET status='pending', worker_id=NULL, retry_count=retry_count+1 
        WHERE status='in_progress' AND type = 'backend' AND updated_at < ?
    """, (now - 600,))

# --- TOOLS ---
@mcp.tool()
def set_mode(mode: str) -> str:
    """Set the strictness mode: vibe, converge, or ship."""
    if mode not in ['vibe', 'converge', 'ship']:
        return "Invalid mode. Use: vibe, converge, ship"
    with get_db() as conn:
        conn.execute("UPDATE config SET value=? WHERE key='mode'", (mode,))
    # Remove milestone file if manually setting mode
    if os.path.exists(MILESTONE_FILE):
        os.remove(MILESTONE_FILE)
    return f"Mode set to: {mode.upper()}"

@mcp.tool()
def get_current_mode() -> str:
    """Get current mode with auto-detection info."""
    mode = get_mode()
    auto_msg = ""
    if os.path.exists(MILESTONE_FILE):
        try:
            with open(MILESTONE_FILE, 'r') as f:
                milestone = date.fromisoformat(f.read().strip())
            days_left = (milestone - date.today()).days
            auto_msg = f" (Auto: {days_left} days to milestone)"
        except:
            pass
    
    icons = {"vibe": "🟢", "converge": "🟡", "ship": "🔴"}
    return f"{icons.get(mode, '⚪')} {mode.upper()}{auto_msg}"

@mcp.tool()
def set_milestone(date_str: str) -> str:
    """Set milestone date (YYYY-MM-DD) for auto-dimmer."""
    try:
        milestone = date.fromisoformat(date_str)
        with open(MILESTONE_FILE, 'w') as f:
            f.write(date_str)
        days = (milestone - date.today()).days
        return f"Milestone set: {date_str} ({days} days). Auto-dimmer active."
    except ValueError:
        return "Invalid date format. Use: YYYY-MM-DD"

@mcp.tool()
def post_task(type: TaskType, description: str, dependencies: List[int] = [], priority: int = 1) -> str:
    """Queues a new task."""
    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO tasks (type, desc, deps, status, updated_at, priority) VALUES (?, ?, ?, 'pending', ?, ?)",
            (type.value, description, json.dumps(dependencies), int(time.time()), priority)
        )
        return f"Task {cursor.lastrowid} queued"

@mcp.tool()
def pick_task(worker_type: TaskType, worker_id: str) -> str:
    """
    Smart Picking v2:
    1. THROTTLING (Backend < 2)
    2. CASCADING BLOCKS: 
       - If Parent FAILED/BLOCKED -> Mark Child BLOCKED (Partial Halt)
       - If Parent PENDING/IN_PROGRESS -> Skip Child (Wait)
       - If Parent COMPLETED -> Execute Child
    """
    with get_db() as conn:
        run_watchdog(conn)
        
        # 1. THROTTLING
        if worker_type == TaskType.BACKEND:
            active = conn.execute(
                "SELECT count(*) FROM tasks WHERE type='backend' AND status='in_progress'"
            ).fetchone()[0]
            if active >= 2:
                return "NO_WORK (Throttled)"

        # 2. SEARCH (include 'blocked' to check for auto-recovery)
        cursor = conn.execute(
            "SELECT * FROM tasks WHERE type = ? AND status IN ('pending', 'blocked') ORDER BY priority DESC, id ASC", 
            (worker_type.value,)
        )
        
        for task in cursor.fetchall():
            deps = json.loads(task['deps'])
            
            if deps:
                # Check status of ALL dependencies
                placeholders = ','.join('?' for _ in deps)
                dep_rows = conn.execute(
                    f"SELECT status FROM tasks WHERE id IN ({placeholders})", deps
                ).fetchall()
                
                statuses = [r[0] for r in dep_rows]
                
                # CONDITION 1: CASCADING BLOCK (Partial Halt)
                # If any parent failed or is blocked, this task must block
                if 'failed' in statuses or 'blocked' in statuses:
                    if task['status'] != 'blocked':
                        conn.execute(
                            "UPDATE tasks SET status='blocked', updated_at=? WHERE id=?", 
                            (int(time.time()), task['id'])
                        )
                    continue  # Skip to next task
                
                # CONDITION 2: WAIT
                # If any parent is not completed, we must wait
                if any(s != 'completed' for s in statuses):
                    # Auto-recover from blocked if parent was fixed
                    if task['status'] == 'blocked':
                        conn.execute(
                            "UPDATE tasks SET status='pending' WHERE id=?", 
                            (task['id'],)
                        )
                    continue  # Skip to next task
            
            # CONDITION 3: EXECUTE
            # All parents completed (or no deps) - ready to run!
            
            # Context Injection
            deps_context = ""
            if deps:
                rows = conn.execute(
                    f"SELECT id, output FROM tasks WHERE id IN ({','.join(map(str, deps))})"
                ).fetchall()
                for r in rows: 
                    deps_context += f"\n[Task {r['id']} Output]: {r['output']}"
            
            # Include mode in task context
            mode = get_mode()
            mode_context = f"\n\n=== MODE: {mode.upper()} ===" 
            if mode == "converge":
                mode_context += "\nREQUIRED: Run unit tests before reporting done."
            elif mode == "ship":
                mode_context += "\nREQUIRED: Run full test suite. No TODOs allowed."
            
            full_desc = f"{task['desc']}\n\n=== CONTEXT ==={deps_context}{mode_context}"
            
            conn.execute(
                "UPDATE tasks SET status='in_progress', worker_id=?, updated_at=? WHERE id=?", 
                (worker_id, int(time.time()), task['id'])
            )
            return f'{{"id": {task["id"]}, "description": "{full_desc}"}}'
            
    return "NO_WORK"


@mcp.tool()
def complete_task(task_id: int, output: str, success: bool = True, files_changed: str = "[]", test_result: str = "SKIPPED") -> str:
    """Marks task complete with structured output."""
    mode = get_mode()
    
    with get_db() as conn:
        # Get task info for potential QA generation
        task = conn.execute("SELECT type, desc FROM tasks WHERE id=?", (task_id,)).fetchone()
        
        if success:
            conn.execute(
                "UPDATE tasks SET status='completed', output=?, files_changed=?, test_result=?, updated_at=? WHERE id=?", 
                (output, files_changed, test_result, int(time.time()), task_id)
            )
            
            # AUTO-QA: Generate QA task in converge/ship mode for backend/frontend tasks
            qa_msg = ""
            if mode in ['converge', 'ship'] and task and task['type'] in ['backend', 'frontend']:
                qa_desc = f"VERIFY Task {task_id}: {task['desc'][:100]}. Check: {output[:200]}"
                cursor = conn.execute(
                    "INSERT INTO tasks (type, desc, deps, status, updated_at, priority) VALUES ('qa', ?, ?, 'pending', ?, 2)",
                    (qa_desc, json.dumps([task_id]), int(time.time()))
                )
                qa_msg = f" → QA Task {cursor.lastrowid} auto-generated."
            
            return f"Task Completed.{qa_msg}"
        else:
            row = conn.execute("SELECT retry_count FROM tasks WHERE id=?", (task_id,)).fetchone()
            current_retries = row[0] if row else 0
            
            if current_retries < 3:
                conn.execute(
                    "UPDATE tasks SET status='pending', worker_id=NULL, retry_count=retry_count+1, output=?, updated_at=? WHERE id=?", 
                    (f"Retry #{current_retries + 1}: {output}", int(time.time()), task_id)
                )
                return f"Task Failed. Auto-retrying ({current_retries + 1}/3)..."
            else:
                conn.execute(
                    "UPDATE tasks SET status='failed', output=?, updated_at=? WHERE id=?", 
                    (output, int(time.time()), task_id)
                )
                return "Task Failed. Max retries exceeded."

@mcp.tool()
def reopen_task(task_id: int, reason: str = "") -> str:
    """Reopen a completed/failed task for rework."""
    with get_db() as conn:
        task = conn.execute("SELECT status, desc FROM tasks WHERE id=?", (task_id,)).fetchone()
        if not task:
            return f"Task {task_id} not found."
        
        new_desc = f"REWORK: {task['desc']}"
        if reason:
            new_desc += f"\n\nREASON: {reason}"
        
        conn.execute(
            "UPDATE tasks SET status='pending', worker_id=NULL, desc=?, updated_at=? WHERE id=?",
            (new_desc, int(time.time()), task_id)
        )
        return f"Task {task_id} reopened for rework."

@mcp.tool()
def get_review_stats() -> str:
    """Get stats for milestone review."""
    with get_db() as conn:
        last_review = conn.execute("SELECT value FROM config WHERE key='last_review'").fetchone()
        last_review_ts = int(last_review[0]) if last_review else 0
        
        # Count tasks since last review
        completed = conn.execute(
            "SELECT COUNT(*) FROM tasks WHERE status='completed' AND updated_at > ?", (last_review_ts,)
        ).fetchone()[0]
        
        failed = conn.execute(
            "SELECT COUNT(*) FROM tasks WHERE status='failed' AND updated_at > ?", (last_review_ts,)
        ).fetchone()[0]
        
        # Get all outputs for changelog
        outputs = conn.execute(
            "SELECT type, desc, output FROM tasks WHERE status='completed' AND updated_at > ? ORDER BY id", 
            (last_review_ts,)
        ).fetchall()
        
        changelog_items = []
        for o in outputs:
            if o['output']:
                changelog_items.append(f"- [{o['type'].upper()}] {o['desc'][:60]}")
        
        mode = get_mode()
        
        return f"""📊 MILESTONE REVIEW
Mode: {mode.upper()}
Tasks completed: {completed}
Tasks failed: {failed}
Last review: {datetime.fromtimestamp(last_review_ts).strftime('%Y-%m-%d %H:%M') if last_review_ts else 'Never'}

📝 CHANGELOG:
{chr(10).join(changelog_items[:20]) if changelog_items else '(No completed tasks)'}"""

@mcp.tool()
def mark_review_done() -> str:
    """Mark current time as last review point."""
    with get_db() as conn:
        conn.execute("UPDATE config SET value=? WHERE key='last_review'", (str(int(time.time())),))
    return "Review checkpoint saved."

@mcp.tool()
def save_artifact(key: str, value: str, worker_id: str) -> str:
    """Save shared knowledge."""
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO artifacts (key, value, worker_id, updated_at) VALUES (?, ?, ?, ?)",
            (key.upper(), value, worker_id, int(time.time()))
        )
    return f"Artifact '{key}' saved."

@mcp.tool()
def read_artifact(key: str) -> str:
    """Read shared knowledge."""
    with get_db() as conn:
        row = conn.execute("SELECT value FROM artifacts WHERE key = ?", (key.upper(),)).fetchone()
    return row[0] if row else "NOT_FOUND"

@mcp.tool()
def list_artifacts() -> str:
    """See what keys are available."""
    with get_db() as conn:
        rows = conn.execute("SELECT key, value FROM artifacts").fetchall()
    return "\n".join([f"{r[0]}: {r[1]}" for r in rows])

@mcp.tool()
def dashboard() -> str:
    """Returns queue view with mode indicator and blocked status."""
    mode = get_mode()
    with get_db() as conn:
        rows = conn.execute("SELECT id, type, status, priority, desc, test_result FROM tasks ORDER BY id DESC LIMIT 15").fetchall()
    
    icons = {"vibe": "🟢", "converge": "🟡", "ship": "🔴"}
    header = f"{icons.get(mode, '⚪')} MODE: {mode.upper()}\n{'─' * 50}\n"
    
    report = []
    for r in rows:
        desc_preview = (r[4][:35] + '..') if len(r[4]) > 35 else r[4]
        # Status icons including BLOCKED
        status_icons = {
            "completed": "✅",
            "in_progress": "🔄", 
            "pending": "⏳",
            "blocked": "🚫",  # NEW: Blocked by failed parent
            "failed": "❌"
        }
        status_icon = status_icons.get(r[2], "❓")
        test_badge = f"[{r[5]}]" if r[5] != "SKIPPED" else ""
        report.append(f"[{r[0]}] {status_icon} {r[1].upper()} P{r[3]} {test_badge}: {desc_preview}")
        
    return header + ("\n".join(report) if report else "No tasks in queue.")

@mcp.tool()
def nuke_queue() -> str:
    """🚨 EMERGENCY: Deletes all PENDING tasks."""
    with get_db() as conn:
        count = conn.execute("DELETE FROM tasks WHERE status='pending'").rowcount
    return f"🚨 Deleted {count} pending tasks."

# --- DECISION MANAGEMENT ---
@mcp.tool()
def post_decision(priority: str, question: str, context: str = "") -> str:
    """Log a decision needed from Product Team (red/yellow/green)."""
    if priority.lower() not in ['red', 'yellow', 'green']:
        return "Invalid priority. Use: red, yellow, green"
    with get_db() as conn:
        conn.execute(
            "INSERT INTO decisions (priority, question, context, created_at) VALUES (?, ?, ?, ?)",
            (priority.lower(), question, context, int(time.time()))
        )
    return f"Decision logged ({priority.upper()})."

@mcp.tool()
def get_pending_decisions() -> str:
    """Get all pending decisions sorted by priority."""
    with get_db() as conn:
        rows = conn.execute("""
            SELECT id, priority, question 
            FROM decisions 
            WHERE status='pending' 
            ORDER BY 
                CASE priority WHEN 'red' THEN 1 WHEN 'yellow' THEN 2 ELSE 3 END,
                created_at ASC
            LIMIT 10
        """).fetchall()
    
    if not rows:
        return "No pending decisions."
    
    icons = {"red": "🔴", "yellow": "🟡", "green": "🟢"}
    result = []
    for r in rows:
        result.append(f"[{r[0]}] {icons.get(r[1], '⚪')} {r[2]}")
    return "\n".join(result)

@mcp.tool()
def resolve_decision(decision_id: int, answer: str) -> str:
    """Resolve a pending decision with an answer."""
    with get_db() as conn:
        conn.execute(
            "UPDATE decisions SET status='resolved', answer=? WHERE id=?",
            (answer, decision_id)
        )
    return f"Decision {decision_id} resolved."

@mcp.tool()
def get_project_status() -> str:
    """Get full project status for control panel."""
    mode = get_mode()
    days_left = None
    
    if os.path.exists(MILESTONE_FILE):
        try:
            with open(MILESTONE_FILE, 'r') as f:
                milestone = date.fromisoformat(f.read().strip())
            days_left = (milestone - date.today()).days
        except:
            pass
    
    with get_db() as conn:
        stats = conn.execute("""
            SELECT status, COUNT(*) as c FROM tasks GROUP BY status
        """).fetchall()
        
        decisions = conn.execute("""
            SELECT priority, COUNT(*) as c FROM decisions 
            WHERE status='pending' GROUP BY priority
        """).fetchall()
    
    status_counts = {s[0]: s[1] for s in stats}
    decision_counts = {d[0]: d[1] for d in decisions}
    
    return json.dumps({
        "mode": mode,
        "days_left": days_left,
        "pending": status_counts.get("pending", 0),
        "active": status_counts.get("in_progress", 0),
        "completed": status_counts.get("completed", 0),
        "failed": status_counts.get("failed", 0),
        "blocked": status_counts.get("blocked", 0),
        "decisions": {
            "red": decision_counts.get("red", 0),
            "yellow": decision_counts.get("yellow", 0),
            "green": decision_counts.get("green", 0)
        }
    })

# --- AUDITOR MANAGEMENT ---

# Security Tripwire Patterns (override everything)
BANNED_PATTERNS = [
    "dangerouslySetInnerHTML", "innerHTML",  # XSS
    "eval(", "exec(", "shell=True",          # Injection
    "DROP TABLE", "DELETE FROM",             # DB Destructive
    "api_key =", "password =", "secret =",   # Hardcoded Secrets
    "0.0.0.0", "allow_origins=['*']",        # Permissive Config
    "disable_ssl", "verify=False"            # Security Bypass
]

CRITICAL_FILE_PATTERNS = ['auth', 'security', 'payment', 'db', 'schema', 
                          'api/admin', 'middleware', 'session', 'crypto']
RELAXED_FILE_PATTERNS = ['css', 'style', 'ui/', 'component', '.test.', 
                         '.spec.', 'mock', 'fixture']

@mcp.tool()
def determine_strictness(files_changed: str, task_desc: str, code_diff: str = "") -> str:
    """Determine task strictness level with Security Tripwire protection."""
    files_list = json.loads(files_changed) if files_changed else []
    
    # 1. SECURITY TRIPWIRES (Override EVERYTHING)
    for pattern in BANNED_PATTERNS:
        if pattern in code_diff:
            return json.dumps({
                "strictness": "CRITICAL",
                "reason": f"TRIPWIRE: Found '{pattern}'",
                "forced": True
            })
    
    # 2. MANUAL OVERRIDES
    desc_upper = task_desc.upper()
    if "[CRITICAL]" in desc_upper:
        return json.dumps({"strictness": "CRITICAL", "reason": "Manual tag", "forced": False})
    if "[RELAXED]" in desc_upper:
        return json.dumps({"strictness": "RELAXED", "reason": "Manual tag", "forced": False})
    if "[NORMAL]" in desc_upper:
        return json.dumps({"strictness": "NORMAL", "reason": "Manual tag", "forced": False})
    
    # 3. FILE PATTERN DETECTION
    for f in files_list:
        for pattern in CRITICAL_FILE_PATTERNS:
            if pattern in f.lower():
                return json.dumps({"strictness": "CRITICAL", "reason": f"File pattern: {pattern}", "forced": False})
    
    for f in files_list:
        for pattern in RELAXED_FILE_PATTERNS:
            if pattern in f.lower():
                return json.dumps({"strictness": "RELAXED", "reason": f"File pattern: {pattern}", "forced": False})
    
    return json.dumps({"strictness": "NORMAL", "reason": "Default", "forced": False})

@mcp.tool()
def record_audit(task_id: int, action: str, strictness: str, reason: str = "") -> str:
    """Record an audit action (review/reject/approve/escalate)."""
    with get_db() as conn:
        # Get current retry count
        task = conn.execute("SELECT retry_count FROM tasks WHERE id=?", (task_id,)).fetchone()
        retry_count = task[0] if task else 0
        
        conn.execute(
            "INSERT INTO audit_log (task_id, action, strictness, reason, retry_count, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            (task_id, action, strictness, reason, retry_count, int(time.time()))
        )
        
        # Update task auditor status
        if action == 'approve':
            conn.execute("UPDATE tasks SET auditor_status='approved', retry_count=0 WHERE id=?", (task_id,))
        elif action == 'reject':
            conn.execute("UPDATE tasks SET auditor_status='rejected', retry_count=retry_count+1 WHERE id=?", (task_id,))
        elif action == 'escalate':
            conn.execute("UPDATE tasks SET auditor_status='escalated', status='blocked' WHERE id=?", (task_id,))
    
    return f"Audit recorded: {action} for task {task_id}"

@mcp.tool()
def get_audit_status(task_id: int) -> str:
    """Get current audit status for a task."""
    with get_db() as conn:
        task = conn.execute(
            "SELECT status, strictness, auditor_status, retry_count, auditor_feedback FROM tasks WHERE id=?",
            (task_id,)
        ).fetchone()
        
        if not task:
            return json.dumps({"error": "Task not found"})
        
        logs = conn.execute(
            "SELECT action, reason, created_at FROM audit_log WHERE task_id=? ORDER BY created_at DESC LIMIT 5",
            (task_id,)
        ).fetchall()
    
    return json.dumps({
        "task_id": task_id,
        "status": task[0],
        "strictness": task[1],
        "auditor_status": task[2],
        "retry_count": task[3],
        "can_continue": task[3] < 3 and task[2] != 'escalated',
        "logs": [{"action": l[0], "reason": l[1], "at": l[2]} for l in logs]
    })

@mcp.tool()
def reset_task_auditor(task_id: int) -> str:
    """Reset auditor state after user intervention (for blocked tasks)."""
    with get_db() as conn:
        conn.execute("""
            UPDATE tasks 
            SET retry_count=0, 
                auditor_status='pending', 
                auditor_feedback='[]',
                status='pending'
            WHERE id=?
        """, (task_id,))
        
        conn.execute(
            "INSERT INTO audit_log (task_id, action, strictness, reason, retry_count, created_at) VALUES (?, 'reset', 'N/A', 'User intervention', 0, ?)",
            (task_id, int(time.time()))
        )
    
    return f"Task {task_id} auditor state reset. Ready for retry."

@mcp.tool()
def get_audit_log(limit: int = 10) -> str:
    """Get recent audit log entries."""
    with get_db() as conn:
        logs = conn.execute("""
            SELECT a.id, a.task_id, t.desc, a.action, a.strictness, a.reason, a.retry_count, a.created_at
            FROM audit_log a
            LEFT JOIN tasks t ON a.task_id = t.id
            ORDER BY a.created_at DESC
            LIMIT ?
        """, (limit,)).fetchall()
    
    result = []
    for l in logs:
        result.append({
            "id": l[0],
            "task_id": l[1],
            "task_desc": l[2][:30] if l[2] else "N/A",
            "action": l[3],
            "strictness": l[4],
            "reason": l[5],
            "retry": l[6],
            "at": l[7]
        })
    
    return json.dumps(result)

# --- PATCH 2: CONTEXT FLUSH (Force Auditor Re-read) ---

@mcp.tool()
def flush_auditor_context(task_id: int) -> str:
    """
    Force Auditor to clear cache and re-read files from disk.
    Use after user manual intervention on blocked tasks.
    """
    with get_db() as conn:
        # Clear cached feedback
        conn.execute("""
            UPDATE tasks 
            SET auditor_feedback='[]',
                auditor_status='pending'
            WHERE id=?
        """, (task_id,))
        
        # Log the flush
        conn.execute("""
            INSERT INTO audit_log 
            (task_id, action, strictness, reason, retry_count, created_at)
            VALUES (?, 'context_flush', 'N/A', 'User intervention - context cleared', 0, ?)
        """, (task_id, int(time.time())))
    
    return json.dumps({
        "success": True,
        "message": f"Context flushed for task {task_id}. Auditor will re-read from disk."
    })

# --- PATCH 3: PORT CLEANUP (Kill Zombie Processes) ---

import socket
import subprocess
import platform

@mcp.tool()
def check_port_available(port: int) -> str:
    """Check if a port is available for use."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.bind(('localhost', port))
        sock.close()
        return json.dumps({"available": True, "port": port})
    except socket.error:
        return json.dumps({"available": False, "port": port, "reason": "Port in use"})

# Allowed port range for safety (Issue #7)
ALLOWED_PORT_RANGE = range(3000, 10001)
ALLOWED_EXTRA_PORTS = {8000, 8080, 5000, 5173, 4200, 9000}

@mcp.tool()
def kill_process_on_port(port: int) -> str:
    """
    Kill process occupying a specific port. Use for zombie server cleanup.
    SECURITY: Port range validation, no shell=True, specific exception handling.
    """
    import logging
    logger = logging.getLogger("MeshServer")
    
    # FIX Issue #7: Port range validation - prevent killing system services
    if port not in ALLOWED_PORT_RANGE and port not in ALLOWED_EXTRA_PORTS:
        return json.dumps({
            "success": False, 
            "error": f"Security Block: Port {port} outside allowed dev range (3000-10000)"
        })
    
    try:
        if platform.system() == "Windows":
            # FIX Issue #2: No shell=True - use list arguments
            # Step 1: Get netstat output
            netstat_result = subprocess.run(
                ["netstat", "-ano"],
                capture_output=True, 
                text=True,
                check=False
            )
            
            pids = set()
            target_str = f":{port}"
            
            for line in netstat_result.stdout.splitlines():
                if target_str in line and ("LISTENING" in line or "ESTABLISHED" in line):
                    parts = line.split()
                    if len(parts) >= 5 and parts[-1].isdigit():
                        pids.add(parts[-1])
            
            if not pids:
                return json.dumps({"success": True, "message": f"No process on port {port}"})
            
            killed = []
            for pid in pids:
                if not pid.isdigit():
                    continue
                try:
                    # FIX Issue #2: No shell=True for taskkill
                    subprocess.run(
                        ["taskkill", "/PID", pid, "/F"],
                        capture_output=True,
                        check=False
                    )
                    killed.append(pid)
                except subprocess.SubprocessError as e:
                    logger.warning(f"Failed to kill PID {pid}: {e}")
            
            return json.dumps({"success": True, "killed_pids": killed, "port": port})
        
        else:
            # Unix/Mac - use lsof without shell=True
            try:
                # FIX Issue #2: No shell=True - use list arguments
                result = subprocess.run(
                    ["lsof", "-t", f"-i:{port}"],
                    capture_output=True, 
                    text=True,
                    check=False
                )
                
                if not result.stdout.strip():
                    return json.dumps({"success": True, "message": f"No process on port {port}"})
                
                pids = [p for p in result.stdout.strip().split('\n') if p.isdigit()]
                
                if pids:
                    # FIX Issue #2: No shell=True for kill
                    subprocess.run(
                        ["kill", "-9"] + pids,
                        capture_output=True,
                        check=False
                    )
                
                return json.dumps({"success": True, "killed_pids": pids, "port": port})
            
            except FileNotFoundError:
                return json.dumps({"success": False, "error": "lsof command not found"})
    
    # FIX Issue #1: No bare except - specific exception handling
    except subprocess.SubprocessError as e:
        logger.error(f"Subprocess error killing port {port}: {e}")
        return json.dumps({"success": False, "error": f"Subprocess error: {e}"})
    except Exception as e:
        logger.error(f"Failed to kill port {port}: {e}")
        return json.dumps({"success": False, "error": str(e)})

@mcp.tool()
def cleanup_dev_environment() -> str:
    """Kill common dev server zombie processes on typical ports."""
    common_ports = [3000, 3001, 5000, 5173, 8000, 8080, 4200, 9000]
    cleaned = []
    still_busy = []
    
    for port in common_ports:
        check = json.loads(check_port_available(port))
        if not check["available"]:
            result = json.loads(kill_process_on_port(port))
            if result.get("success"):
                cleaned.append(port)
            else:
                still_busy.append(port)
    
    return json.dumps({
        "cleaned_ports": cleaned,
        "still_busy": still_busy,
        "message": f"Cleaned {len(cleaned)} ports"
    })

@mcp.tool()
def get_port_status(ports: str = "3000,3001,5000,8000,8080") -> str:
    """Check status of multiple ports. Comma-separated list."""
    port_list = [int(p.strip()) for p in ports.split(",")]
    status = []
    
    for port in port_list:
        check = json.loads(check_port_available(port))
        status.append({
            "port": port,
            "available": check["available"],
            "status": "FREE" if check["available"] else "IN USE"
        })
    
    return json.dumps({"ports": status})

# --- SEMANTIC ROUTER ---

# Import router
try:
    from router import SemanticRouter, IntentExecutor, create_router, route_and_execute
    ROUTER_AVAILABLE = True
except ImportError:
    ROUTER_AVAILABLE = False

# Create global router instance
_router = None
_executor = None

def get_router():
    global _router, _executor
    if _router is None and ROUTER_AVAILABLE:
        _router, _executor = create_router(DB_PATH)
    return _router, _executor

# --- PATCH 1: JIT CONTEXT INJECTION ---

def get_jit_context() -> Dict:
    """
    Just-In-Time context fetch (Patch 1: Context Lag Fix).
    Called IMMEDIATELY before delegator starts to ensure fresh context.
    """
    context = {
        "decisions": "",
        "resolved_decisions": [],
        "blockers": [],
        "notes": [],
        "session": {}
    }
    
    # 1. Latest decisions from file
    decision_file = os.path.join(DOCS_DIR, "DECISION_LOG.md")
    if os.path.exists(decision_file):
        try:
            with open(decision_file, 'r', encoding='utf-8') as f:
                content = f.read()
                # Get last 2000 chars for context window efficiency
                context["decisions"] = content[-2000:] if len(content) > 2000 else content
        except:
            pass
    
    # 2. Resolved decisions from DB
    with get_db() as conn:
        resolved = conn.execute("""
            SELECT question, answer FROM decisions 
            WHERE status='resolved' 
            ORDER BY id DESC LIMIT 5
        """).fetchall()
        context["resolved_decisions"] = [{"q": r[0], "a": r[1]} for r in resolved]
        
        # 3. Active blockers (RED priority)
        blockers = conn.execute("""
            SELECT question FROM decisions 
            WHERE priority='red' AND status='pending'
        """).fetchall()
        context["blockers"] = [b[0] for b in blockers]
        
        # 4. Recent notes
        notes = conn.execute("""
            SELECT value FROM config WHERE key='last_note'
        """).fetchone()
        if notes:
            context["notes"].append(notes[0])
    
    # 5. Session context (from router)
    try:
        with get_db() as conn:
            session = conn.execute(
                "SELECT key, value FROM session_context"
            ).fetchall()
            context["session"] = {s[0]: json.loads(s[1]) for s in session}
    except:
        pass
    
    return context

@mcp.tool()
def trigger_delegation(task_id: int) -> str:
    """
    EXECUTE trigger with JIT context injection (Patch 1).
    This ensures the delegator always has the latest decisions/notes.
    """
    # CRITICAL: Fetch fresh context
    context = get_jit_context()
    
    with get_db() as conn:
        task = conn.execute(
            "SELECT id, type, desc, status, priority FROM tasks WHERE id=?",
            (task_id,)
        ).fetchone()
    
    if not task:
        return json.dumps({"error": f"Task {task_id} not found"})
    
    # Check for blockers
    if context["blockers"]:
        return json.dumps({
            "status": "blocked",
            "task_id": task_id,
            "blockers": context["blockers"],
            "message": f"🔴 {len(context['blockers'])} active blockers. Resolve before continuing."
        })
    
    # Build augmented task payload
    augmented = {
        "task": {
            "id": task[0],
            "type": task[1],
            "desc": task[2],
            "status": task[3],
            "priority": task[4]
        },
        "context": {
            "decisions": context["decisions"],
            "resolved": context["resolved_decisions"],
            "notes": context["notes"]
        }
    }
    
    return json.dumps({
        "status": "delegating",
        "task_id": task_id,
        "context_injected": True,
        "decision_count": len(context["resolved_decisions"]),
        "augmented_payload": augmented
    })

@mcp.tool()
def route_input(user_input: str) -> str:
    """
    Route user input through the Semantic Router.
    Returns classified intent, action, and parameters.
    """
    if not ROUTER_AVAILABLE:
        return json.dumps({"error": "Router not available"})
    
    router, executor = get_router()
    if not router:
        return json.dumps({"error": "Router initialization failed"})
    
    route = router.route(user_input)
    return json.dumps(route.to_dict())

@mcp.tool()
def execute_routed_intent(user_input: str) -> str:
    """
    Route AND execute user input in one call.
    Returns execution result with route info.
    """
    if not ROUTER_AVAILABLE:
        return json.dumps({"error": "Router not available"})
    
    result = route_and_execute(DB_PATH, user_input)
    return json.dumps(result)

@mcp.tool()
def update_task_context(task_id: int, context_type: str = "shown") -> str:
    """
    Update session context for pronoun resolution.
    context_type: 'shown' (displayed to user) or 'mentioned' (user referenced)
    """
    if not ROUTER_AVAILABLE:
        return json.dumps({"error": "Router not available"})
    
    router, _ = get_router()
    if context_type == "shown":
        router.update_last_shown_task(task_id)
    else:
        router.update_last_mentioned_task(task_id)
    
    return json.dumps({"success": True, "task_id": task_id, "type": context_type})

@mcp.tool()
def get_route_history(limit: int = 10) -> str:
    """Get recent routing decisions for debugging."""
    with get_db() as conn:
        rows = conn.execute("""
            SELECT input, intent, action, parameters, confidence, source, created_at
            FROM route_log ORDER BY created_at DESC LIMIT ?
        """, (limit,)).fetchall()
    
    result = []
    for r in rows:
        result.append({
            "input": r[0],
            "intent": r[1],
            "action": r[2],
            "parameters": json.loads(r[3]) if r[3] else None,
            "confidence": r[4],
            "source": r[5],
            "at": r[6]
        })
    
    return json.dumps(result)

@mcp.tool()
def reorder_task_by_keyword(keyword: str, position: str = "top") -> str:
    """
    Reorder tasks matching keyword to top or bottom.
    Used for 'prioritize X' commands.
    """
    with get_db() as conn:
        if position == "top":
            conn.execute("""
                UPDATE tasks SET priority = 99 
                WHERE status='pending' AND desc LIKE ?
            """, (f"%{keyword}%",))
        else:
            conn.execute("""
                UPDATE tasks SET priority = 0 
                WHERE status='pending' AND desc LIKE ?
            """, (f"%{keyword}%",))
        
        affected = conn.execute(
            "SELECT COUNT(*) FROM tasks WHERE desc LIKE ?", 
            (f"%{keyword}%",)
        ).fetchone()[0]
    
    return json.dumps({
        "success": True,
        "keyword": keyword,
        "position": position,
        "tasks_affected": affected
    })

# --- LIBRARIAN MANAGEMENT ---

# Import librarian tools
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from librarian_tools import (
        librarian_full_scan, 
        generate_restore_script,
        execute_operation,
        scan_for_secrets,
        check_file_references
    )
    LIBRARIAN_AVAILABLE = True
except ImportError:
    LIBRARIAN_AVAILABLE = False

@mcp.tool()
def librarian_scan(project_path: str) -> str:
    """Safely scan project directory and generate a manifest of proposed operations."""
    if not LIBRARIAN_AVAILABLE:
        return json.dumps({"error": "Librarian tools not available"})
    
    try:
        manifest = librarian_full_scan(project_path)
        
        # Store pending operations in database
        with get_db() as conn:
            for op in manifest["operations"]:
                conn.execute("""
                    INSERT INTO librarian_ops 
                    (manifest_id, action, from_path, to_path, risk_level, status, created_at)
                    VALUES (?, ?, ?, ?, ?, 'pending', ?)
                """, (
                    manifest["manifest_id"],
                    op["action"],
                    op.get("from", op.get("target", "")),
                    op.get("to", ""),
                    op.get("risk", "LOW"),
                    int(time.time())
                ))
            
            for blocked in manifest["blocked_operations"]:
                conn.execute("""
                    INSERT INTO librarian_ops 
                    (manifest_id, action, from_path, risk_level, status, blocked_reason, created_at)
                    VALUES (?, ?, ?, ?, 'blocked', ?, ?)
                """, (
                    manifest["manifest_id"],
                    blocked["action"],
                    blocked["target"],
                    blocked["risk"],
                    blocked["reason"],
                    int(time.time())
                ))
        
        return json.dumps(manifest)
    
    except Exception as e:
        return json.dumps({"error": str(e)})

@mcp.tool()
def librarian_approve(manifest_id: str) -> str:
    """Approve a pending manifest for execution."""
    with get_db() as conn:
        # Check for blocked operations
        blocked = conn.execute(
            "SELECT COUNT(*) FROM librarian_ops WHERE manifest_id=? AND status='blocked'",
            (manifest_id,)
        ).fetchone()[0]
        
        if blocked > 0:
            return json.dumps({
                "approved": False,
                "reason": f"{blocked} blocked operations require manual review"
            })
        
        # Approve all pending
        conn.execute(
            "UPDATE librarian_ops SET status='approved' WHERE manifest_id=? AND status='pending'",
            (manifest_id,)
        )
        
        count = conn.execute(
            "SELECT COUNT(*) FROM librarian_ops WHERE manifest_id=? AND status='approved'",
            (manifest_id,)
        ).fetchone()[0]
    
    return json.dumps({"approved": True, "operations_approved": count})

@mcp.tool()
def librarian_execute(manifest_id: str) -> str:
    """Execute an approved manifest with backup."""
    if not LIBRARIAN_AVAILABLE:
        return json.dumps({"error": "Librarian tools not available"})
    
    backup_dir = os.path.join(DB_DIR, ".librarian_backups", manifest_id)
    os.makedirs(backup_dir, exist_ok=True)
    
    results = {"executed": 0, "failed": 0, "errors": [], "restore_script": ""}
    
    with get_db() as conn:
        ops = conn.execute("""
            SELECT id, action, from_path, to_path FROM librarian_ops 
            WHERE manifest_id=? AND status='approved'
        """, (manifest_id,)).fetchall()
        
        executed_ops = []
        
        for op in ops:
            op_dict = {
                "action": op[1],
                "from": op[2],
                "to": op[3],
                "target": op[2]
            }
            
            result = execute_operation(op_dict, backup_dir)
            
            if result["success"]:
                conn.execute(
                    "UPDATE librarian_ops SET status='executed', executed_at=? WHERE id=?",
                    (int(time.time()), op[0])
                )
                executed_ops.append(op_dict)
                results["executed"] += 1
            else:
                conn.execute(
                    "UPDATE librarian_ops SET status='failed', blocked_reason=? WHERE id=?",
                    (result.get("error", "Unknown error"), op[0])
                )
                results["errors"].append(result.get("error"))
                results["failed"] += 1
        
        # Generate restore script
        if executed_ops:
            restore_dir = os.path.join(DB_DIR, ".system", "restore_points")
            restore_path = generate_restore_script(manifest_id, executed_ops, restore_dir)
            results["restore_script"] = restore_path
            
            # Store restore point
            conn.execute("""
                INSERT INTO restore_points (manifest_id, script_path, operations_json, created_at, expires_at, status)
                VALUES (?, ?, ?, ?, ?, 'active')
            """, (
                manifest_id,
                restore_path,
                json.dumps(executed_ops),
                int(time.time()),
                int(time.time()) + 604800  # 7 days
            ))
    
    return json.dumps(results)

@mcp.tool()
def librarian_status() -> str:
    """Get current librarian status and pending operations."""
    with get_db() as conn:
        pending = conn.execute(
            "SELECT manifest_id, COUNT(*) as c FROM librarian_ops WHERE status='pending' GROUP BY manifest_id"
        ).fetchall()
        
        approved = conn.execute(
            "SELECT manifest_id, COUNT(*) as c FROM librarian_ops WHERE status='approved' GROUP BY manifest_id"
        ).fetchall()
        
        blocked = conn.execute(
            "SELECT manifest_id, action, from_path, blocked_reason FROM librarian_ops WHERE status='blocked' LIMIT 5"
        ).fetchall()
        
        recent_executed = conn.execute(
            "SELECT manifest_id, COUNT(*) as c, MAX(executed_at) FROM librarian_ops WHERE status='executed' GROUP BY manifest_id ORDER BY executed_at DESC LIMIT 3"
        ).fetchall()
    
    return json.dumps({
        "pending_manifests": [{"id": p[0], "count": p[1]} for p in pending],
        "approved_manifests": [{"id": a[0], "count": a[1]} for a in approved],
        "blocked_operations": [{"manifest": b[0], "action": b[1], "file": b[2], "reason": b[3]} for b in blocked],
        "recent_executions": [{"id": r[0], "count": r[1]} for r in recent_executed]
    })

@mcp.tool()
def librarian_restore(manifest_id: str) -> str:
    """Restore from a previous manifest execution."""
    with get_db() as conn:
        restore = conn.execute(
            "SELECT script_path, operations_json FROM restore_points WHERE manifest_id=? AND status='active'",
            (manifest_id,)
        ).fetchone()
        
        if not restore:
            return json.dumps({"error": "No active restore point found"})
        
        script_path = restore[0]
        
        if not os.path.exists(script_path):
            return json.dumps({"error": f"Restore script not found: {script_path}"})
        
        # Execute restore script
        import subprocess
        try:
            result = subprocess.run(['bash', script_path], capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                conn.execute(
                    "UPDATE restore_points SET status='used' WHERE manifest_id=?",
                    (manifest_id,)
                )
                conn.execute(
                    "UPDATE librarian_ops SET status='restored' WHERE manifest_id=?",
                    (manifest_id,)
                )
                return json.dumps({"success": True, "output": result.stdout})
            else:
                return json.dumps({"success": False, "error": result.stderr})
        
        except subprocess.TimeoutExpired:
            return json.dumps({"success": False, "error": "Restore timed out"})
        except Exception as e:
            return json.dumps({"success": False, "error": str(e)})

@mcp.tool()
def check_secrets(file_path: str) -> str:
    """Scan a specific file for secrets. BLOCKS if found."""
    if not LIBRARIAN_AVAILABLE:
        return json.dumps({"error": "Librarian tools not available"})
    
    result = scan_for_secrets(file_path)
    return json.dumps(result)

@mcp.tool()
def check_references(file_path: str, project_root: str) -> str:
    """Find all references to a file in the codebase."""
    if not LIBRARIAN_AVAILABLE:
        return json.dumps({"error": "Librarian tools not available"})
    
    result = check_file_references(file_path, project_root)
    return json.dumps(result)

if __name__ == "__main__":
    mcp.run()
