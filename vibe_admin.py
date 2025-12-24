"""
Vibe Admin Tool V1.3 Platinum Master
====================================
Human Control Panel for the Vibe Coding System.

Features:
- Audit Trails: Every admin action logged to task_messages
- Transactional Safety: Strict try/except/rollback patterns
- Role Gating: VIBE_ROLE environment check
- Commands: list, approve, retry
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

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python vibe_admin.py [list|approve <id>|retry <id>]")
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
    else:
        print(f"Unknown command: {cmd}")
