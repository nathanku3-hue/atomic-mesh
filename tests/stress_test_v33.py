"""
Vibe Controller V3.3 - Stress Test & Monitoring
Validates cache, auto-scaling, and saturation handling under load.
"""

import sqlite3
import os
import sys
import time
import random
import threading

# Test environment
DB_PATH = "vibe_stress_test.db"
os.environ["DB_PATH"] = DB_PATH
os.environ["CACHE_TTL"] = "5"
os.environ["MAX_AUTO_SCALE_WORKERS"] = "10"

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import vibe_controller
vibe_controller.DB_PATH = DB_PATH
vibe_controller.CACHE_TTL = 5
vibe_controller.MAX_AUTO_SCALE_WORKERS = 10


def setup_stress_db():
    """Create full schema for stress testing."""
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    
    conn.executescript("""
        CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            worker_id TEXT,
            lane TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            goal TEXT NOT NULL,
            priority TEXT DEFAULT 'normal',
            effort_rating INTEGER DEFAULT 1,
            status_updated_at INTEGER DEFAULT (strftime('%s', 'now')),
            created_at INTEGER DEFAULT (strftime('%s', 'now'))
        );
        
        CREATE TABLE worker_health (
            worker_id TEXT PRIMARY KEY,
            lane TEXT NOT NULL,
            tier TEXT DEFAULT 'standard',
            capacity_limit INTEGER DEFAULT 3,
            status TEXT DEFAULT 'online',
            active_tasks INTEGER DEFAULT 0,
            priority_score INTEGER DEFAULT 50,
            last_seen INTEGER DEFAULT 0
        );
        
        CREATE TABLE task_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER,
            status TEXT,
            worker_id TEXT,
            timestamp INTEGER,
            details TEXT
        );
        
        CREATE TABLE task_history_archive (
            id INTEGER PRIMARY KEY,
            task_id INTEGER,
            status TEXT,
            worker_id TEXT,
            timestamp INTEGER,
            details TEXT
        );
        
        CREATE TABLE task_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER,
            role TEXT,
            msg_type TEXT,
            content TEXT,
            created_at INTEGER
        );
    """)
    
    # Seed workers
    for lane in ['backend', 'frontend', 'qa']:
        conn.execute("""
            INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, last_seen)
            VALUES (?, ?, 'senior', 5, 'online', ?)
        """, (f"@{lane}-senior", lane, int(time.time())))
        
        for i in range(2):
            conn.execute("""
                INSERT INTO worker_health (worker_id, lane, tier, capacity_limit, status, last_seen)
                VALUES (?, ?, 'standard', 3, 'online', ?)
            """, (f"@{lane}-{i+1}", lane, int(time.time())))
    
    conn.commit()
    vibe_controller.invalidate_worker_cache()
    return conn


def test_cache_stress():
    """Test cache under high query load."""
    print("\n🔥 Stress Test: Cache Performance")
    
    conn = setup_stress_db()
    vibe_controller.metrics["cache_hits"] = 0
    vibe_controller.metrics["cache_misses"] = 0
    
    iterations = 1000
    lanes = ['backend', 'frontend', 'qa']
    
    start = time.time()
    for _ in range(iterations):
        lane = random.choice(lanes)
        vibe_controller.get_cached_workers(conn, lane)
    elapsed = time.time() - start
    
    hits = vibe_controller.metrics["cache_hits"]
    misses = vibe_controller.metrics["cache_misses"]
    hit_rate = (hits / (hits + misses)) * 100
    qps = iterations / elapsed
    
    conn.close()
    
    print(f"   Iterations: {iterations}")
    print(f"   Time: {elapsed:.2f}s")
    print(f"   QPS: {qps:.0f}")
    print(f"   Cache Hits: {hits} ({hit_rate:.1f}%)")
    print(f"   Cache Misses: {misses}")
    
    assert hit_rate > 90, f"Cache hit rate too low: {hit_rate}%"
    print("✅ PASS: Cache stress test (>90% hit rate)")


def test_saturation_stress():
    """Test saturation detection under load."""
    print("\n🔥 Stress Test: Saturation Detection")
    
    conn = setup_stress_db()
    vibe_controller.metrics["saturation_events"] = 0
    
    # Saturate backend pool
    conn.execute("UPDATE worker_health SET active_tasks = capacity_limit WHERE lane = 'backend'")
    conn.commit()
    
    # Check saturation multiple times
    for _ in range(100):
        vibe_controller.check_saturation(conn, 'backend')
    
    events = vibe_controller.metrics["saturation_events"]
    conn.close()
    
    print(f"   Saturation checks: 100")
    print(f"   Events recorded: {events}")
    
    assert events == 100, f"Expected 100 saturation events, got {events}"
    print("✅ PASS: Saturation detection stress")


