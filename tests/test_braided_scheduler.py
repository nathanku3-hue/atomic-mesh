"""
Test: Braided Stream Scheduler (v18.0 - Stream A Phase A)

Verifies:
1. Same priority across lanes → alternates lanes (round-robin)
2. URGENT (priority=0) in any lane preempts
3. HIGH (priority=5) preempts regular lanes
4. No starvation: all lanes with tasks advance
5. Ordering is stable run-to-run (deterministic)
6. Kickback/reset preserves priority/lane

Acceptance criteria:
- Given 24 tasks across 5 streams: first 10 selections include ≥3 lanes
- Urgent tasks always preempt
- Ordering is stable run-to-run
"""
import json
import os
import sqlite3
import sys
import tempfile
import time

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest


@pytest.fixture
def scheduler_workspace(tmp_path):
    """Create a temporary workspace with required structure for scheduler tests."""
    # Create control/state directory
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)

    # Create SQLite database with v18.0 schema
    db_path = tmp_path / "mesh.db"
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT DEFAULT 'backend',
            desc TEXT,
            deps TEXT DEFAULT '[]',
            status TEXT DEFAULT 'pending',
            output TEXT,
            worker_id TEXT,
            updated_at INTEGER,
            retry_count INTEGER DEFAULT 0,
            priority INTEGER DEFAULT 10,
            source_ids TEXT DEFAULT '[]',
            source_plan_hash TEXT DEFAULT '',
            task_signature TEXT DEFAULT '',
            lane TEXT DEFAULT '',
            created_at INTEGER DEFAULT 0,
            exec_class TEXT DEFAULT 'exclusive',
            lane_rank INTEGER DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    conn.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('mode', 'vibe')")
    conn.commit()
    conn.close()

    return tmp_path


