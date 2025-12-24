"""
Vibe Controller V1.1 Gold Master
================================
Autonomous orchestration engine for the Vibe Coding System.

Features:
- Graceful shutdown with task state cleanup
- Circuit breaker for timeouts and QA rejections (3 retries max)
- Rejection handling: QA can reject dev work, triggers retry with feedback
- Guardian chaining: QA -> Docs (Docs waits for QA to pass)
- Prometheus-ready health metrics
- Periodic DB integrity checks
"""

import time
import json
import sqlite3
import signal
import sys
import os
import traceback
from typing import Dict, Any, Optional
from datetime import datetime

# --- Configuration ---
DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")
LEASE_TIMEOUT_SEC = int(os.getenv("LEASE_TIMEOUT_SEC", "600"))
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "5"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "50"))
MAX_RETRIES = 3
METRICS_INTERVAL = 60  # Collect metrics every minute (not every poll)

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
    Console notification with hooks for future integrations.
    Priority levels: info, warning, critical
    """
    timestamp = time.strftime("%H:%M:%S")
    icons = {"info": "🔔", "warning": "⚠️", "critical": "🚨"}
    icon = icons.get(priority, "🔔")
    
    msg = f"{icon} [{timestamp}] Task #{task_id}: {reason}"
    print(msg)
    
    # Future hook: Slack, PagerDuty, Email
    # if SLACK_WEBHOOK_URL and priority == "critical":
    #     requests.post(SLACK_WEBHOOK_URL, json={"text": msg})
    
    # Persist critical alerts to DB for tracking
    if priority == "critical":
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
                    "UPDATE tasks SET status='failed', worker_id=NULL, lease_id=NULL, updated_at=? WHERE id=?",
                    (now, task_id)
                )
                notify_human(task_id, f"Failed after {attempts} attempts (Timeout).", "critical")
                print(f"💀 [Sweeper] Task #{task_id} FAILED (Max Retries).")
                metrics["tasks_failed"] += 1
            else:
                # Retry
                conn.execute(
                    "UPDATE tasks SET status='pending', worker_id=NULL, lease_id=NULL, attempt_count=?, updated_at=? WHERE id=?",
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
        conn.execute("UPDATE tasks SET status='completed', updated_at=? WHERE id=?", (now, qa_task_id))
        
        # 2. Handle Original Task
        if attempts >= MAX_RETRIES:
            # FIX #3: Failure Circuit Breaker
            conn.execute("UPDATE tasks SET status='failed', updated_at=? WHERE id=?", (now, original_task_id))
            notify_human(original_task_id, f"Failed after {attempts} attempts. Last Rejection: {reason}", "critical")
            print(f"💀 [Controller] Task #{original_task_id} FAILED (QA Rejected {MAX_RETRIES} times).")
            metrics["tasks_failed"] += 1
        else:
            # Reset for Retry
            conn.execute("""
                UPDATE tasks 
                SET status='pending', worker_id=NULL, lease_id=NULL, attempt_count=?, updated_at=?
                WHERE id=?
            """, (attempts, now, original_task_id))
            
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
            "UPDATE tasks SET status='completed', updated_at=? WHERE id=?",
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
        """, (now,))
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
    """Main controller loop."""
    print(f"🧠 [System] Vibe Controller V1.1 Active (Rejection Handling + Guardian Chaining)")
    print(f"   DB: {DB_PATH} | Poll: {POLL_INTERVAL}s | Batch: {BATCH_SIZE} | Max Retries: {MAX_RETRIES}")
    print(f"   Metrics collection: every {METRICS_INTERVAL}s")
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
            
            sweep_stale_leases(conn)
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
