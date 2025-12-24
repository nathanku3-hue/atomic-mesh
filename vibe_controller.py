"""
Vibe Controller V2.1 Platinum Master
====================================
Autonomous orchestration engine for the Vibe Coding System.

Architecture: HYBRID DELEGATION
- Architect can assign specific workers (@backend-1) OR use "auto" for load balancing
- Controller acts as Auto-Router for "auto" assignments
- Health-based routing prevents overloading workers

Features V2.1:
- Auto-Routing: worker_id="auto" → Controller assigns least-busy worker
- Deduplication Guard: Prevents duplicate guardian tasks (QA/Docs)
- Health-Based Routing: MAX_TASKS_PER_WORKER limit, route to free workers

Features V2.0:
- Direct delegation with assignment watchdog (5 min timeout)
- Dynamic load balancing with worker priority scores
- Worker health tracking (active_tasks, last_seen, status)
- Granular audit logging via task_history table
- Circuit breaker for timeouts and QA rejections (3 retries max)
- Rejection handling: QA can reject dev work, triggers retry with feedback
- Guardian chaining: QA -> Docs (Docs waits for QA to pass)
- Blocked task management: 24h timeout, smart reassignment, escalation
- Admin tool integration: Human approval workflow
- Prometheus-ready health metrics
- Periodic DB integrity checks

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
}


def handle_signal(signum, frame):
    """Graceful shutdown handler."""
    global running
    timestamp = time.strftime("%H:%M:%S")
    print(f"\n🛑 [{timestamp}] Shutdown signal received ({signum}). Cleaning up...")
    running = False


signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)


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


# --- V2.1: Deduplication Guard ---
def spawn_guardian(conn: sqlite3.Connection, worker_id: str, lane: str, goal: str, 
                   context_files: str, dependencies: List[int]) -> Optional[int]:
    """
    V2.1 Deduplication Guard: Spawn guardian task with idempotency check.
    Prevents duplicate QA/Docs tasks for the same goal.
    
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
        
        # Insert new guardian task
        cursor = conn.execute("""
            INSERT INTO tasks (worker_id, lane, goal, context_files, dependencies, status)
            VALUES (?, ?, ?, ?, ?, 'pending')
        """, (worker_id, lane, goal, context_files, json.dumps(dependencies)))
        
        task_id = cursor.lastrowid
        print(f"🚀 [Guardian] Spawned {lane} task #{task_id}: {goal}")
        log_status(conn, task_id, "spawned", worker_id, f"Guardian for deps: {dependencies}")
        
        return task_id
        
    except sqlite3.IntegrityError:
        # Unique constraint violation (race condition)
        print(f"🛑 [Deduplication] Guardian task '{goal}' ({lane}) blocked by unique constraint.")
        return None
    except sqlite3.Error as e:
        print(f"⚠️ [Guardian] DB Error: {e}")
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
    """Main controller loop (V2.1 - Hybrid Delegation)."""
    print(f"🧠 [System] Vibe Controller V2.1 Active (Platinum: Hybrid Delegation)")
    print(f"   Architecture: HYBRID (Direct + Auto-Routing)")
    print(f"   DB: {DB_PATH} | Poll: {POLL_INTERVAL}s | Batch: {BATCH_SIZE}")
    print(f"   Assignment Timeout: {ASSIGNMENT_TIMEOUT_SEC}s | Idle Timeout: {IDLE_TIMEOUT_SEC}s")
    print(f"   Max Tasks/Worker: {MAX_TASKS_PER_WORKER} | Max Retries: {MAX_RETRIES}")
    print(f"   Block Timeout: {BLOCKED_TIMEOUT_SEC}s")
    print(f"   Features: Auto-Router, Deduplication Guard, Health-Based Routing")
    print(f"   Press Ctrl+C to stop gracefully.\n")
    
    conn = get_db()
    if not conn:
        print("💥 [System] Failed to connect to database. Exiting.")
        sys.exit(1)
    
    loop_count = 0
    integrity_check_interval = 100  # Check every 100 loops (~8 minutes)
    
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
