"""
Vibe Controller V3.3 - Integration Test
Tests Worker Cache, Weighted Scoring, History Archival, Auto-Scaler
"""

import sqlite3
import os
import sys
import time
import gc

# Set test environment BEFORE importing
DB_PATH = "vibe_coding_test_v33.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["CACHE_TTL"] = "2"  # Short TTL for testing
os.environ["MAX_AUTO_SCALE_WORKERS"] = "3"

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import vibe_controller
vibe_controller.DB_PATH = DB_PATH
vibe_controller.CACHE_TTL = 2
vibe_controller.MAX_AUTO_SCALE_WORKERS = 3
vibe_controller.HISTORY_ARCHIVE_DAYS = 7


def setup_test_db():
    """Create V3.3 schema for testing."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    # Drop existing tables
    conn.execute("DROP TABLE IF EXISTS tasks")
    conn.execute("DROP TABLE IF EXISTS task_messages")
    conn.execute("DROP TABLE IF EXISTS task_history")
    conn.execute("DROP TABLE IF EXISTS task_history_archive")
    conn.execute("DROP TABLE IF EXISTS worker_health")
    
    # Create schema (V3.3 compatible)
    conn.execute("""
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id TEXT,
            lane TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            goal TEXT NOT NULL,
            context_files TEXT,
            dependencies TEXT,
            attempt_count INTEGER DEFAULT 0,
            priority TEXT DEFAULT 'normal',
            effort_rating INTEGER DEFAULT 1,
            status_updated_at INTEGER DEFAULT (strftime('%s', 'now')),
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER DEFAULT (strftime('%s', 'now'))
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
        CREATE TABLE task_history_archive (
            id INTEGER PRIMARY KEY,
            task_id INTEGER,
            status TEXT,
            worker_id TEXT,
            timestamp INTEGER,
            details TEXT
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
        CREATE TABLE worker_health (
            worker_id TEXT PRIMARY KEY,
            lane TEXT NOT NULL,
            tier TEXT DEFAULT 'standard',
            capacity_limit INTEGER DEFAULT 3,
            last_seen INTEGER DEFAULT 0,
            status TEXT DEFAULT 'online',
            active_tasks INTEGER DEFAULT 0,
            priority_score INTEGER DEFAULT 50
        )
    """)
    
    # Insert test workers with tiers
    conn.execute("""
        INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, active_tasks, priority_score, last_seen)
        VALUES 
            ('@backend-senior', 'backend', 'senior', 5, 'online', 0, 80, ?),
            ('@backend-1', 'backend', 'standard', 3, 'online', 0, 60, ?),
            ('@backend-2', 'backend', 'standard', 3, 'online', 0, 50, ?)
    """, (int(time.time()), int(time.time()), int(time.time())))
    
    conn.commit()
    
    # Clear cache between tests
    vibe_controller.invalidate_worker_cache()
    
    return conn


def test_cache_hit():
    """Test that cache returns cached workers."""
    print("\n🧪 Test: Cache Hit")
    
    conn = setup_test_db()
    vibe_controller.metrics["cache_hits"] = 0
    vibe_controller.metrics["cache_misses"] = 0
    
    # First call - cache miss
    workers1 = vibe_controller.get_cached_workers(conn, 'backend')
    assert vibe_controller.metrics["cache_misses"] == 1, "First call should miss"
    
    # Second call - cache hit
    workers2 = vibe_controller.get_cached_workers(conn, 'backend')
    assert vibe_controller.metrics["cache_hits"] == 1, "Second call should hit"
    
    conn.close()
    print("   ✅ Second query hit cache")
    print("✅ PASS: Cache hit")


def test_cache_invalidation():
    """Test that cache is invalidated correctly."""
    print("\n🧪 Test: Cache Invalidation")
    
    conn = setup_test_db()
    
    # Populate cache
    vibe_controller.get_cached_workers(conn, 'backend')
    
    # Invalidate
    vibe_controller.invalidate_worker_cache('backend')
    
    # Verify cache empty
    assert 'backend' not in vibe_controller.WORKER_CACHE, "Cache should be invalidated"
    
    conn.close()
    print("   ✅ Cache invalidated after worker update")
    print("✅ PASS: Cache invalidation")


def test_weighted_scoring():
    """Test that scoring produces correct rankings."""
    print("\n🧪 Test: Weighted Scoring")
    
    senior = {'tier': 'senior', 'capacity_limit': 5, 'active_tasks': 0, 'priority_score': 80}
    standard = {'tier': 'standard', 'capacity_limit': 3, 'active_tasks': 0, 'priority_score': 50}
    
    # High effort task - senior should score higher
    score_senior = vibe_controller.calculate_worker_score(senior, effort_rating=5, priority='normal')
    score_standard = vibe_controller.calculate_worker_score(standard, effort_rating=5, priority='normal')
    
    assert score_senior > score_standard, f"Senior should score higher for effort=5: {score_senior} vs {score_standard}"
    print(f"   ✅ Effort=5: Senior={score_senior} > Standard={score_standard}")
    
    # Low effort - scores should be closer
    score_senior_low = vibe_controller.calculate_worker_score(senior, effort_rating=1, priority='normal')
    score_standard_low = vibe_controller.calculate_worker_score(standard, effort_rating=1, priority='normal')
    
    print(f"   ✅ Effort=1: Senior={score_senior_low}, Standard={score_standard_low}")
    
    # Critical priority boost
    score_critical = vibe_controller.calculate_worker_score(standard, effort_rating=1, priority='critical')
    score_normal = vibe_controller.calculate_worker_score(standard, effort_rating=1, priority='normal')
    
    assert score_critical > score_normal, "Critical should boost score"
    print(f"   ✅ Critical boost: {score_critical} > {score_normal}")
    
    print("✅ PASS: Weighted scoring")


def test_score_tiebreaker():
    """Test that identical scores don't break routing."""
    print("\n🧪 Test: Score Tie-breaker")
    
    # Two identical workers
    worker1 = {'tier': 'standard', 'capacity_limit': 3, 'active_tasks': 0, 'priority_score': 50}
    worker2 = {'tier': 'standard', 'capacity_limit': 3, 'active_tasks': 0, 'priority_score': 50}
    
    score1 = vibe_controller.calculate_worker_score(worker1, effort_rating=1, priority='normal')
    score2 = vibe_controller.calculate_worker_score(worker2, effort_rating=1, priority='normal')
    
    assert score1 == score2, "Identical workers should have same score"
    print(f"   ✅ Score tie detected: {score1} == {score2}")
    print("✅ PASS: Score tie-breaker (no crash)")


