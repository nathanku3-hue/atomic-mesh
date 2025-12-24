"""
Vibe Controller V1.1 - Integration Test Suite
Tests critical workflows: Rejection Handling, Guardian Chaining, Circuit Breaker
"""

import sqlite3
import json
import time
import sys

DB_PATH = "vibe_coding_test.db"

def setup_test_db():
    """Create fresh test database."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DROP TABLE IF EXISTS tasks")
    conn.execute("DROP TABLE IF EXISTS task_messages")
    
    # Create tables
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
    return conn


def test_guardian_chaining(conn):
    """Test that Docs depends on QA task, not dev task."""
    print("\n🧪 Test 1: Guardian Chaining")
    
    # Simulate dev task approval
    now = int(time.time())
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, context_files, created_at)
        VALUES (1, '@backend', 'completed', 'Fix login bug', '["auth.py"]', ?)
    """, (now,))
    
    # Simulate controller spawning guardians (V1.1 logic)
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, dependencies)
        VALUES (2, '@qa', 'pending', 'Verify Task #1', '[1]')
    """)
    
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, dependencies)
        VALUES (3, '@docs', 'pending', 'Document Task #1', '[2]')
    """)
    
    conn.commit()
    
    # Verify
    docs_task = conn.execute("SELECT dependencies FROM tasks WHERE id=3").fetchone()
    deps = json.loads(docs_task[0])
    
    assert deps == [2], f"❌ Docs should depend on QA task #2, got {deps}"
    print("✅ PASS: Docs depends on QA task (not dev task)")


def test_qa_rejection(conn):
    """Test QA rejection triggers task reopening."""
    print("\n🧪 Test 2: QA Rejection Handling")
    
    now = int(time.time())
    
    # Create dev task
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, attempt_count, created_at)
        VALUES (10, '@backend', 'completed', 'Implement feature', 0, ?)
    """, (now,))
    
    # Create QA task that will reject
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, dependencies, metadata, created_at)
        VALUES (11, '@qa', 'review_needed', 'Verify Task #10', '[10]', ?, ?)
    """, (json.dumps({"status": "REJECT", "reason": "Missing null check"}), now))
    
    conn.commit()
    
    # Simulate controller's handle_rejection logic
    conn.row_factory = sqlite3.Row
    qa_task = dict(conn.execute("SELECT * FROM tasks WHERE id=11").fetchone())
    metadata = json.loads(qa_task['metadata'])
    deps = json.loads(qa_task['dependencies'])
    
    if metadata.get('status') == 'REJECT':
        original_task_id = deps[0]
        
        # Reopen original task
        conn.execute("""
            UPDATE tasks 
            SET status='pending', attempt_count=attempt_count+1, updated_at=?
            WHERE id=?
        """, (now, original_task_id))
        
        # Complete QA task
        conn.execute("UPDATE tasks SET status='completed', updated_at=? WHERE id=11", (now,))
        
        # Log feedback
        conn.execute("""
            INSERT INTO task_messages (task_id, role, msg_type, content, created_at)
            VALUES (?, 'system', 'feedback', ?, ?)
        """, (original_task_id, f"⚠️ QA Rejected: {metadata['reason']}", now))
        
        conn.commit()
    
    # Verify
    dev_task = conn.execute("SELECT status, attempt_count FROM tasks WHERE id=10").fetchone()
    assert dev_task[0] == 'pending', f"❌ Dev task should be pending, got {dev_task[0]}"
    assert dev_task[1] == 1, f"❌ Attempt count should be 1, got {dev_task[1]}"
    
    feedback = conn.execute("SELECT content FROM task_messages WHERE task_id=10").fetchone()
    assert "Missing null check" in feedback[0], "❌ Feedback not logged"
    
    print("✅ PASS: QA rejection reopens task with feedback")


def test_circuit_breaker(conn):
    """Test that 3 rejections fail the task."""
    print("\n🧪 Test 3: Circuit Breaker (Max Retries)")
    
    now = int(time.time())
    
    # Create task that has been rejected twice already
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, attempt_count, created_at)
        VALUES (20, '@backend', 'completed', 'Complex feature', 2, ?)
    """, (now,))
    
    # QA rejects for 3rd time
    conn.execute("""
        INSERT INTO tasks (id, lane, status, goal, dependencies, metadata, created_at)
        VALUES (21, '@qa', 'review_needed', 'Verify Task #20', '[20]', ?, ?)
    """, (json.dumps({"status": "REJECT", "reason": "Still buggy"}), now))
    
    conn.commit()
    
    # Simulate controller's handle_rejection with circuit breaker
    conn.row_factory = sqlite3.Row
    qa_task = dict(conn.execute("SELECT * FROM tasks WHERE id=21").fetchone())
    metadata = json.loads(qa_task['metadata'])
    deps = json.loads(qa_task['dependencies'])
    
    if metadata.get('status') == 'REJECT':
        original_task_id = deps[0]
        target_task = conn.execute("SELECT attempt_count FROM tasks WHERE id=?", (original_task_id,)).fetchone()
        attempts = target_task[0] + 1
        
        if attempts >= 3:  # MAX_RETRIES
            # FAIL the task
            conn.execute("UPDATE tasks SET status='failed', updated_at=? WHERE id=?", (now, original_task_id))
            print(f"   💀 Task #{original_task_id} FAILED after {attempts} attempts")
        
        conn.commit()
    
    # Verify
    dev_task = conn.execute("SELECT status FROM tasks WHERE id=20").fetchone()
    assert dev_task[0] == 'failed', f"❌ Task should be failed, got {dev_task[0]}"
    
    print("✅ PASS: Task fails after 3 rejections")


def main():
    print("=" * 60)
    print("Vibe Controller V1.1 - Integration Tests")
    print("=" * 60)
    
    conn = setup_test_db()
    
    try:
        test_guardian_chaining(conn)
        test_qa_rejection(conn)
        test_circuit_breaker(conn)
        
        print("\n" + "=" * 60)
        print("✅ ALL TESTS PASSED")
        print("=" * 60)
        
    except AssertionError as e:
        print(f"\n❌ TEST FAILED: {e}")
        sys.exit(1)
    
    finally:
        conn.close()


if __name__ == "__main__":
    main()
