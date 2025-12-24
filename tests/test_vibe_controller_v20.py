"""
Vibe Controller V2.0 - Integration Test
Tests Push Delegation, Fallback, Worker Health, and Assignment Watchdog
"""

import sqlite3
import os
import sys
import json
import time

# Set test environment
DB_PATH = "vibe_coding_test_v20.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["ASSIGNMENT_TIMEOUT_SEC"] = "2"  # 2 seconds for testing
os.environ["IDLE_TIMEOUT_SEC"] = "3"  # 3 seconds for testing

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import vibe_controller


def setup_test_db():
    """Create V2.0 schema for testing."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # Drop existing tables
    conn.execute("DROP TABLE IF EXISTS tasks")
    conn.execute("DROP TABLE IF EXISTS task_messages")
    conn.execute("DROP TABLE IF EXISTS task_history")
    conn.execute("DROP TABLE IF EXISTS worker_health")
    
    # Create V2.0 schema
    conn.execute("""
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id TEXT NOT NULL,
            lane TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            goal TEXT NOT NULL,
            context_files TEXT,
            dependencies TEXT,
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
    
    conn.execute("""
        CREATE TABLE task_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            worker_id TEXT,
            timestamp INTEGER NOT NULL,
            details TEXT
        )
    """)
    
    conn.execute("""
        CREATE TABLE worker_health (
            worker_id TEXT PRIMARY KEY,
            lane TEXT NOT NULL,
            last_seen INTEGER DEFAULT 0,
            status TEXT DEFAULT 'online',
            active_tasks INTEGER DEFAULT 0,
            completed_today INTEGER DEFAULT 0,
            priority_score INTEGER DEFAULT 50
        )
    """)
    
    # Insert test workers
    conn.execute("""
        INSERT INTO worker_health (worker_id, lane, status, priority_score, last_seen)
        VALUES 
            ('@backend-1', 'backend', 'online', 60, ?),
            ('@backend-2', 'backend', 'online', 50, ?),
            ('@frontend-1', 'frontend', 'online', 60, ?),
            ('@qa-1', 'qa', 'online', 50, ?)
    """, (int(time.time()), int(time.time()), int(time.time()), int(time.time())))
    
    conn.commit()
    return conn


def test_dynamic_load_balancer():
    """Test that get_fallback_worker selects optimal worker."""
    print("\n🧪 Test: Dynamic Load Balancer")
    
    conn = setup_test_db()
    
    # Make @backend-1 busy (high active_tasks)
    conn.execute("UPDATE worker_health SET active_tasks = 5 WHERE worker_id = '@backend-1'")
    conn.commit()
    
    # Get fallback should return @backend-2 (less busy)
    fallback = vibe_controller.get_fallback_worker(conn, 'backend', '@ignore')
    conn.close()
    
    assert fallback == '@backend-2', f"❌ Expected @backend-2 (less busy), got {fallback}"
    print("   ✅ Selected @backend-2 (lower active_tasks)")
    print("✅ PASS: Dynamic load balancer")


def test_assignment_watchdog():
    """Test that ignored tasks are reassigned."""
    print("\n🧪 Test: Assignment Watchdog")
    
    conn = setup_test_db()
    
    # Create task assigned to @backend-1, but backdate created_at to trigger timeout
    old_time = int(time.time()) - 10  # 10 seconds ago (timeout is 2 seconds)
    conn.execute("""
        INSERT INTO tasks (worker_id, lane, goal, status, created_at)
        VALUES ('@backend-1', 'backend', 'Test task', 'pending', ?)
    """, (old_time,))
    conn.commit()
    
    # Run watchdog
    reassigned = vibe_controller.enforce_assignments(conn)
    
    # Check that task was reassigned
    task = conn.execute("SELECT worker_id, metadata FROM tasks WHERE id = 1").fetchone()
    meta = json.loads(task['metadata'] or '{}')
    conn.close()
    
    assert reassigned == 1, f"❌ Expected 1 reassignment, got {reassigned}"
    assert task['worker_id'] == '@backend-2', f"❌ Expected @backend-2, got {task['worker_id']}"
    assert meta.get('fallback_tried') == True, "❌ fallback_tried should be True"
    print("   ✅ Task reassigned to @backend-2")
    print("   ✅ Metadata marked fallback_tried=True")
    print("✅ PASS: Assignment watchdog")


