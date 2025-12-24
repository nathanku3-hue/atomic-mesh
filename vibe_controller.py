"""
Vibe Controller V4.0 Uranium Master
====================================
Autonomous orchestration engine for the Vibe Coding System.

Architecture: HYBRID DELEGATION + PROMPT COMPILER
- Architect can assign specific workers OR use "auto" for load balancing
- Worker tiers (senior/standard) match task complexity
- Skill packs (skills/*.md) auto-injected into task context

Features V4.0:
- Prompt Compiler: expand_task_context() injects lane skill packs
- AGENTS.md: Global constitution for all workers
- LESSONS_LEARNED.md: Auto-appended anti-regression lessons
- Skill Packs: frontend, backend, security, ux, data, qa, _default
- MAX_SKILL_CHARS: Truncation for large skill packs

Features V3.4:
- Specialist Workers: @security-1, @ux-designer, @data-analyst
- DLQ Escalation: Auto-escalate dead letters after 24h

Features V3.3:
- In-Memory Worker Cache: 10s TTL, invalidation on writes
- Weighted Scoring Router: Multi-factor task-worker matching
- Auto-Scaler Hook: Virtual worker provisioning

Features V3.2:
- Worker Tiers: senior workers get effort >= 4 tasks
- effort_rating + priority: Intelligent task-worker matching
- Smart Backoff: network (2s fixed) vs crash (exponential)
- Saturation Guard: Detects and logs when pools are full
- DLQ Management: Dead letter queue for failed tasks
- Priority Inheritance: Guardian tasks inherit parent priority

Features V2.1:
- Auto-Routing: worker_id="auto" → Controller assigns least-busy worker
- Deduplication Guard: Prevents duplicate guardian tasks (QA/Docs)
- Health-Based Routing: capacity_limit per worker

Features V2.0:
- Direct delegation with assignment watchdog (5 min timeout)
- Dynamic load balancing with worker priority scores
- Worker health tracking (active_tasks, last_seen, status)
- Granular audit logging via task_history table

Notification: Console-only (Slack disabled)
"""

import time
import json
import sqlite3
import signal
import sys
import os
import traceback
from typing import Dict, Any, Optional, List
from datetime import datetime

# --- Configuration ---
DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")
LEASE_TIMEOUT_SEC = int(os.getenv("LEASE_TIMEOUT_SEC", "600"))
BLOCKED_TIMEOUT_SEC = int(os.getenv("BLOCKED_TIMEOUT_SEC", "86400"))  # 24 hours
ASSIGNMENT_TIMEOUT_SEC = int(os.getenv("ASSIGNMENT_TIMEOUT_SEC", "300"))  # 5 minutes
IDLE_TIMEOUT_SEC = int(os.getenv("IDLE_TIMEOUT_SEC", "600"))  # 10 minutes
MAX_TASKS_PER_WORKER = int(os.getenv("MAX_TASKS_PER_WORKER", "3"))  # V2.1: Load limit
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "5"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "50"))
MAX_RETRIES = 3
METRICS_INTERVAL = 60  # Collect metrics every minute

# V3.3: Cache & Scaling Config
CACHE_TTL = int(os.getenv("CACHE_TTL", "10"))  # seconds
HISTORY_ARCHIVE_DAYS = int(os.getenv("HISTORY_ARCHIVE_DAYS", "7"))
MAX_AUTO_SCALE_WORKERS = int(os.getenv("MAX_AUTO_SCALE_WORKERS", "5"))

# V4.0: Prompt Compiler Config
SKILLS_DIR = os.getenv("SKILLS_DIR", "skills")
MAX_SKILL_CHARS = int(os.getenv("MAX_SKILL_CHARS", "2000"))  # Truncate large skills
LESSONS_FILE = os.getenv("LESSONS_FILE", "LESSONS_LEARNED.md")

# --- State Management ---
running = True
circuit_breaker_failures = 0
CIRCUIT_BREAKER_THRESHOLD = 3

# --- Prometheus-Ready Metrics ---
metrics = {
    "tasks_completed": 0,
    "tasks_failed": 0,
    "retries_total": 0,
    "circuit_breaker_trips": 0,
    "queue_lengths": {"pending": 0, "in_progress": 0, "review_needed": 0, "blocked": 0},
    "avg_completion_time_ms": 0,
    "last_sweep_recovered": 0,
    "last_metrics_update": 0,
    # V3.3 metrics
    "cache_hits": 0,
    "cache_misses": 0,
    "saturation_events": 0,
    "auto_scale_events": 0,
}

# V3.3: In-Memory Worker Cache
WORKER_CACHE = {}  # {lane: (workers_list, timestamp)}


def handle_signal(signum, frame):
    """Graceful shutdown handler."""
    global running
    timestamp = time.strftime("%H:%M:%S")
    print(f"\n🛑 [{timestamp}] Shutdown signal received ({signum}). Cleaning up...")
    running = False


signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)


# --- V3.3: Cache Functions ---
def get_cached_workers(conn: sqlite3.Connection, lane: str) -> List[Dict]:
    """
    V3.3: Get workers from cache or DB.
    Cache TTL: CACHE_TTL seconds.
    """
    global WORKER_CACHE
    now = time.time()
    
    if lane in WORKER_CACHE:
        cached_workers, cached_time = WORKER_CACHE[lane]
        if now - cached_time < CACHE_TTL:
            metrics["cache_hits"] += 1
            return cached_workers
    
    # Cache miss - query DB
    metrics["cache_misses"] += 1
    try:
        workers = conn.execute("""
            SELECT worker_id, tier, active_tasks, capacity_limit, priority_score, last_seen
            FROM worker_health WHERE lane = ? AND status = 'online'
        """, (lane,)).fetchall()
        
        worker_list = [dict(w) for w in workers]
        WORKER_CACHE[lane] = (worker_list, now)
        return worker_list
    except sqlite3.Error:
        return []


def invalidate_worker_cache(lane: str = None):
    """V3.3: Invalidate cache after worker updates."""
    global WORKER_CACHE
    if lane:
        WORKER_CACHE.pop(lane, None)
    else:
        WORKER_CACHE.clear()


import random  # For tie-breaker

def calculate_worker_score(worker: Dict, effort_rating: int, priority: str) -> int:
    """
    V3.3: Multi-factor scoring for worker selection.
    Higher score = better match.
    """
    score = 0
    
    # Factor 1: Free Capacity (higher = better)
    free = worker.get('capacity_limit', 3) - worker.get('active_tasks', 0)
    score += free * 10
    
    # Factor 2: Tier Match
    if effort_rating >= 4:
        if worker.get('tier') == 'senior':
            score += 50  # Senior bonus for hard tasks
        else:
            score -= 20  # Penalty for standard on hard task
    
    # Factor 3: Priority Override
    if priority == 'critical':
        score += 30
    elif priority == 'high':
        score += 15
    
    # Factor 4: Priority score from worker health
    score += worker.get('priority_score', 50) // 10
    
    return score


