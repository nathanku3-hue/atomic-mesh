"""
Vibe Admin Tool V1.3 - Integration Test
Tests admin commands and audit trail functionality
"""

import sqlite3
import os
import sys
import json

# Set test environment
DB_PATH = "vibe_coding_test_admin.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["VIBE_ROLE"] = "admin"  # Authenticate for tests

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from vibe_admin import approve_task, retry_task, list_pending_approvals

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
            metadata TEXT,
            worker_id TEXT,
            lease_id TEXT,
            attempt_count INTEGER DEFAULT 0,
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

def test_approve_workflow():
    print("\n🧪 Test: Admin Approval Workflow")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # 1. Create high-risk task
    meta = json.dumps({"risk": "high", "reason": "OAuth integration"})
    conn.execute("INSERT INTO tasks (id, lane, status, goal, metadata) VALUES (1, '@backend', 'review_needed', 'Add SSO', ?)", (meta,))
    conn.commit()
    conn.close()
    
    # 2. Admin approves
    print("   Admin action: approve(1)")
    approve_task(1)
    
    # 3. Verify metadata updated
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    task = conn.execute("SELECT metadata FROM tasks WHERE id=1").fetchone()
    meta = json.loads(task['metadata'])
    
    assert meta['risk'] == 'low', f"❌ Risk should be 'low', got {meta['risk']}"
    assert meta['human_approved'] == True, "❌ human_approved should be True"
    print("   ✅ Metadata updated (risk: high -> low)")
    
    # 4. Verify audit trail
    audit = conn.execute("SELECT content FROM task_messages WHERE task_id=1 AND role='admin'").fetchone()
    assert audit is not None, "❌ Audit trail missing"
    assert "ADMIN APPROVE" in audit['content'], "❌ Audit content incorrect"
    print("   ✅ Audit trail logged")
    
    conn.close()
    print("✅ PASS: Admin approval workflow")

def test_retry_workflow():
    print("\n🧪 Test: Admin Retry Workflow")
    conn = sqlite3.connect(DB_PATH)
    
    # 1. Create failed task
    conn.execute("INSERT INTO tasks (id, lane, status, goal, attempt_count) VALUES (2, '@backend', 'failed', 'Fix bug', 3)")
    conn.commit()
    conn.close()
    
    # 2. Admin retries
    print("   Admin action: retry(2)")
    retry_task(2)
    
    # 3. Verify reset
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    task = conn.execute("SELECT status, attempt_count FROM tasks WHERE id=2").fetchone()
    
    assert task['status'] == 'pending', f"❌ Status should be 'pending', got {task['status']}"
    assert task['attempt_count'] == 0, f"❌ Attempt count should be 0, got {task['attempt_count']}"
    print("   ✅ Task reset (status: failed -> pending, attempts: 3 -> 0)")
    
    # 4. Verify audit trail
    audit = conn.execute("SELECT content FROM task_messages WHERE task_id=2 AND role='admin'").fetchone()
    assert audit is not None, "❌ Audit trail missing"
    assert "ADMIN RETRY" in audit['content'], "❌ Audit content incorrect"
    print("   ✅ Audit trail logged")
    
    conn.close()
    print("✅ PASS: Admin retry workflow")

def cleanup():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

if __name__ == "__main__":
    print("============================================================")
    print("Vibe Admin Tool V1.3 - Integration Tests")
    print("============================================================")
    
    setup_test_db()
    test_approve_workflow()
    test_retry_workflow()
    cleanup()
    
    print("\n============================================================")
    print("✅ ALL TESTS PASSED")
    print("============================================================")