def test_worker_idle_detection():
    """Test that idle workers are marked offline."""
    print("\n🧪 Test: Worker Idle Detection")
    
    conn = setup_test_db()
    
    # Make @backend-1 idle (old last_seen)
    old_time = int(time.time()) - 10  # 10 seconds ago (timeout is 3 seconds)
    conn.execute("UPDATE worker_health SET last_seen = ? WHERE worker_id = '@backend-1'", (old_time,))
    conn.commit()
    
    # Run idle detection
    marked = vibe_controller.handle_worker_idle(conn)
    
    # Check status
    worker = conn.execute("SELECT status FROM worker_health WHERE worker_id = '@backend-1'").fetchone()
    conn.close()
    
    assert marked >= 1, f"❌ Expected at least 1 worker marked, got {marked}"
    assert worker['status'] == 'offline', f"❌ Expected 'offline', got {worker['status']}"
    print("   ✅ @backend-1 marked offline after idle timeout")
    print("✅ PASS: Worker idle detection")


def test_audit_logging():
    """Test that log_status writes to task_history."""
    print("\n🧪 Test: Audit Logging")
    
    conn = setup_test_db()
    
    # Log a status change
    vibe_controller.log_status(conn, 1, "completed", "@backend-1", "Test completion")
    conn.commit()
    
    # Check task_history
    history = conn.execute("SELECT * FROM task_history WHERE task_id = 1").fetchone()
    conn.close()
    
    assert history is not None, "❌ No history entry found"
    assert history['status'] == "completed", f"❌ Expected 'completed', got {history['status']}"
    assert history['worker_id'] == "@backend-1", f"❌ Expected '@backend-1', got {history['worker_id']}"
    assert history['details'] == "Test completion", f"❌ Expected 'Test completion', got {history['details']}"
    print("   ✅ Status change logged to task_history")
    print("✅ PASS: Audit logging")


def test_worker_health_update():
    """Test that update_worker_health updates metrics correctly."""
    print("\n🧪 Test: Worker Health Update")
    
    conn = setup_test_db()
    
    # Claim action
    vibe_controller.update_worker_health(conn, '@backend-1', 'claim')
    conn.commit()
    
    worker = conn.execute("SELECT active_tasks, status FROM worker_health WHERE worker_id = '@backend-1'").fetchone()
    assert worker['active_tasks'] == 1, f"❌ Expected active_tasks=1, got {worker['active_tasks']}"
    assert worker['status'] == 'busy', f"❌ Expected 'busy', got {worker['status']}"
    print("   ✅ Claim: active_tasks=1, status=busy")
    
    # Complete action
    vibe_controller.update_worker_health(conn, '@backend-1', 'complete')
    conn.commit()
    
    worker = conn.execute("SELECT active_tasks, completed_today, status FROM worker_health WHERE worker_id = '@backend-1'").fetchone()
    assert worker['active_tasks'] == 0, f"❌ Expected active_tasks=0, got {worker['active_tasks']}"
    assert worker['completed_today'] == 1, f"❌ Expected completed_today=1, got {worker['completed_today']}"
    assert worker['status'] == 'online', f"❌ Expected 'online', got {worker['status']}"
    print("   ✅ Complete: active_tasks=0, completed_today=1, status=online")
    
    conn.close()
    print("✅ PASS: Worker health update")


def cleanup():
    # Give time for connections to close
    import gc
    gc.collect()
    time.sleep(0.5)
    try:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
    except:
        pass  # Ignore if file is locked


if __name__ == "__main__":
    print("============================================================")
    print("Vibe Controller V2.0 - Integration Tests")
    print("============================================================")
    
    try:
        test_dynamic_load_balancer()
        test_assignment_watchdog()
        test_worker_idle_detection()
        test_audit_logging()
        test_worker_health_update()
    finally:
        cleanup()
    
    print("\n============================================================")
    print("✅ ALL V2.0 TESTS PASSED")
    print("============================================================")