# --- Database Layer with Retry ---
def get_db(retry_count: int = 0) -> Optional[sqlite3.Connection]:
    """Get DB connection with exponential backoff retry."""
    global circuit_breaker_failures
    
    if circuit_breaker_failures >= CIRCUIT_BREAKER_THRESHOLD:
        notify_human(0, "CRITICAL: Circuit breaker OPEN - manual intervention required")
        metrics["circuit_breaker_trips"] += 1
        return None
    
    try:
        conn = sqlite3.connect(DB_PATH, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        conn.execute("PRAGMA journal_mode = WAL;")
        circuit_breaker_failures = 0  # Reset on success
        return conn
    except sqlite3.Error as e:
        circuit_breaker_failures += 1
        metrics["retries_total"] += 1
        
        if retry_count < MAX_RETRIES:
            wait_time = 2 ** retry_count  # Exponential backoff: 1, 2, 4 seconds
            print(f"⚠️ [DB] Connection failed, retry {retry_count + 1}/{MAX_RETRIES} in {wait_time}s: {e}")
            time.sleep(wait_time)
            return get_db(retry_count + 1)
        else:
            notify_human(0, f"CRITICAL: DB connection failed after {MAX_RETRIES} retries: {e}")
            return None


# --- The Predictor ---
def predict_next_step(task: Dict[str, Any]) -> str:
    """Predict the next logical step after task completion."""
    goal = task['goal'].lower() if task.get('goal') else ""
    
    if "test" in goal:
        return "Tests implemented. Run `npm test` to verify."
    elif "api" in goal:
        return "Endpoint ready. Check `docs/API.md`."
    elif "ui" in goal:
        return "UI mounted. Check Storybook/Localhost."
    elif "schema" in goal:
        return "Schema updated. Run migration."
    return "Task complete. Review code diff."


# --- Notification Layer (Console + Extensible Hooks) ---
def notify_human(task_id: int, reason: str, priority: str = "info"):
    """
    Console notification with smart classification and hooks for future integrations.
    Priority levels: info, warning, critical
    """
    timestamp = time.strftime("%H:%M:%S")
    icons = {"info": "🔔", "warning": "⚠️", "critical": "🚨"}
    icon = icons.get(priority, "🔔")
    
    # Smart Classification (V1.2)
    category = "General"
    if "file" in reason.lower() or "dependency" in reason.lower():
        category = "Missing Dependency"
    elif "ambiguous" in reason.lower() or "unclear" in reason.lower():
        category = "Ambiguity"
    elif "risk" in reason.lower():
        category = "Risk Gate"
    elif "blocked" in reason.lower():
        category = "Blocked Task"
    
    msg = f"{icon} [{timestamp}] Task #{task_id} [{category}]: {reason}"
    print(msg)
    
    # Future hook: Slack, PagerDuty, Email
    # if SLACK_WEBHOOK_URL and priority == "critical":
    #     payload = {"text": msg}
    #     if priority == "critical": payload['style'] = "danger"
    #     requests.post(SLACK_WEBHOOK_URL, json=payload)
    
    # Persist critical alerts to DB for tracking
    if priority in ["critical", "warning"]:
        try:
            conn = sqlite3.connect(DB_PATH)
            conn.execute(
                "INSERT INTO task_messages (task_id, role, msg_type, content, created_at) VALUES (?, 'system', 'alert', ?, ?)",
                (task_id if task_id else 0, msg, int(time.time()))
            )
            conn.commit()
            conn.close()
        except Exception:
            pass  # Don't fail on alert persistence


# --- V2.0: Audit Logging ---
def log_status(conn: sqlite3.Connection, task_id: int, status: str, worker_id: str, details: str = None):
    """
    Write to immutable task_history for granular audit trail.
    Every status change is permanently logged.
    """
    try:
        conn.execute("""
            INSERT INTO task_history (task_id, status, worker_id, timestamp, details)
            VALUES (?, ?, ?, ?, ?)
        """, (task_id, status, worker_id, int(time.time()), details))
    except sqlite3.Error:
        pass  # Don't fail on audit logging


# --- V2.0: Worker Health Management ---
def update_worker_health(conn: sqlite3.Connection, worker_id: str, action: str):
    """
    Update worker health metrics on task claim/complete.
    Actions: 'claim' (increment active_tasks), 'complete' (decrement, increment completed_today)
    """
    now = int(time.time())
    try:
        if action == 'claim':
            conn.execute("""
                UPDATE worker_health 
                SET active_tasks = active_tasks + 1, last_seen = ?, status = 'busy'
                WHERE worker_id = ?
            """, (now, worker_id))
        elif action == 'complete':
            conn.execute("""
                UPDATE worker_health 
                SET active_tasks = MAX(0, active_tasks - 1), 
                    completed_today = completed_today + 1,
                    last_seen = ?,
                    status = CASE WHEN active_tasks <= 1 THEN 'online' ELSE 'busy' END
                WHERE worker_id = ?
            """, (now, worker_id))
        elif action == 'heartbeat':
            conn.execute("""
                UPDATE worker_health SET last_seen = ? WHERE worker_id = ?
            """, (now, worker_id))
    except sqlite3.Error:
        pass  # Don't fail on health update


def get_fallback_worker(conn: sqlite3.Connection, lane: str, ignore_id: str) -> Optional[str]:
    """
    Dynamic load balancer: Find optimal worker for fallback.
    Considers: active_tasks, priority_score, last_seen.
    Returns best worker_id or None if no alternatives.
    """
    try:
        # Query for online workers in this lane, excluding ignored worker
        # Order by: lowest active_tasks, highest priority_score, most recent last_seen
        row = conn.execute("""
            SELECT worker_id FROM worker_health
            WHERE lane = ? AND worker_id != ? AND status != 'offline'
            ORDER BY active_tasks ASC, priority_score DESC, last_seen DESC
            LIMIT 1
        """, (lane, ignore_id)).fetchone()
        
        if row:
            return row['worker_id']
        
        # Fallback to hardcoded alternatives if worker_health is empty
        fallbacks = {
            'backend': ['@backend-1', '@backend-2'],
            'frontend': ['@frontend-1', '@frontend-2'],
            'qa': ['@qa-1'],
            'docs': ['@librarian']
        }
        candidates = fallbacks.get(lane, [])
        for w in candidates:
            if w != ignore_id:
                return w
        return None
        
    except sqlite3.Error:
        return None


def handle_worker_idle(conn: sqlite3.Connection) -> int:
    """
    Detect workers that have been idle (no heartbeat) for too long.
    Marks them as 'offline' and alerts admin.
    Returns count of workers marked offline.
    """
    now = int(time.time())
    threshold = now - IDLE_TIMEOUT_SEC
    marked = 0
    
    try:
        idle_workers = conn.execute("""
            SELECT worker_id, lane FROM worker_health
            WHERE status != 'offline' AND last_seen < ? AND last_seen > 0
        """, (threshold,)).fetchall()
        
        for worker in idle_workers:
            conn.execute("""
                UPDATE worker_health SET status = 'offline' WHERE worker_id = ?
            """, (worker['worker_id'],))
            notify_human(0, f"Worker {worker['worker_id']} ({worker['lane']}) marked OFFLINE (idle > {IDLE_TIMEOUT_SEC//60}min)", "warning")
            marked += 1
        
        if marked > 0:
            conn.commit()
            
    except sqlite3.Error as e:
        print(f"⚠️ [Health] DB Error: {e}")
    
    return marked


# --- V2.0: Assignment Watchdog ---
def enforce_assignments(conn: sqlite3.Connection) -> int:
    """
    Watchdog: Detect tasks that have been pending too long (ignored by assigned worker).
    Reassigns to fallback worker or escalates to admin.
    Returns count of tasks reassigned.
    """
    now = int(time.time())
    threshold = now - ASSIGNMENT_TIMEOUT_SEC
    reassigned = 0
    
    try:
        # Find tasks pending longer than assignment timeout
        ignored = conn.execute(f"""
            SELECT * FROM tasks 
            WHERE status = 'pending' AND created_at < ?
            LIMIT {BATCH_SIZE}
        """, (threshold,)).fetchall()
        
        for task in ignored:
            task_id = task['id']
            original_worker = task['worker_id']
            lane = task['lane']
            meta = json.loads(task['metadata'] or '{}')
            
            # Check if fallback already tried
            if meta.get('fallback_tried'):
                notify_human(task_id, 
                    f"Task ignored by PRIMARY ({original_worker}) and FALLBACK. Human intervention needed.", 
                    "critical")
                continue
            
            # Try to find fallback worker
            fallback = get_fallback_worker(conn, lane, original_worker)
            
            if fallback:
                print(f"⚠️ [Watchdog] Worker {original_worker} unresponsive. Reassigning #{task_id} to {fallback}.")
                meta['fallback_tried'] = True
                meta['original_worker'] = original_worker
                
                conn.execute("""
                    UPDATE tasks SET worker_id = ?, metadata = ?, updated_at = ? WHERE id = ?
                """, (fallback, json.dumps(meta), now, task_id))
                
                log_status(conn, task_id, "reassigned", fallback, f"Fallback from {original_worker}")
                reassigned += 1
            else:
                notify_human(task_id, f"No fallback workers available for lane '{lane}'. Task stuck.", "critical")
        
        if reassigned > 0:
            conn.commit()
            
    except sqlite3.Error as e:
        print(f"⚠️ [Watchdog] DB Error: {e}")
        traceback.print_exc()
    
    return reassigned


# --- V2.1: Auto-Router (Hybrid Delegation) ---
def get_best_worker_for_lane(conn: sqlite3.Connection, lane: str) -> Optional[str]:
    """
    V2.1 Auto-Router: Find least-loaded worker in the lane.
    Used when Architect sets worker_id='auto'.
    
    Selection criteria:
    1. status='online' (not offline)
    2. active_tasks < MAX_TASKS_PER_WORKER
    3. Order by: active_tasks ASC, last_seen DESC
    """
    try:
        # Bootstrap default workers if missing (first run)
        defaults = {
            'backend': ['@backend-1', '@backend-2'],
            'frontend': ['@frontend-1', '@frontend-2'],
            'qa': ['@qa-1'],
            'docs': ['@librarian']
        }
        for w in defaults.get(lane, []):
            conn.execute("""
                INSERT OR IGNORE INTO worker_health (worker_id, lane, last_seen, status)
                VALUES (?, ?, ?, 'online')
            """, (w, lane, int(time.time())))
        
        # Query for best candidate
        row = conn.execute("""
            SELECT worker_id FROM worker_health 
            WHERE lane = ? AND status = 'online' AND active_tasks < ?
            ORDER BY active_tasks ASC, last_seen DESC
            LIMIT 1
        """, (lane, MAX_TASKS_PER_WORKER)).fetchone()
        
        if row:
            return row['worker_id']
        
        # All workers at capacity - log warning
        print(f"⚠️ [Auto-Router] All {lane} workers at capacity ({MAX_TASKS_PER_WORKER} tasks). Waiting...")
        return None
        
    except sqlite3.Error as e:
        print(f"⚠️ [Auto-Router] DB Error: {e}")
        return None


def route_pending_tasks(conn: sqlite3.Connection) -> int:
    """
    V2.1 Auto-Router: Assign workers to tasks with worker_id='auto'.
    Scans pending tasks and assigns using get_best_worker_for_lane().
    """
    routed = 0
    try:
        # Find tasks needing routing
        pending = conn.execute("""
            SELECT id, lane FROM tasks 
            WHERE worker_id = 'auto' AND status = 'pending'
            LIMIT 20
        """).fetchall()
        
        for task in pending:
            task_id = task['id']
            lane = task['lane']
            
            # V4.0: Compile task context (inject skill pack) BEFORE routing
            full_task = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
            if full_task:
                expand_task_context(conn, dict(full_task))
            
            worker = get_best_worker_for_lane(conn, lane)
            if worker:
                print(f"🔀 [Auto-Router] Assigning Task #{task_id} ({lane}) -> {worker}")
                
                # Update task assignment
                conn.execute("""
                    UPDATE tasks SET worker_id = ?, updated_at = ? WHERE id = ?
                """, (worker, int(time.time()), task_id))
                
                # Increment worker's active tasks
                conn.execute("""
                    UPDATE worker_health SET active_tasks = active_tasks + 1 WHERE worker_id = ?
                """, (worker,))
                
                log_status(conn, task_id, "auto_routed", worker, f"Auto-assigned from 'auto'")
                routed += 1
        
        if routed > 0:
            conn.commit()
            
    except sqlite3.Error as e:
        print(f"⚠️ [Auto-Router] DB Error: {e}")
        traceback.print_exc()
    
    return routed


# --- V2.1: Deduplication Guard (V3.2: Priority Inheritance) ---
def spawn_guardian(conn: sqlite3.Connection, worker_id: str, lane: str, goal: str, 
                   context_files: str, dependencies: List[int], 
                   priority: str = 'normal') -> Optional[int]:
    """
    V3.2 Guardian Spawner with Priority Inheritance.
    - Prevents duplicate QA/Docs tasks for the same goal
    - Inherits parent task priority (prevents priority inversion)
    
    Returns: task_id if created, None if duplicate skipped
    """
    try:
        # Check if guardian already exists (deduplication)
        existing = conn.execute("""
            SELECT id FROM tasks WHERE goal = ? AND lane = ?
        """, (goal, lane)).fetchone()
        
        if existing:
            print(f"🛑 [Deduplication] Guardian task '{goal}' ({lane}) already exists (#{existing['id']}). Skipping.")
            return None
        
        # Insert new guardian task with inherited priority
        cursor = conn.execute("""
            INSERT INTO tasks (worker_id, lane, goal, context_files, dependencies, priority, status)
            VALUES (?, ?, ?, ?, ?, ?, 'pending')
        """, (worker_id, lane, goal, context_files, json.dumps(dependencies), priority))
        
        task_id = cursor.lastrowid
        print(f"🚀 [Guardian] Spawned {lane} task #{task_id}: {goal} (priority: {priority})")
        log_status(conn, task_id, "spawned", worker_id, f"Guardian for deps: {dependencies}, priority: {priority}")
        
        return task_id
        
    except sqlite3.IntegrityError:
        # Unique constraint violation (race condition)
        print(f"🛑 [Deduplication] Guardian task '{goal}' ({lane}) blocked by unique constraint.")
        return None
    except sqlite3.Error as e:
        print(f"⚠️ [Guardian] DB Error: {e}")
        return None


# --- V3.2: Saturation Guard (V3.3: With Metrics) ---
def check_saturation(conn: sqlite3.Connection, lane: str) -> bool:
    """
    V3.2 Saturation Guard: Detect when a lane's worker pool is full.
    V3.3: Records saturation_events metric.
    Returns True if saturated (all workers at capacity).
    """
    try:
        stats = conn.execute("""
            SELECT 
                COALESCE(SUM(active_tasks), 0) as total_load,
                COALESCE(SUM(capacity_limit), 0) as total_capacity
            FROM worker_health 
            WHERE lane = ? AND status = 'online'
        """, (lane,)).fetchone()
        
        if stats and stats['total_capacity'] > 0:
            utilization = stats['total_load'] / stats['total_capacity']
            if utilization >= 0.9:  # 90% or more
                print(f"⚠️ [Saturation] {lane} pool at {int(utilization * 100)}% ({stats['total_load']}/{stats['total_capacity']})")
                metrics["saturation_events"] += 1
                return True
        return False
        
    except sqlite3.Error as e:
        print(f"⚠️ [Saturation] DB Error: {e}")
        return False


# --- V3.3: Task History Archival ---
def archive_old_history(conn: sqlite3.Connection, days: int = None) -> int:
    """
    V3.3: Move old task_history records to archive table.
    Prevents history table bloat.
    Returns count of archived records.
    """
    if days is None:
        days = HISTORY_ARCHIVE_DAYS
        
    try:
        cutoff = int(time.time()) - (days * 86400)
        
        # Count records to archive
        count = conn.execute(
            "SELECT COUNT(*) as c FROM task_history WHERE timestamp < ?", (cutoff,)
        ).fetchone()['c']
        
        if count == 0:
            return 0
        
        # Move to archive
        conn.execute("""
            INSERT INTO task_history_archive 
            SELECT * FROM task_history WHERE timestamp < ?
        """, (cutoff,))
        
        conn.execute("DELETE FROM task_history WHERE timestamp < ?", (cutoff,))
        conn.commit()
        
        print(f"🧹 [Archive] Moved {count} history records older than {days} days")
        return count
        
    except sqlite3.Error as e:
        print(f"⚠️ [Archive] DB Error: {e}")
        return 0


# --- V3.4: DLQ Escalation ---
DLQ_ESCALATION_HOURS = int(os.getenv("DLQ_ESCALATION_HOURS", "24"))

def escalate_dead_letters(conn: sqlite3.Connection) -> int:
    """
    V3.4: Automated DLQ Escalation.
    If a task rots in DLQ for > 24 hours, escalate with higher urgency.
    Prevents ignored dead letters from being forgotten.
    
    Returns: count of escalated tasks
    """
    try:
        now = int(time.time())
        threshold = now - (DLQ_ESCALATION_HOURS * 3600)
        
        # Find ignored dead letters (not yet escalated)
        ignored = conn.execute("""
            SELECT id, goal, lane, last_error_type FROM tasks 
            WHERE status = 'dead_letter' 
            AND updated_at < ? 
            AND (metadata IS NULL OR metadata NOT LIKE '%"escalated"%')
        """, (threshold,)).fetchall()
        
        escalated = 0
        for task in ignored:
            msg = f"🔥 [ESCALATION] Task #{task['id']} ({task['lane']}) dead for {DLQ_ESCALATION_HOURS}h! Goal: {task['goal'][:50]}"
            print(msg)
            notify_human(task['id'], msg, "critical")
            
            # Mark as escalated to prevent spam
            conn.execute("""
                UPDATE tasks 
                SET metadata = CASE 
                    WHEN metadata IS NULL THEN '{"escalated": true}'
                    ELSE json_patch(metadata, '{"escalated": true}')
                END,
                updated_at = ?
                WHERE id = ?
            """, (now, task['id']))
            
            escalated += 1
        
        if escalated > 0:
            conn.commit()
            print(f"🔥 [DLQ] Escalated {escalated} dead letter tasks (>{DLQ_ESCALATION_HOURS}h)")
        
        return escalated
        
    except sqlite3.Error as e:
        print(f"⚠️ [DLQ Escalation] DB Error: {e}")
        return 0


# --- V4.0: Prompt Compiler ---
# V4.1: Enhanced Guardrail Patterns
INJECTION_PATTERNS = [
    # Prompt injection
    "ignore previous instructions",
    "disregard all prior",
    "forget everything",
    "system prompt",
    "you are now",
    "new instructions:",
]

# V4.1: Sensitive Data Patterns (credentials, secrets)
SENSITIVE_DATA_PATTERNS = [
    (r"api[_-]?key\s*[=:]\s*['\"][a-zA-Z0-9]{16,}['\"]", "[API_KEY_REDACTED]"),
    (r"password\s*[=:]\s*['\"][^'\"]+['\"]", "[PASSWORD_REDACTED]"),
    (r"secret\s*[=:]\s*['\"][^'\"]+['\"]", "[SECRET_REDACTED]"),
    (r"token\s*[=:]\s*['\"][a-zA-Z0-9_\-\.]+['\"]", "[TOKEN_REDACTED]"),
    (r"sk-[a-zA-Z0-9]{32,}", "[OPENAI_KEY_REDACTED]"),
    (r"ghp_[a-zA-Z0-9]{36}", "[GITHUB_TOKEN_REDACTED]"),
    (r"xox[baprs]-[a-zA-Z0-9\-]+", "[SLACK_TOKEN_REDACTED]"),
]

# V4.1: Code Injection Patterns (SQL, XSS)
CODE_INJECTION_PATTERNS = [
    (r";\s*DROP\s+TABLE", "[SQL_INJECTION_BLOCKED]"),
    (r";\s*DELETE\s+FROM", "[SQL_INJECTION_BLOCKED]"),
    (r"<script[^>]*>", "[XSS_BLOCKED]"),
    (r"javascript:", "[XSS_BLOCKED]"),
    (r"on\w+\s*=\s*['\"]", "[XSS_BLOCKED]"),
]

import re  # For regex patterns


def sanitize_user_content(content: str) -> str:
    """
    V4.1 Guardrail: Sanitize user content to prevent:
    1. Prompt injection attacks
    2. Sensitive data leaks (API keys, passwords)
    3. Code injection (SQL, XSS)
    """
    # 1. Prompt injection (case-insensitive string match)
    lower_content = content.lower()
    for pattern in INJECTION_PATTERNS:
        if pattern in lower_content:
            print(f"⚠️ [Guardrail] Prompt injection blocked: '{pattern[:20]}...'")
            content = re.sub(re.escape(pattern), "[FILTERED]", content, flags=re.IGNORECASE)
    
    # 2. Sensitive data redaction (regex)
    for pattern, replacement in SENSITIVE_DATA_PATTERNS:
        if re.search(pattern, content, re.IGNORECASE):
            print(f"⚠️ [Guardrail] Sensitive data redacted: {replacement}")
            content = re.sub(pattern, replacement, content, flags=re.IGNORECASE)
    
    # 3. Code injection blocking (regex)
    for pattern, replacement in CODE_INJECTION_PATTERNS:
        if re.search(pattern, content, re.IGNORECASE):
            print(f"⚠️ [Guardrail] Code injection blocked: {replacement}")
            content = re.sub(pattern, replacement, content, flags=re.IGNORECASE)
    
    return content


def expand_task_context(conn: sqlite3.Connection, task: Dict) -> bool:
    """
    V4.0 Prompt Compiler: Inject lane skill pack into task context.
    
    Prompt Ordering (best practice):
    1. CONTEXT/EXAMPLES (skill pack)
    2. ROLE (directive from skill pack)
    3. USER REQUEST (sanitized goal)
    4. CONSTRAINTS (from skill pack)
    
    Returns: True if expanded, False if no skill pack found
    """
    lane = task.get('lane', '')
    task_id = task.get('id')
    
    # Determine skill file path
    skill_file = os.path.join(SKILLS_DIR, f"{lane}.md")
    if not os.path.exists(skill_file):
        # Try fallback
        skill_file = os.path.join(SKILLS_DIR, "_default.md")
        if not os.path.exists(skill_file):
            print(f"⚠️ [Compiler] No skill pack for lane '{lane}', proceeding without")
            return False
    
    try:
        # Read skill pack
        with open(skill_file, 'r', encoding='utf-8') as f:
            skills = f.read()
        
        # Truncate if too large
        if len(skills) > MAX_SKILL_CHARS:
            skills = skills[:MAX_SKILL_CHARS] + "\n...[truncated]..."
            print(f"⚠️ [Compiler] Skill pack truncated to {MAX_SKILL_CHARS} chars")
        
        # Sanitize user goal (guardrail)
        current_goal = sanitize_user_content(task.get('goal', ''))
        
        # Proper Prompt Ordering:
        # 1. SKILL PACK (context, examples, directive, constraints)
        # 2. USER TASK (sanitized)
        compiled_goal = f"""--- {lane.upper()} SKILL PACK ({os.path.basename(skill_file)}) ---
{skills}

--- USER TASK ---
{current_goal}

--- REMINDER ---
Follow the MUST/AVOID rules above. Check EVIDENCE checklist before submitting."""
        
        # Update context_files
        ctx = json.loads(task.get('context_files') or '[]')
        if skill_file not in ctx:
            ctx.append(skill_file)
        
        # Update task
        conn.execute("""
            UPDATE tasks SET goal = ?, context_files = ?, updated_at = ?
            WHERE id = ?
        """, (compiled_goal, json.dumps(ctx), int(time.time()), task_id))
        conn.commit()
        
        print(f"📚 [Compiler] Injected skill pack for task #{task_id} (lane: {lane})")
        return True
        
    except Exception as e:
        print(f"⚠️ [Compiler] Error reading skill pack: {e}")
        return False


def append_lesson_learned(lesson: str, category: str = "General") -> bool:
    """
    V4.0: Auto-append to LESSONS_LEARNED.md on task rejection.
    Called by QA workers when they find systematic issues.
    """
    try:
        if not os.path.exists(LESSONS_FILE):
            print(f"⚠️ [Lessons] File not found: {LESSONS_FILE}")
            return False
        
        timestamp = time.strftime("%Y-%m-%d")
        entry = f"- **[{timestamp}] {category}:** {lesson}\n"
        
        with open(LESSONS_FILE, 'a', encoding='utf-8') as f:
            f.write(entry)
        
        print(f"📝 [Lessons] Added: {lesson[:50]}...")
        return True
        
    except Exception as e:
        print(f"⚠️ [Lessons] Error appending: {e}")
        return False

# --- V3.3: Auto-Scaler Hook ---
_auto_scale_counter = 0  # Unique ID counter

def provision_virtual_worker(conn: sqlite3.Connection, lane: str) -> Optional[str]:
    """
    V3.3: Auto-scale by provisioning a virtual worker.
    This is a hook for K8s/Lambda/Cursor session spin-up.
    Respects MAX_AUTO_SCALE_WORKERS limit.
    
    Returns: new worker_id or None if limit reached
    """
    global _auto_scale_counter
    try:
        # Check current auto-scaled worker count
        count = conn.execute("""
            SELECT COUNT(*) as c FROM worker_health 
            WHERE worker_id LIKE ? AND lane = ?
        """, (f"@{lane}-auto-%", lane)).fetchone()['c']
        
        if count >= MAX_AUTO_SCALE_WORKERS:
            print(f"⚠️ [Scaler] {lane} at auto-scale limit ({count}/{MAX_AUTO_SCALE_WORKERS})")
            return None
        
        # Provision new worker with unique ID
        _auto_scale_counter += 1
        new_id = f"@{lane}-auto-{int(time.time())}-{_auto_scale_counter}"
        print(f"⚡ [Scaler] Provisioning virtual worker: {new_id}")
        
        conn.execute("""
            INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, last_seen)
            VALUES (?, ?, 'standard', 3, 'online', ?)
        """, (new_id, lane, int(time.time())))
        
        invalidate_worker_cache(lane)
        metrics["auto_scale_events"] += 1
        conn.commit()
        
        return new_id
        
    except sqlite3.Error as e:
        print(f"⚠️ [Scaler] DB Error: {e}")
        return None


# --- V3.2: Smart Backoff ---
def handle_smart_retry(conn: sqlite3.Connection, task_id: int, error_type: str = "crash") -> None:
    """
    V3.2 Smart Backoff: Different retry strategies based on error type.
    - network: Fixed 2s retry (transient, likely to recover)
    - crash: Exponential backoff (2s, 4s, 8s, 16s...)
    - permanent: Move to dead_letter immediately
    """
    try:
        task = conn.execute("SELECT attempt_count FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if not task:
            return
            
        attempts = task['attempt_count'] + 1
        now = int(time.time())
        
        # Permanent error or max retries → Dead Letter Queue
        if error_type == "permanent" or attempts >= MAX_RETRIES:
            print(f"💀 [DLQ] Task #{task_id} moved to DEAD LETTER QUEUE (attempts: {attempts}, error: {error_type})")
            conn.execute("UPDATE tasks SET status = 'dead_letter', worker_id = NULL, last_error_type = ?, updated_at = ? WHERE id = ?", (error_type, now, task_id))  # SAFETY-ALLOW: status-write
            log_status(conn, task_id, "dead_letter", None, f"Max retries exceeded ({error_type})")
            notify_human(task_id, f"Task moved to Dead Letter Queue after {attempts} attempts", "critical")
            return
        
        # Calculate backoff based on error type
        if error_type == "network":
            backoff_seconds = 2  # Fixed 2s for network issues
        else:
            backoff_seconds = 2 ** attempts  # Exponential: 2, 4, 8, 16...
        
        backoff_until = now + backoff_seconds
        
        print(f"⏳ [Backoff] Task #{task_id} ({error_type}): retry in {backoff_seconds}s")
        conn.execute("UPDATE tasks SET status = 'pending', worker_id = NULL, attempt_count = ?, backoff_until = ?, last_error_type = ?, updated_at = ? WHERE id = ?", (attempts, backoff_until, error_type, now, task_id))  # SAFETY-ALLOW: status-write
        
        log_status(conn, task_id, "retry_scheduled", None, f"{error_type} backoff: {backoff_seconds}s")
        
    except sqlite3.Error as e:
        print(f"⚠️ [Backoff] DB Error: {e}")


# --- V3.2: Tier-Based Routing ---
def get_best_worker_with_tier(conn: sqlite3.Connection, lane: str, 
                               effort_rating: int = 1, priority: str = 'normal') -> Optional[str]:
    """
    V3.2 Intelligent Router: Match task effort to worker tier.
    - effort >= 4: Prefer senior workers
    - critical priority: Override tier preference, find any slot
    
    Returns: worker_id or None if no available worker
    """
    try:
        # Bootstrap default workers if missing
        defaults = {
            'backend': [('@backend-senior', 'senior'), ('@backend-1', 'standard'), ('@backend-2', 'standard')],
            'frontend': [('@frontend-senior', 'senior'), ('@frontend-1', 'standard'), ('@frontend-2', 'standard')],
            'qa': [('@qa-1', 'standard')],
            'docs': [('@librarian', 'standard')]
        }
        for w, tier in defaults.get(lane, []):
            cap = 5 if tier == 'senior' else 3
            conn.execute("""
                INSERT OR IGNORE INTO worker_health (worker_id, lane, tier, capacity_limit, last_seen, status)
                VALUES (?, ?, ?, ?, ?, 'online')
            """, (w, lane, tier, cap, int(time.time())))
        
        # Check saturation first
        check_saturation(conn, lane)
        
        # Determine preferred tier based on effort
        prefer_senior = effort_rating >= 4
        
        if prefer_senior:
            # Try senior first
            row = conn.execute("""
                SELECT worker_id FROM worker_health 
                WHERE lane = ? AND status = 'online' AND tier = 'senior' AND active_tasks < capacity_limit
                ORDER BY active_tasks ASC, last_seen DESC
                LIMIT 1
            """, (lane,)).fetchone()
            
            if row:
                return row['worker_id']
            
            # Fallback to standard if no senior available (or critical priority overrides)
            print(f"⚠️ [Router] No senior available for effort={effort_rating}, falling back to standard")
        
        # Query for any available worker
        row = conn.execute("""
            SELECT worker_id FROM worker_health 
            WHERE lane = ? AND status = 'online' AND active_tasks < capacity_limit
            ORDER BY active_tasks ASC, priority_score DESC, last_seen DESC
            LIMIT 1
        """, (lane,)).fetchone()
        
        if row:
            return row['worker_id']
        
        print(f"⚠️ [Router] No available workers for {lane}. All at capacity.")
        return None
        
    except sqlite3.Error as e:
        print(f"⚠️ [Router] DB Error: {e}")
        return None


# --- Core Logic ---
def sweep_stale_leases(conn: sqlite3.Connection) -> int:
    """
    Recover zombie tasks and enforce Circuit Breaker on timeouts.
    Returns count recovered.
    """
    now = int(time.time())
    recovered = 0
    
    try:
        # 1. Identify Stale Tasks
        stale_tasks = conn.execute(f"""
            SELECT id, attempt_count FROM tasks 
            WHERE status='in_progress' AND lease_expires_at < ? AND lease_expires_at > 0
            LIMIT {BATCH_SIZE}
        """, (now,)).fetchall()

        for task in stale_tasks:
            task_id = task['id']
            attempts = task['attempt_count'] + 1
            
            if attempts >= MAX_RETRIES:
                # Circuit Breaker: Fail
                conn.execute(
                    "UPDATE tasks SET status='failed', worker_id=NULL, lease_id=NULL, updated_at=? WHERE id=?", # SAFETY-ALLOW: status-write
                    (now, task_id)
                )
                notify_human(task_id, f"Failed after {attempts} attempts (Timeout).", "critical")
                print(f"💀 [Sweeper] Task #{task_id} FAILED (Max Retries).")
                metrics["tasks_failed"] += 1
            else:
                # Retry
                conn.execute(
                    "UPDATE tasks SET status='pending', worker_id=NULL, lease_id=NULL, attempt_count=?, updated_at=? WHERE id=?", # SAFETY-ALLOW: status-write
                    (attempts, now, task_id)
                )
                print(f"♻️ [Sweeper] Task #{task_id} recovered (Attempt {attempts}/{MAX_RETRIES}).")
                recovered += 1
        
        if stale_tasks:
            conn.commit()
            metrics["last_sweep_recovered"] = recovered

    except sqlite3.Error as e:
        print(f"⚠️ [Sweeper] DB Error: {e}")
        traceback.print_exc()
    
    return recovered


def sweep_blocked_tasks(conn: sqlite3.Connection) -> int:
    """
    Manage blocked tasks (V1.2).
    If blocked > 24h -> Reassign or Escalate.
    Returns count of tasks processed.
    """
    now = int(time.time())
    threshold = now - BLOCKED_TIMEOUT_SEC
    processed = 0
    
    try:
        # Find tasks blocked longer than 24h
        long_blocked = conn.execute(f"""
            SELECT id, attempt_count, metadata FROM tasks 
            WHERE status='blocked' AND updated_at < ?
            LIMIT {BATCH_SIZE}
        """, (threshold,)).fetchall()

        for task in long_blocked:
            task_id = task['id']
            attempts = task['attempt_count'] + 1
            metadata = json.loads(task['metadata'] or '{}')
            blocker_msg = metadata.get('blocker_msg', 'Unknown reason')
            
            print(f"⚠️ [BlockWatch] Task #{task_id} blocked > 24h.")
            
            if attempts >= MAX_RETRIES:
                # We tried reassigning, still blocked. Escalate to human.
                notify_human(
                    task_id, 
                    f"STILL BLOCKED after {attempts} reassignments. Human intervention mandatory. Reason: {blocker_msg}",
                    "critical"
                )
                # Touch updated_at so we don't spam every 5 seconds (wait another 24h or manual fix)
                conn.execute("UPDATE tasks SET updated_at=? WHERE id=?", (now, task_id))
                metrics["tasks_failed"] += 1
            else:
                # Reassign to fresh worker (V1.2 Refinement 4)
                conn.execute("""
                    UPDATE tasks 
                    SET status='pending', worker_id=NULL, lease_id=NULL, attempt_count=?, updated_at=?
                    WHERE id=?
                """, (attempts, now, task_id))  # SAFETY-ALLOW: status-write
                notify_human(
                    task_id,
                    f"Blocked too long ({BLOCKED_TIMEOUT_SEC//3600}h). Reassigning to new worker (Attempt {attempts}/{MAX_RETRIES}).",
                    "warning"
                )
                print(f"🔄 [BlockWatch] Task #{task_id} reassigned (fresh eyes strategy).")
                processed += 1
        
        if long_blocked:
            conn.commit()

    except sqlite3.Error as e:
        print(f"⚠️ [BlockWatch] DB Error: {e}")
        traceback.print_exc()
    
    return processed


def handle_review_queue(conn: sqlite3.Connection):
    """Process tasks awaiting review."""
    try:
        reviews = conn.execute(
            f"SELECT * FROM tasks WHERE status='review_needed' LIMIT {BATCH_SIZE}"
        ).fetchall()
        
        for task in reviews:
            if not running:
                break
            process_submission(conn, dict(task))
            
    except sqlite3.Error as e:
        print(f"⚠️ [Reviewer] DB Fetch Error: {e}")
        traceback.print_exc()


def process_submission(conn: sqlite3.Connection, task: Dict[str, Any]):
    """Decides fate based on Metadata (Rejection vs Approval) and Risk."""
    task_id = task['id']
    
    try:
        metadata = json.loads(task.get('metadata') or '{}')
        
        # FIX #1: Rejection Handler (QA Rejects Dev)
        if metadata.get('status') == 'REJECT':
            handle_rejection(conn, task, metadata)
            return

        # Normal Approval Flow
        risk_level = metadata.get('risk', 'low')

        if risk_level == 'low':
            approve_task(conn, task)
        else:
            # High-risk: notify human if not already notified
            if not metadata.get('notified', False):
                notify_human(task_id, "High Risk Task submitted - requires review.", "warning")
                metadata['notified'] = True
                conn.execute(
                    "UPDATE tasks SET metadata = ? WHERE id = ?",
                    (json.dumps(metadata), task_id)
                )
                conn.commit()
                
    except Exception as e:
        print(f"🔥 [Reviewer] Error processing Task #{task_id}: {e}")
        traceback.print_exc()
        metrics["tasks_failed"] += 1


def handle_rejection(conn: sqlite3.Connection, qa_task: Dict[str, Any], metadata: Dict[str, Any]):
    """
    QA rejected the code. Logic:
    1. Close QA Task.
    2. Reset Original Task (Dev) if retries allow.
    3. Fail Original Task if retries exceeded.
    """
    qa_task_id = qa_task['id']
    reason = metadata.get('reason', 'QA Rejection')
    critique = metadata.get('critique', 'Check logs.')
    
    # Identify Original Task
    deps = json.loads(qa_task.get('dependencies') or '[]')
    if not deps:
        print(f"⚠️ [Rejection] QA Task #{qa_task_id} rejected but has no dependencies!")
        return

    original_task_id = deps[0]
    
    # Check Retries on Original Task
    target_task = conn.execute("SELECT attempt_count FROM tasks WHERE id=?", (original_task_id,)).fetchone()
    if not target_task:
        return
    
    attempts = target_task['attempt_count'] + 1
    now = int(time.time())

    try:
        conn.execute("BEGIN")
        
        # 1. Complete QA Task (The QA did their job correctly by rejecting)
        conn.execute("UPDATE tasks SET status='completed', updated_at=? WHERE id=?", (now, qa_task_id)) # SAFETY-ALLOW: status-write
        
        # 2. Handle Original Task
        if attempts >= MAX_RETRIES:
            # FIX #3: Failure Circuit Breaker
            conn.execute("UPDATE tasks SET status='failed', updated_at=? WHERE id=?", (now, original_task_id)) # SAFETY-ALLOW: status-write
            notify_human(original_task_id, f"Failed after {attempts} attempts. Last Rejection: {reason}", "critical")
            print(f"💀 [Controller] Task #{original_task_id} FAILED (QA Rejected {MAX_RETRIES} times).")
            metrics["tasks_failed"] += 1
        else:
            # Reset for Retry
            conn.execute("""
                UPDATE tasks 
                SET status='pending', worker_id=NULL, lease_id=NULL, attempt_count=?, updated_at=?
                WHERE id=?
            """, (attempts, now, original_task_id)) # SAFETY-ALLOW: status-write
            
            # Log Feedback
            conn.execute("""
                INSERT INTO task_messages (task_id, role, msg_type, content, created_at) 
                VALUES (?, 'system', 'feedback', ?, ?)
            """, (original_task_id, f"⚠️ QA Rejected: {reason}\nCritique: {critique}", now))
            
            print(f"♻️ [Controller] Task #{original_task_id} Reopened for Fix (Attempt {attempts}/{MAX_RETRIES}).")
        
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f"💥 [Rejection] Failed to reset Task #{original_task_id}: {e}")
        traceback.print_exc()


def approve_task(conn: sqlite3.Connection, task: Dict[str, Any]):
    """Complete task and dispatch guardian workers with proper chaining (QA -> Docs)."""
    task_id = task['id']
    lane = task.get('lane', '')
    next_step = predict_next_step(task)
    now = int(time.time())
    
    # Calculate completion time
    created_at = task.get('created_at', now)
    completion_time_ms = (now - created_at) * 1000

    try:
        conn.execute("BEGIN")
        
        # Mark task completed
        conn.execute(
            "UPDATE tasks SET status='completed', updated_at=? WHERE id=?", # SAFETY-ALLOW: status-write
            (now, task_id)
        )

        
        # Log next step suggestion
        conn.execute(
            "INSERT INTO task_messages (task_id, role, msg_type, content, created_at) VALUES (?, 'system', 'next_step', ?, ?)",
            (task_id, f"✅ Task Completed. Suggestion: {next_step}", now)
        )
        
        # FIX #2: Guardian Chaining (Dev -> QA -> Docs)
        if lane in ['@backend', '@frontend', '@database', '@devops']:
            context_files = task.get('context_files', '')
            
            # 1. Spawn QA (Dependent on Dev)
            cursor = conn.execute(
                "INSERT INTO tasks (lane, status, goal, context_files, dependencies) VALUES (?, ?, ?, ?, ?)",
                ('@qa', 'pending', f"Verify Task #{task_id}", context_files, json.dumps([task_id]))
            )
            qa_task_id = cursor.lastrowid
            
            # 2. Spawn Docs (Dependent on QA TASK ID)
            # This ensures Docs waits for QA to pass.
            conn.execute(
                "INSERT INTO tasks (lane, status, goal, context_files, dependencies) VALUES (?, ?, ?, ?, ?)",
                ('@docs', 'pending', f"Document Task #{task_id}", context_files, json.dumps([qa_task_id]))
            )
            
            print(f"🚀 [Orchestrator] Task #{task_id} approved. Chain: QA #{qa_task_id} -> Docs. Next: {next_step}")
        else:
            print(f"✅ [Orchestrator] {lane} Task #{task_id} approved. Next: {next_step}")
        
        conn.commit()
        
        # Update metrics
        metrics["tasks_completed"] += 1
        metrics["avg_completion_time_ms"] = (
            (metrics["avg_completion_time_ms"] + completion_time_ms) / 2
        )

    except sqlite3.Error as e:
        conn.rollback()
        print(f"💥 [Orchestrator] Transaction Failed for Task #{task_id}: {e}")
        traceback.print_exc()
        metrics["tasks_failed"] += 1


def check_db_integrity(conn: sqlite3.Connection):
    """Periodic check for orphaned tasks and state consistency."""
    try:
        # Find orphaned in_progress tasks (no valid lease, not expired)
        orphaned = conn.execute("""
            SELECT COUNT(*) FROM tasks 
            WHERE status='in_progress' AND (lease_id IS NULL OR lease_id = '')
        """).fetchone()[0]
        
        if orphaned > 0:
            notify_human(0, f"DB Integrity: {orphaned} orphaned in_progress tasks detected", "warning")
            
        # Find tasks stuck in blocked for too long (> 24 hours)
        day_ago = int(time.time()) - 86400
        stuck = conn.execute(
            "SELECT COUNT(*) FROM tasks WHERE status='blocked' AND updated_at < ?",
            (day_ago,)
        ).fetchone()[0]
        
        if stuck > 0:
            notify_human(0, f"DB Integrity: {stuck} tasks stuck in blocked state > 24h", "warning")
            
    except sqlite3.Error as e:
        print(f"⚠️ [Integrity] Check failed: {e}")


def update_queue_metrics(conn: sqlite3.Connection):
    """Update queue length metrics (every METRICS_INTERVAL seconds)."""
    now = int(time.time())
    if now - metrics["last_metrics_update"] < METRICS_INTERVAL:
        return
    
    try:
        for status in ["pending", "in_progress", "review_needed", "blocked"]:
            count = conn.execute(
                "SELECT COUNT(*) FROM tasks WHERE status=?", (status,)
            ).fetchone()[0]
            metrics["queue_lengths"][status] = count
        
        metrics["last_metrics_update"] = now
        
    except sqlite3.Error as e:
        print(f"⚠️ [Metrics] Update failed: {e}")


def cleanup_on_shutdown(conn: sqlite3.Connection):
    """Graceful shutdown: pause in-progress tasks."""
    try:
        now = int(time.time())
        cursor = conn.execute("""
            UPDATE tasks 
            SET status='pending', worker_id=NULL, lease_id=NULL, updated_at=?
            WHERE status='in_progress'
        """, (now,))  # SAFETY-ALLOW: status-write
        conn.commit()
        
        if cursor.rowcount > 0:
            print(f"🔄 [Shutdown] Requeued {cursor.rowcount} in-progress tasks.")
            
    except sqlite3.Error as e:
        print(f"⚠️ [Shutdown] Cleanup failed: {e}")


def write_health_status():
    """Write health status file for external monitoring."""
    try:
        with open("vibe_controller.health", "w") as f:
            status = {
                "status": "healthy" if circuit_breaker_failures < CIRCUIT_BREAKER_THRESHOLD else "degraded",
                "timestamp": datetime.now().isoformat(),
                "metrics": metrics
            }
            json.dump(status, f, indent=2)
    except Exception:
        pass


# --- Main Loop ---
def run_controller():
    """Main controller loop (V3.4 - Final Master)."""
    print(f"🧠 [System] Vibe Controller V3.4 Active (Final: Complete Orchestration)")
    print(f"   Architecture: HYBRID (Direct + Routing + Tiers + Cache + Specialists)")
    print(f"   DB: {DB_PATH} | Poll: {POLL_INTERVAL}s | Batch: {BATCH_SIZE}")
    print(f"   Specialists: @security-1, @ux-designer, @data-analyst")
    print(f"   DLQ Escalation: {DLQ_ESCALATION_HOURS}h | Auto-Scaler: MAX {MAX_AUTO_SCALE_WORKERS}")
    print(f"   ChatOps: Ready | Dashboard: Ready")
    print(f"   Press Ctrl+C to stop gracefully.\n")
    
    conn = get_db()
    if not conn:
        print("💥 [System] Failed to connect to database. Exiting.")
        sys.exit(1)
    
    loop_count = 0
    integrity_check_interval = 100  # Check every 100 loops (~8 minutes)
    archive_interval = 100  # Archive history every 100 loops
    
    try:
        while running:
            start_time = time.time()
            
            # V2.1: Auto-Router (assign workers to 'auto' tasks)
            route_pending_tasks(conn)
            
            # V2.0: Assignment Watchdog (detect ignored tasks, reassign)
            enforce_assignments(conn)
            
            # V2.0: Worker Health (detect idle workers, mark offline)
            handle_worker_idle(conn)
            
            # V1.x: Core orchestration
            sweep_stale_leases(conn)
            sweep_blocked_tasks(conn)
            handle_review_queue(conn)
            update_queue_metrics(conn)
            
            # Periodic integrity check
            loop_count += 1
            if loop_count % integrity_check_interval == 0:
                check_db_integrity(conn)
            
            # V3.3: Periodic history archival
            if loop_count % archive_interval == 0:
                archive_old_history(conn)
                # V3.4: Check for dead letters needing escalation
                escalate_dead_letters(conn)
            
            # Write health status
            write_health_status()
            
            # Sleep for remaining poll interval
            elapsed = time.time() - start_time
            time.sleep(max(0, POLL_INTERVAL - elapsed))
            
    except Exception as e:
        print(f"🔥 [System] Critical Loop Error: {e}")
        traceback.print_exc()
        
    finally:
        cleanup_on_shutdown(conn)
        conn.close()
        write_health_status()
        print("👋 [System] Controller stopped safely.")


if __name__ == "__main__":
    run_controller()
