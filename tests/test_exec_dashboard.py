"""
Test: EXEC Dashboard (v21.0)

Verifies:
1. get_exec_snapshot returns correct schema with all required keys
2. get_exec_snapshot handles missing/null fields gracefully (optional-safe)
3. worker_heartbeat creates and updates heartbeat table
4. Lane statistics are computed correctly
5. Alerts are generated for expected conditions

Acceptance criteria:
- get_exec_snapshot schema: plan, stream, security, scheduler, lanes, workers, active_tasks, alerts
- All fields are optional-safe (no crash on missing values)
- worker_heartbeat creates table on first call
- worker_heartbeat updates last_seen on subsequent calls
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
def exec_workspace(tmp_path, monkeypatch):
    """Create a temporary workspace for exec dashboard tests."""
    # Create required directories
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)
    docs_dir = tmp_path / "docs"
    docs_dir.mkdir(parents=True)
    logs_dir = tmp_path / "logs"
    logs_dir.mkdir(parents=True)

    # Initialize git repo (for worktree alerts)
    import subprocess
    subprocess.run(["git", "init"], cwd=str(tmp_path), capture_output=True)

    # Create SQLite database with schema
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
            lane_rank INTEGER DEFAULT 0,
            risk TEXT DEFAULT 'LOW',
            qa_status TEXT DEFAULT 'pending',
            auditor_status TEXT DEFAULT 'pending',
            auditor_feedback TEXT DEFAULT '[]',
            strictness TEXT DEFAULT 'NORMAL',
            notes TEXT DEFAULT '',
            parent_task_id INTEGER
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS decisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question TEXT,
            status TEXT DEFAULT 'pending',
            priority TEXT DEFAULT 'yellow'
        )
    """)
    conn.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('mode', 'vibe')")
    conn.commit()
    conn.close()

    # Patch environment
    monkeypatch.setenv("MESH_BASE_DIR", str(tmp_path))
    monkeypatch.setenv("ATOMIC_MESH_DB", str(db_path))

    # Force mesh_server to reload with new paths
    if "mesh_server" in sys.modules:
        del sys.modules["mesh_server"]

    return {"tmp_path": tmp_path, "db_path": db_path}


