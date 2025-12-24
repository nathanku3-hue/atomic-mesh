"""
Vibe Controller V2.1 - Integration Test
Tests Auto-Routing, Deduplication Guard, and Health-Based Routing
"""

import sqlite3
import os
import sys
import json
import time
import gc

# Set test environment
DB_PATH = "vibe_coding_test_v21.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["MAX_TASKS_PER_WORKER"] = "2"  # Low limit for testing

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import vibe_controller


def setup_test_db():
    """Create V2.1 schema for testing."""
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
    
    # V2.1: Deduplication index
    conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_dedup_guardians ON tasks(goal, lane)")
    
    # Insert test workers
    conn.execute("""
        INSERT INTO worker_health (worker_id, lane, status, active_tasks, last_seen)
        VALUES 
            ('@backend-1', 'backend', 'online', 0, ?),
            ('@backend-2', 'backend', 'online', 0, ?),
            ('@frontend-1', 'frontend', 'online', 0, ?),
            ('@qa-1', 'qa', 'online', 0, ?)
    """, (int(time.time()), int(time.time()), int(time.time()), int(time.time())))
    
    conn.commit()
    return conn


def test_auto_routing_basic():
    """Test that worker_id='auto' gets assigned to a real worker."""
    print("\n🧪 Test: Auto-Routing Basic")
    
    conn = setup_test_db()
    
    # Create task with worker_id='auto'
    conn.execute("""
        INSERT INTO tasks (worker_id, lane, goal, status)
        VALUES ('auto', 'backend', 'Test auto-route', 'pending')
    """)
    conn.commit()
    
    # Run auto-router
    routed = vibe_controller.route_pending_tasks(conn)
    
    # Check assignment
    task = conn.execute("SELECT worker_id FROM tasks WHERE id = 1").fetchone()
    conn.close()
    
    assert routed == 1, f"❌ Expected 1 routed, got {routed}"
    assert task['worker_id'] in ['@backend-1', '@backend-2'], f"❌ Expected @backend-*, got {task['worker_id']}"
    print(f"   ✅ Task auto-routed to {task['worker_id']}")
    print("✅ PASS: Auto-routing basic")


def test_auto_routing_load_balance():
    """Test that auto-router picks least-busy worker."""
    print("\n🧪 Test: Auto-Routing Load Balance")
    
    conn = setup_test_db()
    
    # Make @backend-1 busy (1 task)
    conn.execute("UPDATE worker_health SET active_tasks = 1 WHERE worker_id = '@backend-1'")
    conn.commit()
    
    # Create task with worker_id='auto'
    conn.execute("""
        INSERT INTO tasks (worker_id, lane, goal, status)
        VALUES ('auto', 'backend', 'Test load balance', 'pending')
    """)
    conn.commit()
    
    # Run auto-router
    vibe_controller.route_pending_tasks(conn)
    
    # Check assignment - should go to @backend-2 (less busy)
    task = conn.execute("SELECT worker_id FROM tasks WHERE id = 1").fetchone()
    conn.close()
    
    assert task['worker_id'] == '@backend-2', f"❌ Expected @backend-2, got {task['worker_id']}"
    print("   ✅ Routed to @backend-2 (least busy)")
    print("✅ PASS: Auto-routing load balance")


def test_auto_routing_capacity_limit():
    """Test that workers at capacity are skipped."""
    print("\n🧪 Test: Auto-Routing Capacity Limit")
    
    conn = setup_test_db()
    
    # Make @backend-1 at capacity (2 tasks = MAX)
    conn.execute("UPDATE worker_health SET active_tasks = 2 WHERE worker_id = '@backend-1'")
    conn.commit()
    
    # Create task with worker_id='auto'
    conn.execute("""
        INSERT INTO tasks (worker_id, lane, goal, status)
        VALUES ('auto', 'backend', 'Test capacity', 'pending')
    """)
    conn.commit()
    
    # Run auto-router
    vibe_controller.route_pending_tasks(conn)
    
    # Check assignment - should NOT go to @backend-1
    task = conn.execute("SELECT worker_id FROM tasks WHERE id = 1").fetchone()
    conn.close()
    
    assert task['worker_id'] == '@backend-2', f"❌ Expected @backend-2, got {task['worker_id']}"
    print("   ✅ Skipped @backend-1 (at capacity), routed to @backend-2")
    print("✅ PASS: Auto-routing capacity limit")


def test_deduplication_guard():
    """Test that duplicate guardian tasks are blocked."""
    print("\n🧪 Test: Deduplication Guard")
    
    conn = setup_test_db()
    
    # Spawn first guardian
    task1 = vibe_controller.spawn_guardian(conn, '@qa-1', 'qa', 'Verify Task #1', None, [1])
    conn.commit()
    
    assert task1 is not None, "❌ First guardian should be created"
    print(f"   ✅ First guardian created: #{task1}")
    
    # Try to spawn duplicate
    task2 = vibe_controller.spawn_guardian(conn, '@qa-1', 'qa', 'Verify Task #1', None, [1])
    
    assert task2 is None, "❌ Duplicate guardian should be blocked"
    print("   ✅ Duplicate guardian blocked")
    
    # Verify only one exists
    count = conn.execute("SELECT COUNT(*) as c FROM tasks WHERE goal = 'Verify Task #1'").fetchone()['c']
    conn.close()
    
    assert count == 1, f"❌ Expected 1 task, got {count}"
    print("   ✅ Only one guardian task exists")
    print("✅ PASS: Deduplication guard")


def test_deduplication_unique_constraint():
    """Test that unique index catches race conditions."""
    print("\n🧪 Test: Deduplication Unique Constraint")
    
    conn = setup_test_db()
    
    # Insert first task directly
    conn.execute("""
        INSERT INTO tasks (worker_id, lane, goal, status)
        VALUES ('@qa-1', 'qa', 'Verify Task #99', 'pending')
    """)
    conn.commit()
    
    # Try to spawn via function (should hit unique constraint)
    result = vibe_controller.spawn_guardian(conn, '@qa-1', 'qa', 'Verify Task #99', None, [99])
    conn.close()
    
    assert result is None, "❌ Should be blocked by pre-check or unique constraint"
    print("   ✅ Duplicate blocked by pre-check")
    print("✅ PASS: Deduplication unique constraint")


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
    print("Vibe Controller V2.1 - Integration Tests")
    print("============================================================")
    
    try:
        test_auto_routing_basic()
        test_auto_routing_load_balance()
        test_auto_routing_capacity_limit()
        test_deduplication_guard()
        test_deduplication_unique_constraint()
    finally:
        cleanup()
    
    print("\n============================================================")
    print("✅ ALL V2.1 TESTS PASSED")
    print("============================================================")
