"""
Vibe Admin Tool V3.2 Diamond Master
====================================
Human Control Panel for the Vibe Coding System.

Features:
- Audit Trails: Every admin action logged to task_messages
- Transactional Safety: Strict try/except/rollback patterns
- Role Gating: VIBE_ROLE environment check
- Commands: list, approve, retry, dlq

V3.2 DLQ Commands:
- dlq list: Show dead letter tasks
- dlq retry: Retry all (set priority=high)
- dlq purge: Delete all dead letter tasks
"""

import sqlite3
import sys
import json
import os
import time

DB_PATH = os.getenv("DB_PATH", "vibe_coding.db")
REQUIRED_ROLE = "admin"

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    # Enable WAL for concurrent access safety
    conn.execute("PRAGMA journal_mode = WAL;")
    return conn

# --- Security & Auditing ---

def check_permissions():
    """Simple RBAC via Environment Variable."""
    current_role = os.getenv("VIBE_ROLE", "user") # Default to 'user' for safety
    if current_role != REQUIRED_ROLE:
        print(f"⛔ PERMISSION DENIED. Required role: '{REQUIRED_ROLE}', Got: '{current_role}'")
        print("Tip: Run `export VIBE_ROLE=admin` to authenticate.")
        sys.exit(1)

def log_admin_action(conn, task_id, action, details):
    """Writes to the immutable audit log."""
    conn.execute("""
        INSERT INTO task_messages (task_id, role, msg_type, content, created_at)
        VALUES (?, 'admin', 'action', ?, ?)
    """, (task_id, f"ADMIN {action.upper()}: {details}", int(time.time())))

# --- Commands ---

def list_pending_approvals():
    conn = get_db()
    try:
        rows = conn.execute("SELECT id, goal, metadata FROM tasks WHERE status='review_needed'").fetchall()
        if not rows:
            print("✅ No tasks waiting for approval.")
            return

        print(f"\n📋 Found {len(rows)} tasks waiting for approval:")
        for r in rows:
            meta = json.loads(r['metadata'] or '{}')
            risk = meta.get('risk', 'unknown')
            print(f"  [#{r['id']}] {r['goal']}")
            print(f"      Risk: {risk} | Worker: {r.get('worker_id', '?')}")
    finally:
        conn.close()

def approve_task(task_id):
    check_permissions()
    conn = get_db()
    try:
        # Fetch current metadata to preserve other fields
        meta_row = conn.execute("SELECT metadata FROM tasks WHERE id=?", (task_id,)).fetchone()
        if not meta_row:
            print(f"❌ Task #{task_id} not found.")
            return

        conn.execute("BEGIN")
        
        meta = json.loads(meta_row['metadata'] or '{}')
        old_risk = meta.get('risk', 'unknown')
        
        # Override Risk
        meta['risk'] = 'low'
        meta['human_approved'] = True
        meta['approved_by'] = os.getenv("USER", "admin")
        
        # Update Task
        conn.execute("UPDATE tasks SET metadata=? WHERE id=?", (json.dumps(meta), task_id))
        
        # Audit Log
        log_admin_action(conn, task_id, "APPROVE", f"Risk overridden ({old_risk} -> low).")
        
        conn.commit()
        print(f"✅ Task #{task_id} approved. The Controller will process it on the next tick.")
        
    except Exception as e:
        conn.rollback()
        print(f"💥 Failed to approve task: {e}")
    finally:
        conn.close()

def retry_task(task_id):
    check_permissions()
    conn = get_db()
    try:
        conn.execute("BEGIN")
        
        # Reset Task State
        conn.execute("""
            UPDATE tasks 
            SET status='pending', attempt_count=0, worker_id=NULL, lease_id=NULL, updated_at=? 
            WHERE id=?
        """, (int(time.time()), task_id))  # SAFETY-ALLOW: status-write
        
        # Audit Log
        log_admin_action(conn, task_id, "RETRY", "Task manually reset to Pending state.")
        
        conn.commit()
        print(f"🔄 Task #{task_id} reset. A worker will pick it up shortly.")
        
    except Exception as e:
        conn.rollback()
        print(f"💥 Failed to retry task: {e}")
    finally:
        conn.close()

# --- V5.5: Blind Handoff (Blueprint Submission) ---

def submit_blueprint(content: str, domain: str = "general"):
    """
    V5.5 Blind Handoff: Ingests raw text directly to DB as Blueprint.
    The Architect bypasses processing; Librarian parses.
    """
    # Refinement #1: Validation (Warning, not blocking)
    if len(content) < 50:
        print(f" >> [WARNING] Blueprint content is very short ({len(content)} chars).")
        print(f"    Ensure this is a complete solution paste.")
    
    conn = get_db()
    try:
        conn.execute("BEGIN")
        
        cursor = conn.execute("""
            INSERT INTO tasks (goal, lane, status, domain, priority, created_at, updated_at)
            VALUES (?, 'blueprint', 'pending_parsing', ?, 'high', ?, ?)
        """, (
            f"[BLUEPRINT] {content[:100]}...",
            domain,
            int(time.time()),
            int(time.time())
        ))
        
        task_id = cursor.lastrowid
        
        # Store full content in metadata
        conn.execute("""
            UPDATE tasks SET metadata = ? WHERE id = ?
        """, (json.dumps({"raw_content": content, "type": "blueprint"}), task_id))
        
        log_admin_action(conn, task_id, "BLUEPRINT_SUBMIT", f"Created Blueprint (Domain: {domain})")
        
        conn.commit()
        print(f" >> [Admin] Blueprint saved as Task #{task_id}.")
        print(f"    Domain: {domain} | Status: pending_parsing")
        return task_id
        
    except Exception as e:
        conn.rollback()
        print(f"💥 Failed to submit blueprint: {e}")
        return None
    finally:
        conn.close()