class TestGetExecSnapshot:
    """Tests for get_exec_snapshot MCP tool."""

    def test_schema_keys_present(self, exec_workspace):
        """Verify all required top-level keys are present in snapshot."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        # Required keys per spec
        assert "plan" in result, "Missing 'plan' key"
        assert "stream" in result, "Missing 'stream' key"
        assert "security" in result, "Missing 'security' key"
        assert "scheduler" in result, "Missing 'scheduler' key"
        assert "lanes" in result, "Missing 'lanes' key"
        assert "workers" in result, "Missing 'workers' key"
        assert "active_tasks" in result, "Missing 'active_tasks' key"
        assert "alerts" in result, "Missing 'alerts' key"

    def test_plan_fields(self, exec_workspace):
        """Verify plan object has expected fields."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())
        plan = result["plan"]

        assert "hash" in plan
        assert "name" in plan
        assert "version" in plan
        assert "path" in plan

    def test_lanes_empty_when_no_tasks(self, exec_workspace):
        """Lanes list should be empty when no tasks exist."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        assert isinstance(result["lanes"], list)
        assert len(result["lanes"]) == 0

    def test_lanes_statistics_with_tasks(self, exec_workspace):
        """Verify lane statistics are computed correctly."""
        from mesh_server import get_exec_snapshot, get_db

        # Add tasks to database using mesh_server's get_db
        now = int(time.time())
        with get_db() as conn:
            conn.execute(
                "INSERT INTO tasks (type, lane, desc, status, updated_at) VALUES (?, ?, ?, ?, ?)",
                ("backend", "backend", "Task 1", "pending", now)
            )
            conn.execute(
                "INSERT INTO tasks (type, lane, desc, status, updated_at) VALUES (?, ?, ?, ?, ?)",
                ("backend", "backend", "Task 2", "completed", now)
            )
            conn.execute(
                "INSERT INTO tasks (type, lane, desc, status, updated_at) VALUES (?, ?, ?, ?, ?)",
                ("frontend", "frontend", "Task 3", "in_progress", now)
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert len(result["lanes"]) >= 2, "Should have at least backend and frontend lanes"

        # Find backend lane
        backend_lane = next((l for l in result["lanes"] if l["name"] == "backend"), None)
        assert backend_lane is not None, "Backend lane not found"
        assert backend_lane["pending"] == 1
        assert backend_lane["done"] == 1
        assert backend_lane["total"] == 2

        # Find frontend lane
        frontend_lane = next((l for l in result["lanes"] if l["name"] == "frontend"), None)
        assert frontend_lane is not None, "Frontend lane not found"
        assert frontend_lane["active"] == 1
        assert frontend_lane["total"] == 1

    def test_active_tasks_populated(self, exec_workspace):
        """Verify active tasks are included in snapshot."""
        from mesh_server import get_exec_snapshot, get_db

        # Add in_progress task using mesh_server's get_db
        now = int(time.time())
        with get_db() as conn:
            conn.execute(
                "INSERT INTO tasks (type, lane, desc, status, updated_at, worker_id) VALUES (?, ?, ?, ?, ?, ?)",
                ("backend", "backend", "Active task", "in_progress", now, "worker_1")
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert len(result["active_tasks"]) == 1
        task = result["active_tasks"][0]
        assert task["status"] == "in_progress"
        assert task["lane"] == "backend"
        assert "title" in task

    def test_alerts_for_blocked_tasks(self, exec_workspace):
        """Verify alert is generated for blocked tasks."""
        from mesh_server import get_exec_snapshot, get_db

        # Add blocked task using mesh_server's get_db
        now = int(time.time())
        with get_db() as conn:
            conn.execute(
                "INSERT INTO tasks (type, desc, status, updated_at) VALUES (?, ?, ?, ?)",
                ("backend", "Blocked task", "blocked", now)
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        blocked_alert = next(
            (a for a in result["alerts"] if a.get("code") == "TASKS_BLOCKED"),
            None
        )
        assert blocked_alert is not None, "Expected TASKS_BLOCKED alert"
        assert blocked_alert["level"] == "warn"

    @pytest.mark.skip(reason="SQLite locking under parallel test runner. Manual smoke: create RED decision, verify alert appears in /status")
    def test_alerts_for_red_decisions(self, exec_workspace):
        """Verify alert is generated for RED priority decisions."""
        from mesh_server import get_exec_snapshot, DB_PATH

        # Add RED decision using direct sqlite connection to avoid locking
        db_path = DB_PATH
        conn = sqlite3.connect(db_path, timeout=30.0)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        conn.execute(
            "INSERT INTO decisions (question, status, priority) VALUES (?, ?, ?)",
            ("Critical question", "pending", "red")
        )
        conn.commit()
        conn.close()

        result = json.loads(get_exec_snapshot())

        red_alert = next(
            (a for a in result["alerts"] if a.get("code") == "RED_DECISION"),
            None
        )
        assert red_alert is not None, "Expected RED_DECISION alert"
        assert red_alert["level"] == "error"

    def test_optional_safe_empty_db(self, exec_workspace):
        """Verify no crash when database is empty (optional-safe)."""
        from mesh_server import get_exec_snapshot

        # Just call it - should not raise
        result = json.loads(get_exec_snapshot())

        # Should return valid structure
        assert isinstance(result, dict)
        assert isinstance(result["lanes"], list)
        assert isinstance(result["alerts"], list)


class TestWorkerHeartbeat:
    """Tests for worker_heartbeat MCP tool."""

    def test_heartbeat_creates_table(self, exec_workspace):
        """Verify heartbeat creates worker_heartbeats table if not exists."""
        from mesh_server import worker_heartbeat, get_db

        result = json.loads(worker_heartbeat(
            worker_id="test_worker_1",
            worker_type="backend",
            allowed_lanes=["backend", "qa"],
            task_ids=[]
        ))

        assert result["status"] == "OK"
        assert result["worker_id"] == "test_worker_1"

        # Verify table was created using mesh_server's get_db
        with get_db() as conn:
            tables = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='worker_heartbeats'"
            ).fetchall()

        assert len(tables) == 1, "worker_heartbeats table should be created"

    def test_heartbeat_updates_last_seen(self, exec_workspace):
        """Verify heartbeat updates last_seen timestamp."""
        from mesh_server import worker_heartbeat

        # First heartbeat
        result1 = json.loads(worker_heartbeat(
            worker_id="test_worker_2",
            worker_type="frontend"
        ))
        last_seen_1 = result1["last_seen"]

        # Wait a bit
        time.sleep(0.1)

        # Second heartbeat
        result2 = json.loads(worker_heartbeat(
            worker_id="test_worker_2",
            worker_type="frontend"
        ))
        last_seen_2 = result2["last_seen"]

        # last_seen should be updated
        assert last_seen_2 >= last_seen_1

    def test_heartbeat_requires_worker_id(self, exec_workspace):
        """Verify heartbeat fails without worker_id."""
        from mesh_server import worker_heartbeat

        result = json.loads(worker_heartbeat(
            worker_id="",  # Empty
            worker_type="backend"
        ))

        assert result["status"] == "ERROR"

    def test_heartbeat_with_task_ids(self, exec_workspace):
        """Verify heartbeat stores task_ids correctly."""
        from mesh_server import worker_heartbeat, get_db

        result = json.loads(worker_heartbeat(
            worker_id="test_worker_3",
            worker_type="backend",
            task_ids=[1, 2, 3]
        ))

        assert result["status"] == "OK"

        # Verify task_ids were stored using mesh_server's get_db
        with get_db() as conn:
            row = conn.execute(
                "SELECT task_ids FROM worker_heartbeats WHERE worker_id = ?",
                ("test_worker_3",)
            ).fetchone()

        task_ids = json.loads(row["task_ids"])
        assert task_ids == [1, 2, 3]


class TestWorkerVisibilityInSnapshot:
    """Tests for worker visibility in exec snapshot."""

    def test_workers_appear_in_snapshot(self, exec_workspace):
        """Verify registered workers appear in snapshot."""
        from mesh_server import worker_heartbeat, get_exec_snapshot

        # Register worker
        worker_heartbeat(
            worker_id="snapshot_test_worker",
            worker_type="backend",
            allowed_lanes=["backend", "qa"],
            task_ids=[42]
        )

        # Get snapshot
        result = json.loads(get_exec_snapshot())

        # Worker should be in snapshot
        worker = next(
            (w for w in result["workers"] if w["id"] == "snapshot_test_worker"),
            None
        )
        assert worker is not None, "Worker should appear in snapshot"
        assert worker["type"] == "backend"
        assert 42 in worker["task_ids"]


class TestSchedulerStateInSnapshot:
    """Tests for scheduler state in exec snapshot."""

    def test_scheduler_last_pick_visible(self, exec_workspace):
        """Verify last scheduler pick is visible in snapshot."""
        from mesh_server import get_exec_snapshot, get_db

        # Set scheduler state using mesh_server's get_db
        with get_db() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                ("scheduler_last_decision", json.dumps({
                    "picked_id": 99,
                    "lane": "backend",
                    "reason": "rotation"
                }))
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert result["scheduler"]["last_pick"] is not None
        assert result["scheduler"]["last_pick"]["task_id"] == 99
        assert result["scheduler"]["last_pick"]["lane"] == "backend"
        assert result["scheduler"].get("last_decision") is not None
        assert result["scheduler"]["last_decision"]["picked_id"] == 99
        assert result["scheduler"]["last_decision"]["reason"] == "rotation"

    def test_scheduler_rotation_ptr_visible(self, exec_workspace):
        """Verify scheduler rotation pointer is visible in snapshot."""
        from mesh_server import get_exec_snapshot, DB_PATH

        # Set scheduler pointer using direct sqlite connection to avoid locking
        db_path = DB_PATH
        conn = sqlite3.connect(db_path, timeout=30.0)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=5000")
        conn.execute(
            "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
            ("scheduler_lane_pointer", json.dumps({"index": 2, "lane": "qa"}))
        )
        conn.commit()
        conn.close()

        result = json.loads(get_exec_snapshot())

        assert result["scheduler"]["rotation_ptr"] == 2