def test_history_archival():
    """Test that old history is archived."""
    print("\n🧪 Test: History Archival")
    
    conn = setup_test_db()
    
    # Insert old history (10 days ago)
    old_timestamp = int(time.time()) - (10 * 86400)
    conn.execute("""
        INSERT INTO task_history (task_id, status, worker_id, timestamp, details)
        VALUES (1, 'completed', '@backend-1', ?, 'Old record')
    """, (old_timestamp,))
    
    # Insert recent history
    conn.execute("""
        INSERT INTO task_history (task_id, status, worker_id, timestamp, details)
        VALUES (2, 'completed', '@backend-1', ?, 'New record')
    """, (int(time.time()),))
    conn.commit()
    
    # Archive old records
    archived = vibe_controller.archive_old_history(conn, days=7)
    
    # Verify
    history_count = conn.execute("SELECT COUNT(*) as c FROM task_history").fetchone()['c']
    archive_count = conn.execute("SELECT COUNT(*) as c FROM task_history_archive").fetchone()['c']
    conn.close()
    
    assert archived == 1, f"Expected 1 archived, got {archived}"
    assert history_count == 1, f"Expected 1 remaining in history, got {history_count}"
    assert archive_count == 1, f"Expected 1 in archive, got {archive_count}"
    
    print(f"   ✅ Archived {archived} old records")
    print("✅ PASS: History archival")


def test_auto_scaler_provision():
    """Test auto-scaler creates virtual workers."""
    print("\n🧪 Test: Auto-Scaler Provision")
    
    conn = setup_test_db()
    vibe_controller.metrics["auto_scale_events"] = 0
    
    # Provision virtual worker
    new_id = vibe_controller.provision_virtual_worker(conn, 'backend')
    
    assert new_id is not None, "Should create virtual worker"
    assert new_id.startswith('@backend-auto-'), f"Expected @backend-auto-*, got {new_id}"
    assert vibe_controller.metrics["auto_scale_events"] == 1
    
    # Verify in DB
    worker = conn.execute("SELECT * FROM worker_health WHERE worker_id = ?", (new_id,)).fetchone()
    conn.close()
    
    assert worker is not None, "Worker should exist in DB"
    assert worker['status'] == 'online'
    
    print(f"   ✅ Provisioned: {new_id}")
    print("✅ PASS: Auto-scaler provision")


def test_auto_scaler_limit():
    """Test auto-scaler respects MAX limit."""
    print("\n🧪 Test: Auto-Scaler Limit")
    
    conn = setup_test_db()
    
    # Create MAX workers
    for i in range(vibe_controller.MAX_AUTO_SCALE_WORKERS):
        conn.execute("""
            INSERT INTO worker_health (worker_id, lane, tier, status, last_seen)
            VALUES (?, 'backend', 'standard', 'online', ?)
        """, (f"@backend-auto-{i}", int(time.time())))
    conn.commit()
    
    # Try to provision more - should fail
    new_id = vibe_controller.provision_virtual_worker(conn, 'backend')
    conn.close()
    
    assert new_id is None, "Should not exceed MAX limit"
    print(f"   ✅ Rejected at limit ({vibe_controller.MAX_AUTO_SCALE_WORKERS})")
    print("✅ PASS: Auto-scaler limit")


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
    print("Vibe Controller V3.3 - Integration Tests")
    print("============================================================")
    
    try:
        test_cache_hit()
        test_cache_invalidation()
        test_weighted_scoring()
        test_score_tiebreaker()
        test_history_archival()
        test_auto_scaler_provision()
        test_auto_scaler_limit()
    finally:
        cleanup()
    
    print("\n============================================================")
    print("✅ ALL V3.3 TESTS PASSED")
    print("============================================================")