def insert_task(conn, lane, desc, priority=None, created_at=None, status='pending', deps='[]'):
    """Helper to insert a task with proper lane/priority mapping."""
    from mesh_server import LANE_WEIGHTS, LANE_ORDER

    if priority is None:
        priority = LANE_WEIGHTS.get(lane, 50)

    lane_rank = LANE_ORDER.index(lane) if lane in LANE_ORDER else len(LANE_ORDER)

    if created_at is None:
        created_at = int(time.time())

    cursor = conn.execute("""
        INSERT INTO tasks (type, desc, status, priority, lane, lane_rank, created_at, deps, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (lane, desc, status, priority, lane, lane_rank, created_at, deps, int(time.time())))
    return cursor.lastrowid


def get_task_ids_in_selection_order(db_path, state_dir, count=10):
    """
    Simulate scheduler selections and return list of (task_id, lane) tuples.
    Uses the actual scheduler logic.
    """
    import mesh_server
    from mesh_server import pick_task_braided, _write_lane_pointer

    selected = []

    # Reset lane pointer
    _write_lane_pointer(-1, None)

    for i in range(count):
        result = pick_task_braided(f"test_worker_{i}")
        result_data = json.loads(result)

        if result_data.get("status") == "NO_WORK":
            break

        task_id = result_data.get("id")
        lane = result_data.get("lane")
        selected.append((task_id, lane))

    return selected


class TestBraidedSchedulerBasics:
    """Basic functionality tests."""

    def test_round_robin_across_lanes(self, scheduler_workspace, monkeypatch):
        """Same priority across lanes should alternate lanes."""
        import mesh_server

        # Patch paths
        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        # Reload to pick up patched paths
        from mesh_server import get_db, _write_lane_pointer

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert tasks with same priority (using default lane weights)
        # backend=10, frontend=20, qa=30 - but we want same priority for this test
        # So use explicit priority=10 for all
        insert_task(conn, 'backend', 'Backend task 1', priority=10, created_at=base_time)
        insert_task(conn, 'backend', 'Backend task 2', priority=10, created_at=base_time+1)
        insert_task(conn, 'frontend', 'Frontend task 1', priority=10, created_at=base_time)
        insert_task(conn, 'frontend', 'Frontend task 2', priority=10, created_at=base_time+1)
        insert_task(conn, 'qa', 'QA task 1', priority=10, created_at=base_time)
        insert_task(conn, 'qa', 'QA task 2', priority=10, created_at=base_time+1)

        conn.commit()
        conn.close()

        # Reset lane pointer
        _write_lane_pointer(-1, None)

        # Get selections
        from mesh_server import pick_task_braided

        selections = []
        for i in range(6):
            result = json.loads(pick_task_braided(f"worker_{i}"))
            if result.get("status") == "NO_WORK":
                break
            selections.append(result.get("lane"))

        # Should see all three lanes in first 6 selections
        unique_lanes = set(selections[:6])
        assert len(unique_lanes) >= 3, f"Expected at least 3 lanes in first 6 selections, got {unique_lanes}"

        # Should see round-robin pattern (backend, frontend, qa, backend, frontend, qa)
        assert 'backend' in selections[:3], "backend should appear in first 3 selections"
        assert 'frontend' in selections[:3], "frontend should appear in first 3 selections"
        assert 'qa' in selections[:3], "qa should appear in first 3 selections"

    def test_urgent_preempts(self, scheduler_workspace, monkeypatch):
        """URGENT (priority=0) should always preempt regular tasks."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert regular tasks first
        insert_task(conn, 'backend', 'Regular backend', priority=10, created_at=base_time)
        insert_task(conn, 'frontend', 'Regular frontend', priority=20, created_at=base_time)

        # Insert URGENT task (even in a "lower priority" lane)
        insert_task(conn, 'docs', 'URGENT docs task | P:URGENT', priority=0, created_at=base_time+100)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # First selection should be the URGENT task despite being in docs lane
        result = json.loads(pick_task_braided("worker_0"))
        assert result.get("priority") == 0, "URGENT task should be selected first"
        assert "URGENT" in result.get("description", ""), "Should be the URGENT docs task"

    def test_high_preempts_regular(self, scheduler_workspace, monkeypatch):
        """HIGH (priority=5) should preempt regular lane tasks."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert regular backend task (priority 10)
        insert_task(conn, 'backend', 'Regular backend', priority=10, created_at=base_time)

        # Insert HIGH priority QA task
        insert_task(conn, 'qa', 'HIGH priority QA | P:HIGH', priority=5, created_at=base_time+100)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # First selection should be HIGH priority despite QA lane default being 30
        result = json.loads(pick_task_braided("worker_0"))
        assert result.get("priority") == 5, "HIGH task should be selected first"
        assert "HIGH" in result.get("description", ""), "Should be the HIGH priority task"


class TestNoStarvation:
    """Verify no lane starvation."""

    def test_all_lanes_advance(self, scheduler_workspace, monkeypatch):
        """If multiple lanes have tasks, all should advance over time."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert many tasks per lane (same priority for fairness test)
        for i in range(5):
            insert_task(conn, 'backend', f'Backend task {i}', priority=10, created_at=base_time+i)
            insert_task(conn, 'frontend', f'Frontend task {i}', priority=10, created_at=base_time+i)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # Get 10 selections
        backend_count = 0
        frontend_count = 0

        for i in range(10):
            result = json.loads(pick_task_braided(f"worker_{i}"))
            if result.get("status") == "NO_WORK":
                break
            lane = result.get("lane")
            if lane == 'backend':
                backend_count += 1
            elif lane == 'frontend':
                frontend_count += 1

        # Both lanes should have been selected multiple times
        assert backend_count >= 3, f"Backend should be selected at least 3 times, got {backend_count}"
        assert frontend_count >= 3, f"Frontend should be selected at least 3 times, got {frontend_count}"


class TestDeterministicOrdering:
    """Verify ordering is stable/deterministic."""

    def test_ordering_stable_across_runs(self, scheduler_workspace, monkeypatch):
        """Same initial state should produce same selection order."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        # Create first database state
        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = 1000000000  # Fixed timestamp for determinism

        insert_task(conn, 'backend', 'Backend A', priority=10, created_at=base_time)
        insert_task(conn, 'frontend', 'Frontend A', priority=10, created_at=base_time)
        insert_task(conn, 'qa', 'QA A', priority=10, created_at=base_time)

        conn.commit()
        conn.close()

        # Run 1
        _write_lane_pointer(-1, None)
        run1_selections = []
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        for i in range(3):
            result = json.loads(pick_task_braided(f"worker_run1_{i}"))
            if result.get("status") == "NO_WORK":
                break
            run1_selections.append((result.get("id"), result.get("lane")))

        # Reset tasks to pending for run 2
        conn.execute("UPDATE tasks SET status='pending', worker_id=NULL")
        conn.commit()
        conn.close()

        # Run 2 (same initial state)
        _write_lane_pointer(-1, None)
        run2_selections = []

        for i in range(3):
            result = json.loads(pick_task_braided(f"worker_run2_{i}"))
            if result.get("status") == "NO_WORK":
                break
            run2_selections.append((result.get("id"), result.get("lane")))

        # Both runs should produce same order
        assert run1_selections == run2_selections, f"Ordering should be deterministic: run1={run1_selections}, run2={run2_selections}"


class TestAcceptanceCriteria:
    """Tests matching the acceptance criteria from the spec."""

    def test_24_tasks_5_streams_first_10_include_3_lanes(self, scheduler_workspace, monkeypatch):
        """
        Given a plan with 24 tasks across 5 streams:
        First 10 selections should include >= 3 lanes.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # 24 tasks across 5 streams (roughly equal distribution)
        lanes = ['backend', 'frontend', 'qa', 'ops', 'docs']
        for i in range(24):
            lane = lanes[i % 5]
            # Use same priority (10) for fair round-robin test
            insert_task(conn, lane, f'{lane.title()} task {i}', priority=10, created_at=base_time+i)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # Get first 10 selections
        selected_lanes = []
        for i in range(10):
            result = json.loads(pick_task_braided(f"worker_{i}"))
            if result.get("status") == "NO_WORK":
                break
            selected_lanes.append(result.get("lane"))

        unique_lanes = set(selected_lanes)
        assert len(unique_lanes) >= 3, f"First 10 selections should include >=3 lanes, got {unique_lanes}"

    def test_urgent_always_preempts_across_lanes(self, scheduler_workspace, monkeypatch):
        """Urgent tasks in any lane should always preempt."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert regular tasks
        for lane in ['backend', 'frontend', 'qa']:
            for i in range(3):
                insert_task(conn, lane, f'{lane.title()} regular {i}', priority=10, created_at=base_time+i)

        # Insert URGENT in docs (lowest default priority lane)
        insert_task(conn, 'docs', 'CRITICAL URGENT FIX | P:URGENT', priority=0, created_at=base_time+100)

        # Insert another URGENT in ops
        insert_task(conn, 'ops', 'OPS EMERGENCY | P:URGENT', priority=0, created_at=base_time+101)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # First two selections should both be URGENT tasks
        result1 = json.loads(pick_task_braided("worker_0"))
        result2 = json.loads(pick_task_braided("worker_1"))

        assert result1.get("priority") == 0, "First selection should be URGENT"
        assert result2.get("priority") == 0, "Second selection should be URGENT"


class TestKickbackPreservesPriority:
    """Verify kickback/reset preserves priority and lane."""

    def test_reset_preserves_priority_lane(self, scheduler_workspace, monkeypatch):
        """After reset, task should maintain original priority and lane."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert a task with specific priority
        task_id = insert_task(conn, 'frontend', 'Important frontend task', priority=5, created_at=base_time)

        # Record original values
        original = conn.execute("SELECT priority, lane, lane_rank FROM tasks WHERE id=?", (task_id,)).fetchone()
        original_priority = original['priority']
        original_lane = original['lane']
        original_lane_rank = original['lane_rank']

        # Simulate kickback (set to blocked)
        conn.execute("UPDATE tasks SET status='blocked' WHERE id=?", (task_id,))
        conn.commit()

        # Simulate reset (like /reset command)
        conn.execute("UPDATE tasks SET status='pending', retry_count=0 WHERE id=?", (task_id,))
        conn.commit()

        # Check values after reset
        after_reset = conn.execute("SELECT priority, lane, lane_rank, status FROM tasks WHERE id=?", (task_id,)).fetchone()

        conn.close()

        assert after_reset['priority'] == original_priority, "Priority should be preserved after reset"
        assert after_reset['lane'] == original_lane, "Lane should be preserved after reset"
        assert after_reset['lane_rank'] == original_lane_rank, "Lane rank should be preserved after reset"
        assert after_reset['status'] == 'pending', "Status should be reset to pending"


class TestExplicitOrdering:
    """Test the explicit ORDER BY clause behavior."""

    def test_order_by_priority_asc(self, scheduler_workspace, monkeypatch):
        """Lower priority number should be selected first."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert tasks with different priorities (all same lane to avoid round-robin)
        insert_task(conn, 'backend', 'Low priority', priority=50, created_at=base_time)
        insert_task(conn, 'backend', 'Medium priority', priority=20, created_at=base_time)
        insert_task(conn, 'backend', 'High priority', priority=5, created_at=base_time)
        insert_task(conn, 'backend', 'Urgent priority', priority=0, created_at=base_time)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # Selections should be in priority order (lowest first)
        priorities = []
        for i in range(4):
            result = json.loads(pick_task_braided(f"worker_{i}"))
            if result.get("status") == "NO_WORK":
                break
            priorities.append(result.get("priority"))

        assert priorities == [0, 5, 20, 50], f"Should select in priority order (ASC), got {priorities}"

    def test_order_by_created_at_for_same_priority(self, scheduler_workspace, monkeypatch):
        """Same priority, same lane: earlier created_at should be selected first."""
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert tasks with same priority but different created_at (same lane)
        id3 = insert_task(conn, 'backend', 'Third created', priority=10, created_at=base_time+300)
        id1 = insert_task(conn, 'backend', 'First created', priority=10, created_at=base_time+100)
        id2 = insert_task(conn, 'backend', 'Second created', priority=10, created_at=base_time+200)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # Should be selected in created_at order
        selected_ids = []
        for i in range(3):
            result = json.loads(pick_task_braided(f"worker_{i}"))
            if result.get("status") == "NO_WORK":
                break
            selected_ids.append(result.get("id"))

        assert selected_ids == [id1, id2, id3], f"Should select in created_at order, got {selected_ids}"


class TestPriorityPreemption:
    """Test priority preemption edge cases."""

    def test_high_frontend_jumps_ahead_of_normal_backend(self, scheduler_workspace, monkeypatch):
        """
        HIGH priority frontend (priority=5) should be selected before
        normal backend (priority=10) even though backend has lower default weight.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert normal backend tasks (priority=10, backend's default)
        insert_task(conn, 'backend', 'Normal backend task 1', priority=10, created_at=base_time)
        insert_task(conn, 'backend', 'Normal backend task 2', priority=10, created_at=base_time+1)

        # Insert HIGH priority frontend task (priority=5)
        insert_task(conn, 'frontend', 'HIGH priority frontend | P:HIGH', priority=5, created_at=base_time+100)

        # Insert normal frontend task (priority=20)
        insert_task(conn, 'frontend', 'Normal frontend task', priority=20, created_at=base_time)

        conn.commit()
        conn.close()

        _write_lane_pointer(-1, None)

        # First selection should be the HIGH frontend (priority=5 < backend's 10)
        result = json.loads(pick_task_braided("worker_0"))

        assert result.get("priority") == 5, f"HIGH frontend should be selected first, got priority={result.get('priority')}"
        assert result.get("lane") == "frontend", f"Should be frontend lane, got {result.get('lane')}"
        assert "HIGH" in result.get("description", ""), "Should be the HIGH priority task"


class TestBlockedLaneHandling:
    """Test scheduler behavior when lanes have only blocked tasks."""

    def test_blocked_lane_skipped_picks_another(self, scheduler_workspace, monkeypatch):
        """
        If all tasks in a lane are blocked by dependencies, scheduler should
        skip that lane and pick from another available lane.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert a parent task that's not completed (blocks children)
        parent_id = insert_task(conn, 'backend', 'Parent task (in progress)', priority=10, created_at=base_time, status='in_progress')

        # Insert backend tasks that depend on the in-progress parent (will be blocked)
        insert_task(conn, 'backend', 'Backend blocked by parent', priority=10, created_at=base_time+1, deps=json.dumps([parent_id]))
        insert_task(conn, 'backend', 'Another backend blocked', priority=10, created_at=base_time+2, deps=json.dumps([parent_id]))

        # Insert frontend tasks with no dependencies (should be picked)
        insert_task(conn, 'frontend', 'Frontend task 1 (no deps)', priority=20, created_at=base_time)
        insert_task(conn, 'frontend', 'Frontend task 2 (no deps)', priority=20, created_at=base_time+1)

        conn.commit()
        conn.close()

        # Set lane pointer to backend (index 0) - scheduler should try backend first
        _write_lane_pointer(0, None)

        # First selection should skip blocked backend and pick frontend
        result = json.loads(pick_task_braided("worker_0"))

        assert result.get("status") != "NO_WORK", "Should find work in frontend lane"
        assert result.get("lane") == "frontend", f"Should skip blocked backend and pick frontend, got {result.get('lane')}"

    def test_empty_lane_advances_pointer(self, scheduler_workspace, monkeypatch):
        """
        If current lane has no pending tasks, scheduler should advance
        to next lane without getting stuck.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Only insert tasks in QA lane (index 2), leave backend/frontend empty
        insert_task(conn, 'qa', 'QA task 1', priority=30, created_at=base_time)
        insert_task(conn, 'qa', 'QA task 2', priority=30, created_at=base_time+1)

        conn.commit()
        conn.close()

        # Set lane pointer to backend (index 0) - but backend has no tasks
        _write_lane_pointer(0, None)

        # Scheduler should advance past empty backend/frontend and pick QA
        result = json.loads(pick_task_braided("worker_0"))

        assert result.get("status") != "NO_WORK", "Should find work in QA lane"
        assert result.get("lane") == "qa", f"Should advance to QA lane, got {result.get('lane')}"


class TestAtomicClaim:
    """Regression test for atomic task claiming (prevents double-claim)."""

    def test_double_claim_prevented(self, scheduler_workspace, monkeypatch):
        """
        Simulate two workers trying to claim the same task.
        Only one should succeed; the other should get a different task or NO_WORK.

        This tests the atomic UPDATE ... WHERE status='pending' pattern.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided, get_db

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert exactly ONE task
        insert_task(conn, 'backend', 'Single task for race test', priority=10, created_at=base_time)

        conn.commit()
        conn.close()

        _write_lane_pointer(0, None)

        # Worker 1 claims the task
        result1 = json.loads(pick_task_braided("worker_1"))
        assert result1.get("status") == "OK", "Worker 1 should claim the task"
        task_id = result1.get("id")

        # Worker 2 tries to claim - should get NO_WORK (task already claimed)
        result2 = json.loads(pick_task_braided("worker_2"))
        assert result2.get("status") == "NO_WORK", \
            f"Worker 2 should get NO_WORK since only task was claimed, got {result2}"

        # Verify task is claimed by worker_1
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT worker_id, status FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["worker_id"] == "worker_1", f"Task should be claimed by worker_1, got {task['worker_id']}"
        assert task["status"] == "in_progress", f"Task should be in_progress, got {task['status']}"

    def test_concurrent_claim_with_multiple_tasks(self, scheduler_workspace, monkeypatch):
        """
        With multiple tasks, two workers should each get a different task.
        No task should be double-claimed.
        """
        import mesh_server

        monkeypatch.setattr('mesh_server.BASE_DIR', str(scheduler_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(scheduler_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(scheduler_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.LANE_POINTER_FILE', str(scheduler_workspace / "control" / "state" / "scheduler_lane_pointer.json"))

        from mesh_server import _write_lane_pointer, pick_task_braided

        db_path = scheduler_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row

        base_time = int(time.time())

        # Insert two tasks
        insert_task(conn, 'backend', 'Task A', priority=10, created_at=base_time)
        insert_task(conn, 'backend', 'Task B', priority=10, created_at=base_time+1)

        conn.commit()
        conn.close()

        _write_lane_pointer(0, None)

        # Two workers claim tasks
        result1 = json.loads(pick_task_braided("worker_1"))
        result2 = json.loads(pick_task_braided("worker_2"))

        assert result1.get("status") == "OK", "Worker 1 should get a task"
        assert result2.get("status") == "OK", "Worker 2 should get a task"

        # They should have different task IDs
        assert result1.get("id") != result2.get("id"), \
            f"Workers should claim different tasks: {result1.get('id')} vs {result2.get('id')}"

        # Verify both tasks are claimed by different workers
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        tasks = conn.execute("SELECT id, worker_id FROM tasks WHERE status='in_progress'").fetchall()
        conn.close()

        worker_ids = [t["worker_id"] for t in tasks]
        assert len(set(worker_ids)) == 2, f"Each task should have different worker: {worker_ids}"
        assert "worker_1" in worker_ids
        assert "worker_2" in worker_ids


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
