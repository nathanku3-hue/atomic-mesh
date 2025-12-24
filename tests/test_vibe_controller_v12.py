"""
Vibe Controller V1.2 - Integration Test Suite
Tests new Platinum features: Blocked Task Management
"""

import sqlite3
import json
import time
import sys
import os


# Set env var for controller config
os.environ["BLOCKED_TIMEOUT_SEC"] = "1"  # 1 second for testing
DB_PATH = "vibe_coding_test_v12.db"
os.environ["DB_PATH"] = DB_PATH

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from agent_tools import ask_clarification, claim_task

def setup_test_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DROP TABLE IF EXISTS tasks")
    conn.execute("DROP TABLE IF EXISTS task_messages")
    
    conn.execute("""
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lane TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            goal TEXT NOT NULL,
            context_files TEXT,
            dependencies TEXT,
            worker_id TEXT,
            lease_id TEXT,
            lease_expires_at INTEGER DEFAULT 0,
            attempt_count INTEGER DEFAULT 0,
            metadata TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
    """)
    
    conn.execute("""
        CREATE TABLE task_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            msg_type TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )
    """)
    conn.commit()
    conn.close()

def test_blocked_workflow():
    print("\n🧪 Test: Blocked Task Workflow")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # 1. Create task
    now = int(time.time())
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, created_at)
        VALUES (1, '@backend', 'in_progress', 'Fix bug', ?)
    """, (now,))
    conn.commit()
    conn.close()
    
    # 2. Worker calls ask_clarification
    print("   Worker actions: ask_clarification()")
    ask_clarification(1, "Missing API key")
    
    # Verify blocked status
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    task = conn.execute("SELECT status, metadata FROM tasks WHERE id=1").fetchone()
    assert task[0] == 'blocked', f"❌ Status should be blocked, got {task[0]}"
    assert "Missing API key" in task[1], "❌ Metadata should contain blocker msg"
    print("   ✅ Status -> blocked")
    
    # 3. Simulate Time Travel (manually backdate)
    print("   Simulating 24h wait (backdating)...")
    backdated = int(time.time()) - 3600 # 1 hour ago
    conn.execute("UPDATE tasks SET updated_at=? WHERE id=1", (backdated,))
    conn.commit()
    
    # 4. Run Controller Sweeper
    # We import here to get the updated env vars
    import vibe_controller
    vibe_controller.DB_PATH = DB_PATH
    vibe_controller.BLOCKED_TIMEOUT_SEC = 1
    
    print("   Controller actions: sweep_blocked_tasks()")
    count = vibe_controller.sweep_blocked_tasks(conn)
    
    # Verify Reassignment
    task = conn.execute("SELECT status, attempt_count FROM tasks WHERE id=1").fetchone()
    assert count == 1, "❌ Should have processed 1 task"
    assert task[0] == 'pending', f"❌ Status should be pending (reassigned), got {task[0]}"
    assert task[1] == 1, f"❌ Attempt count should be 1, got {task[1]}"
    print("   ✅ Task reassigned (pending, attempt += 1)")
    
    # 5. Simulate Max Retries
    print("   Simulating max retries escalation...")
    conn.execute("UPDATE tasks SET status='blocked', attempt_count=3, updated_at=? WHERE id=1", (int(time.time()) - 10,))
    conn.commit()
    
    vibe_controller.sweep_blocked_tasks(conn)
    
    # Verify Escalation (Updated_at touched, but still blocked or failed? V1.2 logic says notify human but keep blocked)
    # The code says: notify_human("STILL BLOCKED", critical) and touch updated_at
    task = conn.execute("SELECT status FROM tasks WHERE id=1").fetchone()
    assert task[0] == 'blocked', f"❌ Status should remain blocked (escalated), got {task[0]}"
    print("   ✅ Task escalated (remains blocked, human notified)")
    
    conn.close()
    print("✅ PASS: Blocked task workflow")

if __name__ == "__main__":
    setup_test_db()
    test_blocked_workflow()