# --- V3.2: Dead Letter Queue Commands ---

def dlq_list():
    """List all tasks in the Dead Letter Queue."""
    conn = get_db()
    try:
        rows = conn.execute("""
            SELECT id, goal, lane, attempt_count, last_error_type, created_at 
            FROM tasks WHERE status = 'dead_letter'
            ORDER BY created_at DESC
        """).fetchall()
        
        if not rows:
            print("✅ Dead Letter Queue is empty.")
            return
        
        print(f"\n💀 Found {len(rows)} tasks in Dead Letter Queue:")
        for r in rows:
            age_hours = (int(time.time()) - r['created_at']) // 3600
            print(f"  [#{r['id']}] {r['goal']}")
            print(f"      Lane: {r['lane']} | Attempts: {r['attempt_count']} | Error: {r['last_error_type'] or 'unknown'}")
            print(f"      Age: {age_hours}h")
    finally:
        conn.close()


def dlq_retry():
    """Retry all tasks in the Dead Letter Queue (set priority=high)."""
    check_permissions()
    conn = get_db()
    try:
        conn.execute("BEGIN")
        
        # Count before update
        count = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE status = 'dead_letter'").fetchone()['c']
        
        if count == 0:
            print("✅ Dead Letter Queue is empty. Nothing to retry.")
            return
        
        # Reset all DLQ tasks
        conn.execute("""
            UPDATE tasks 
            SET status = 'pending', attempt_count = 0, worker_id = NULL, 
                backoff_until = 0, priority = 'high', updated_at = ?
            WHERE status = 'dead_letter'
        """, (int(time.time()),))  # SAFETY-ALLOW: status-write
        
        # Audit log (use task_id=0 for system-wide actions)
        log_admin_action(conn, 0, "DLQ_RETRY", f"Resuscitated {count} dead letter tasks with priority=high")
        
        conn.commit()
        print(f"🚑 Resuscitated {count} tasks from Dead Letter Queue (priority: high).")
        
    except Exception as e:
        conn.rollback()
        print(f"💥 Failed to retry DLQ: {e}")
    finally:
        conn.close()


def dlq_purge():
    """Permanently delete all tasks in the Dead Letter Queue."""
    check_permissions()
    conn = get_db()
    try:
        count = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE status = 'dead_letter'").fetchone()['c']
        
        if count == 0:
            print("✅ Dead Letter Queue is empty. Nothing to purge.")
            return
        
        # Confirm before purge
        print(f"⚠️ About to PERMANENTLY DELETE {count} dead letter tasks.")
        confirm = input("Type 'PURGE' to confirm: ")
        if confirm != "PURGE":
            print("❌ Purge cancelled.")
            return
        
        conn.execute("BEGIN")
        conn.execute("DELETE FROM tasks WHERE status = 'dead_letter'")
        log_admin_action(conn, 0, "DLQ_PURGE", f"Purged {count} dead letter tasks")
        conn.commit()
        
        print(f"🗑️ Purged {count} tasks from Dead Letter Queue.")
        
    except Exception as e:
        conn.rollback()
        print(f"💥 Failed to purge DLQ: {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python vibe_admin.py [list|approve <id>|retry <id>|dlq <list|retry|purge>|blueprint <content> [domain]]")
        sys.exit(1)
    
    cmd = sys.argv[1]
    
    if cmd == "list": 
        list_pending_approvals()
    elif cmd == "approve": 
        if len(sys.argv) < 3: print("Error: Missing Task ID"); sys.exit(1)
        approve_task(sys.argv[2])
    elif cmd == "retry": 
        if len(sys.argv) < 3: print("Error: Missing Task ID"); sys.exit(1)
        retry_task(sys.argv[2])
    elif cmd == "blueprint":
        if len(sys.argv) < 3: print("Error: Missing content"); sys.exit(1)
        content = sys.argv[2]
        domain = sys.argv[3] if len(sys.argv) > 3 else "general"
        submit_blueprint(content, domain)
    elif cmd == "dlq":
        if len(sys.argv) < 3:
            print("Usage: python vibe_admin.py dlq [list|retry|purge]")
            sys.exit(1)
        subcmd = sys.argv[2]
        if subcmd == "list":
            dlq_list()
        elif subcmd == "retry":
            dlq_retry()
        elif subcmd == "purge":
            dlq_purge()
        else:
            print(f"Unknown DLQ command: {subcmd}")
    else:
        print(f"Unknown command: {cmd}")

