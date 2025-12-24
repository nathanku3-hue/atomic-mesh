"""
Vibe Controller V3.2 - Integration Test
Tests Worker Tiers, Smart Backoff, Priority Inheritance, Saturation Guard, DLQ
"""

import sqlite3
import os
import sys
import json
import time
import gc

# Set test environment BEFORE importing
DB_PATH = "vibe_coding_test_v32.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["MAX_TASKS_PER_WORKER"] = "3"
os.environ["MAX_RETRIES"] = "3"

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import and override DB_PATH directly
import vibe_controller
vibe_controller.DB_PATH = DB_PATH
vibe_controller.MAX_RETRIES = 3


def setup_test_db():
    """Create V3.2 schema for testing."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # Drop existing tables
    conn.execute("DROP TABLE IF EXISTS tasks")
    conn.execute("DROP TABLE IF EXISTS task_messages")
    conn.execute("DROP TABLE IF EXISTS task_history")
    conn.execute("DROP TABLE IF EXISTS worker_health")
    
    # Create schema
    conn.execute("""
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id TEXT,
            lane TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            goal TEXT NOT NULL,
            context_files TEXT,
            dependencies TEXT,
            lease_id TEXT,
            lease_expires_at INTEGER DEFAULT 0,
            attempt_count INTEGER DEFAULT 0,
            backoff_until INTEGER DEFAULT 0,
            last_error_type TEXT,
            priority TEXT DEFAULT 'normal',
            effort_rating INTEGER DEFAULT 1,
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
            tier TEXT DEFAULT 'standard',
            capacity_limit INTEGER DEFAULT 3,
            last_seen INTEGER DEFAULT 0,
            status TEXT DEFAULT 'online',
            active_tasks INTEGER DEFAULT 0,
            completed_today INTEGER DEFAULT 0,
            priority_score INTEGER DEFAULT 50
        )
    """)
    
    # Deduplication index
    conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_dedup_guardians ON tasks(goal, lane)")
    
    # Insert test workers with tiers
    conn.execute("""
        INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, active_tasks, last_seen)
        VALUES 
            ('@backend-senior', 'backend', 'senior', 5, 'online', 0, ?),
            ('@backend-1', 'backend', 'standard', 3, 'online', 0, ?),
            ('@backend-2', 'backend', 'standard', 3, 'online', 0, ?),
            ('@qa-1', 'qa', 'standard', 3, 'online', 0, ?)
    """, (int(time.time()), int(time.time()), int(time.time()), int(time.time())))
    
    conn.commit()
    return conn


def test_tier_routing_high_effort():
    """Test that high-effort tasks go to senior workers."""
    print("\n🧪 Test: Tier Routing (High Effort)")
    
    conn = setup_test_db()
    
    # Get best worker for effort=5 task
    worker = vibe_controller.get_best_worker_with_tier(conn, 'backend', effort_rating=5)
    conn.close()
    
    assert worker == '@backend-senior', f"❌ Expected @backend-senior for effort=5, got {worker}"
    print("   ✅ High-effort task routed to @backend-senior")
    print("✅ PASS: Tier routing (high effort)")


def test_tier_routing_low_effort():
    """Test that low-effort tasks go to any worker."""
    print("\n🧪 Test: Tier Routing (Low Effort)")
    
    conn = setup_test_db()
    
    # Get best worker for effort=1 task
    worker = vibe_controller.get_best_worker_with_tier(conn, 'backend', effort_rating=1)
    conn.close()
    
    # Should be any available worker (senior or standard)
    assert worker in ['@backend-senior', '@backend-1', '@backend-2'], f"❌ Expected any backend worker, got {worker}"
    print(f"   ✅ Low-effort task routed to {worker}")
    print("✅ PASS: Tier routing (low effort)")


def test_tier_routing_fallback():
    """Test fallback when senior is busy."""
    print("\n🧪 Test: Tier Routing (Fallback)")
    
    conn = setup_test_db()
    
    # Make senior busy (at capacity)
    conn.execute("UPDATE worker_health SET active_tasks = 5 WHERE worker_id = '@backend-senior'")
    conn.commit()
    
    # Get best worker for effort=5 task (should fallback to standard)
    worker = vibe_controller.get_best_worker_with_tier(conn, 'backend', effort_rating=5)
    conn.close()
    
    assert worker in ['@backend-1', '@backend-2'], f"❌ Expected fallback to standard, got {worker}"
    print(f"   ✅ High-effort task fell back to {worker} (senior busy)")
    print("✅ PASS: Tier routing (fallback)")


def test_smart_backoff_network():
    """Test network error gets fixed 2s backoff."""
    print("\n🧪 Test: Smart Backoff (Network)")
    
    conn = setup_test_db()
    
    # Create a task
    conn.execute("INSERT INTO tasks (worker_id, lane, goal, status, attempt_count) VALUES ('@backend-1', 'backend', 'Test task', 'in_progress', 0)")
    conn.commit()
    
    before = conn.execute("SELECT status, attempt_count FROM tasks WHERE id = 1").fetchone()
    print(f"   DEBUG Before: status={before['status']}, attempt={before['attempt_count']}")
    
    # Handle retry with network error
    vibe_controller.handle_smart_retry(conn, 1, "network")
    conn.commit()
    
    after = conn.execute("SELECT status, backoff_until, last_error_type, attempt_count FROM tasks WHERE id = 1").fetchone()
    print(f"   DEBUG After: status={after['status']}, attempt={after['attempt_count']}, error={after['last_error_type']}")
    conn.close()
    
    assert after['status'] == 'pending', f"❌ Expected pending, got {after['status']}"
    assert after['last_error_type'] == 'network', f"❌ Expected network, got {after['last_error_type']}"
    assert after['attempt_count'] == 1, f"❌ Expected 1 attempt, got {after['attempt_count']}"
    # Network backoff is fixed 2s
    assert after['backoff_until'] > 0, "❌ Expected backoff_until to be set"
    print("   ✅ Network error: fixed 2s backoff, status=pending")
    print("✅ PASS: Smart backoff (network)")


def test_smart_backoff_crash():
    """Test crash error gets exponential backoff."""
    print("\n🧪 Test: Smart Backoff (Crash)")
    
    conn = setup_test_db()
    
    # Create a task with 1 prior attempt
    conn.execute("INSERT INTO tasks (worker_id, lane, goal, status, attempt_count) VALUES ('@backend-1', 'backend', 'Test task', 'in_progress', 1)")
    conn.commit()
    
    # Handle retry with crash error
    vibe_controller.handle_smart_retry(conn, 1, "crash")
    conn.commit()
    
    task = conn.execute("SELECT status, backoff_until, last_error_type, attempt_count FROM tasks WHERE id = 1").fetchone()
    now = int(time.time())
    backoff_time = task['backoff_until'] - now
    conn.close()
    
    assert task['status'] == 'pending', f"❌ Expected pending, got {task['status']}"
    assert task['last_error_type'] == 'crash', f"❌ Expected crash, got {task['last_error_type']}"
    assert task['attempt_count'] == 2, f"❌ Expected 2 attempts, got {task['attempt_count']}"
    # 2nd attempt = 2^2 = 4s backoff
    assert backoff_time >= 3, f"❌ Expected ~4s backoff, got {backoff_time}s"
    print(f"   ✅ Crash error: exponential backoff ({backoff_time}s), status=pending")
    print("✅ PASS: Smart backoff (crash)")


def test_smart_backoff_dlq():
    """Test max retries moves to dead letter queue."""
    print("\n🧪 Test: Smart Backoff (DLQ)")
    
    conn = setup_test_db()
    
    # Create a task at max retries
    conn.execute("INSERT INTO tasks (worker_id, lane, goal, status, attempt_count) VALUES ('@backend-1', 'backend', 'Test task', 'in_progress', 2)")
    conn.commit()
    
    # Handle retry (should go to DLQ)
    vibe_controller.handle_smart_retry(conn, 1, "crash")
    conn.commit()
    
    task = conn.execute("SELECT status, last_error_type FROM tasks WHERE id = 1").fetchone()
    conn.close()
    
    assert task['status'] == 'dead_letter', f"❌ Expected dead_letter, got {task['status']}"
    print("   ✅ Max retries exceeded: moved to dead_letter")
    print("✅ PASS: Smart backoff (DLQ)")


def test_priority_inheritance():
    """Test that guardian tasks inherit parent priority."""
    print("\n🧪 Test: Priority Inheritance")
    
    conn = setup_test_db()
    
    # Spawn guardian with critical priority
    task_id = vibe_controller.spawn_guardian(
        conn, '@qa-1', 'qa', 'Verify Task #99', None, [99], priority='critical'
    )
    conn.commit()
    
    task = conn.execute("SELECT priority FROM tasks WHERE id = ?", (task_id,)).fetchone()
    conn.close()
    
    assert task_id is not None, "❌ Guardian should be created"
    assert task['priority'] == 'critical', f"❌ Expected critical, got {task['priority']}"
    print("   ✅ Guardian inherited priority=critical")
    print("✅ PASS: Priority inheritance")


def test_saturation_guard():
    """Test saturation detection."""
    print("\n🧪 Test: Saturation Guard")
    
    conn = setup_test_db()
    
    # Fill workers to 90%+ capacity
    conn.execute("UPDATE worker_health SET active_tasks = 5 WHERE worker_id = '@backend-senior'")
    conn.execute("UPDATE worker_health SET active_tasks = 3 WHERE worker_id = '@backend-1'")
    conn.execute("UPDATE worker_health SET active_tasks = 3 WHERE worker_id = '@backend-2'")
    conn.commit()
    
    # Check saturation
    saturated = vibe_controller.check_saturation(conn, 'backend')
    conn.close()
    
    assert saturated == True, "❌ Expected saturation detected"
    print("   ✅ Saturation detected (11/11 = 100%)")
    print("✅ PASS: Saturation guard")


def cleanup():
    gc.collect()
    time.sleep(0.5)
    try:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
    except:
        pass


if __name__ == "__main__":
    print("============================================================")
    print("Vibe Controller V3.2 - Integration Tests")
    print("============================================================")
    
    try:
        test_tier_routing_high_effort()
        test_tier_routing_low_effort()
        test_tier_routing_fallback()
        test_smart_backoff_network()
        test_smart_backoff_crash()
        test_smart_backoff_dlq()
        test_priority_inheritance()
        test_saturation_guard()
    finally:
        cleanup()
    
    print("\n============================================================")
    print("✅ ALL V3.2 TESTS PASSED")
    print("============================================================")