def test_auto_scale_stress():
    """Test auto-scaler under rapid provisioning."""
    print("\n🔥 Stress Test: Auto-Scaler")
    
    conn = setup_stress_db()
    vibe_controller.metrics["auto_scale_events"] = 0
    
    # Clear any existing auto-workers
    conn.execute("DELETE FROM worker_health WHERE worker_id LIKE '@backend-auto-%'")
    conn.commit()
    
    provisioned = []
    rejected = 0
    
    # Try to provision MAX + 5 workers
    for _ in range(vibe_controller.MAX_AUTO_SCALE_WORKERS + 5):
        new_id = vibe_controller.provision_virtual_worker(conn, 'backend')
        if new_id:
            provisioned.append(new_id)
        else:
            rejected += 1
    
    events = vibe_controller.metrics["auto_scale_events"]
    conn.close()
    
    print(f"   Provisioned: {len(provisioned)}")
    print(f"   Rejected (at limit): {rejected}")
    print(f"   Scale events: {events}")
    
    assert len(provisioned) == vibe_controller.MAX_AUTO_SCALE_WORKERS, f"Expected {vibe_controller.MAX_AUTO_SCALE_WORKERS}, got {len(provisioned)}"
    assert rejected == 5, f"Expected 5 rejected, got {rejected}"
    print("✅ PASS: Auto-scaler respects limits")


def test_scoring_stress():
    """Test scoring under many workers."""
    print("\n🔥 Stress Test: Scoring Performance")
    
    # Generate 100 workers
    workers = []
    for i in range(100):
        workers.append({
            'worker_id': f"@backend-{i}",
            'tier': 'senior' if i < 10 else 'standard',
            'capacity_limit': 5 if i < 10 else 3,
            'active_tasks': random.randint(0, 3),
            'priority_score': random.randint(30, 100)
        })
    
    iterations = 10000
    efforts = [1, 2, 3, 4, 5]
    priorities = ['normal', 'high', 'critical']
    
    start = time.time()
    for _ in range(iterations):
        worker = random.choice(workers)
        effort = random.choice(efforts)
        priority = random.choice(priorities)
        vibe_controller.calculate_worker_score(worker, effort, priority)
    elapsed = time.time() - start
    
    ops = iterations / elapsed
    
    print(f"   Iterations: {iterations}")
    print(f"   Time: {elapsed:.3f}s")
    print(f"   Ops/sec: {ops:.0f}")
    
    assert ops > 50000, f"Scoring too slow: {ops} ops/sec"
    print("✅ PASS: Scoring performance (>50k ops/sec)")


def test_archival_stress():
    """Test archival with large history."""
    print("\n🔥 Stress Test: History Archival")
    
    conn = setup_stress_db()
    
    # Insert 1000 old records
    old_ts = int(time.time()) - (30 * 86400)  # 30 days ago
    for i in range(1000):
        conn.execute("""
            INSERT INTO task_history (task_id, status, worker_id, timestamp, details)
            VALUES (?, 'completed', '@backend-1', ?, 'Old record')
        """, (i, old_ts))
    
    # Insert 100 recent records
    for i in range(100):
        conn.execute("""
            INSERT INTO task_history (task_id, status, worker_id, timestamp, details)
            VALUES (?, 'completed', '@backend-1', ?, 'New record')
        """, (i + 1000, int(time.time())))
    conn.commit()
    
    start = time.time()
    archived = vibe_controller.archive_old_history(conn, days=7)
    elapsed = time.time() - start
    
    history_count = conn.execute("SELECT COUNT(*) as c FROM task_history").fetchone()['c']
    archive_count = conn.execute("SELECT COUNT(*) as c FROM task_history_archive").fetchone()['c']
    conn.close()
    
    print(f"   Archived: {archived}")
    print(f"   Remaining in history: {history_count}")
    print(f"   In archive: {archive_count}")
    print(f"   Time: {elapsed:.3f}s")
    
    assert archived == 1000
    assert history_count == 100
    assert archive_count == 1000
    print("✅ PASS: Archival handles 1000+ records")


def print_monitoring_summary():
    """Print monitoring metrics summary."""
    print("\n" + "=" * 60)
    print("📊 V3.3 MONITORING SUMMARY")
    print("=" * 60)
    
    print(f"""
Metrics Tracked:
  • cache_hits: {vibe_controller.metrics.get('cache_hits', 0)}
  • cache_misses: {vibe_controller.metrics.get('cache_misses', 0)}
  • saturation_events: {vibe_controller.metrics.get('saturation_events', 0)}
  • auto_scale_events: {vibe_controller.metrics.get('auto_scale_events', 0)}

Recommendations:
  • Cache hit rate should stay > 80%
  • Saturation events trigger review of worker pool sizing
  • Auto-scale events indicate load spikes
  • Review archived history monthly

Production Monitoring:
  1. Check vibe_controller.health file for system status
  2. Monitor metrics dict via Prometheus scraping
  3. Set alerts for saturation_events > 10/hour
""")


def cleanup():
    try:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
    except:
        pass


if __name__ == "__main__":
    print("=" * 60)
    print("🔥 VIBE CONTROLLER V3.3 STRESS TESTS")
    print("=" * 60)
    
    try:
        test_cache_stress()
        test_saturation_stress()
        test_auto_scale_stress()
        test_scoring_stress()
        test_archival_stress()
        print_monitoring_summary()
    finally:
        cleanup()
    
    print("=" * 60)
    print("✅ ALL STRESS TESTS PASSED")
    print("=" * 60)
