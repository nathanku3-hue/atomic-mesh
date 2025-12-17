"""
Test: /go command (v18.5 - Braided Scheduler Integration)

Verifies:
1. pick_task_braided returns NO_WORK when no tasks exist
2. pick_task_braided picks task and marks IN_PROGRESS when tasks exist
3. /g alias resolves to /go command

Acceptance criteria:
- /go with no tasks → "NO_WORK" status (friendly message in UI)
- /go with tasks → picks task via braided scheduler
- /g alias works
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
def go_workspace(tmp_path, monkeypatch):
    """Create a temporary workspace for /go command tests."""
    # Create required directories
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)
    docs_dir = tmp_path / "docs"
    docs_dir.mkdir(parents=True)

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
            lane_rank INTEGER DEFAULT 0,
            risk TEXT DEFAULT 'LOW',
            qa_status TEXT DEFAULT 'pending',
            auditor_status TEXT DEFAULT 'pending',
            auditor_feedback TEXT DEFAULT '[]',
            strictness TEXT DEFAULT 'NORMAL',
            notes TEXT DEFAULT ''
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

    # Patch environment
    monkeypatch.setenv("MESH_BASE_DIR", str(tmp_path))
    monkeypatch.setenv("ATOMIC_MESH_DB", str(db_path))

    # Force mesh_server to reload with new paths
    if "mesh_server" in sys.modules:
        del sys.modules["mesh_server"]

    return tmp_path


class TestGoCommandNoTasks:
    """Test /go behavior when no tasks exist."""

    def test_no_work_when_empty(self, go_workspace, monkeypatch):
        """pick_task_braided returns NO_WORK when task table is empty."""
        from mesh_server import pick_task_braided

        result = json.loads(pick_task_braided("test_worker"))
        assert result["status"] == "NO_WORK"

    def test_no_work_when_all_completed(self, go_workspace, monkeypatch):
        """pick_task_braided returns NO_WORK when all tasks are completed."""
        from mesh_server import pick_task_braided, get_db

        # Insert a completed task
        with get_db() as conn:
            conn.execute("""
                INSERT INTO tasks (type, desc, status, lane, priority, lane_rank, created_at)
                VALUES ('backend', 'Test task', 'completed', 'backend', 10, 0, ?)
            """, (int(time.time()),))
            conn.commit()

        result = json.loads(pick_task_braided("test_worker"))
        assert result["status"] == "NO_WORK"


class TestGoCommandWithTasks:
    """Test /go behavior when pending tasks exist."""

    def test_picks_pending_task(self, go_workspace, monkeypatch):
        """pick_task_braided picks a pending task and marks IN_PROGRESS."""
        from mesh_server import pick_task_braided, get_db

        # Insert a pending task
        with get_db() as conn:
            conn.execute("""
                INSERT INTO tasks (type, desc, status, lane, priority, lane_rank, created_at)
                VALUES ('backend', 'Test pending task', 'pending', 'backend', 10, 0, ?)
            """, (int(time.time()),))
            conn.commit()

        result = json.loads(pick_task_braided("test_worker"))

        assert result["status"] == "OK"
        assert result["id"] == 1
        assert result["description"] == "Test pending task"
        assert result["lane"] == "backend"

        # Verify task is now IN_PROGRESS
        with get_db() as conn:
            task = conn.execute("SELECT status FROM tasks WHERE id = 1").fetchone()
            assert task["status"] == "in_progress"

    def test_returns_task_details(self, go_workspace, monkeypatch):
        """pick_task_braided returns expected task fields."""
        from mesh_server import pick_task_braided, get_db

        with get_db() as conn:
            conn.execute("""
                INSERT INTO tasks (type, desc, status, lane, priority, lane_rank, created_at, exec_class)
                VALUES ('frontend', 'UI component', 'pending', 'frontend', 20, 1, ?, 'parallel')
            """, (int(time.time()),))
            conn.commit()

        result = json.loads(pick_task_braided("test_worker"))

        assert result["status"] == "OK"
        assert result["type"] == "frontend"
        assert result["lane"] == "frontend"
        assert result["exec_class"] == "parallel"
        assert "preempted" in result


class TestGoCommandAlias:
    """Test that /g alias is registered for /go."""

    def test_g_alias_registered(self, go_workspace):
        """Verify 'g' is in the alias list for 'go' command."""
        # Read control_panel.ps1 and check the alias definition
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        control_panel_path = os.path.join(repo_root, "control_panel.ps1")

        with open(control_panel_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Check that 'g' is in the alias list for 'go'
        # Pattern: "go" = @{ ... Alias = @("continue", "c", "g", "run") ...
        assert '"g"' in content or "'g'" in content, "/g alias not found in command registry"
        assert 'Alias = @("continue", "c", "g", "run")' in content or "Alias = @('continue', 'c', 'g', 'run')" in content


class TestGoCommandPriority:
    """Test /go respects task priority."""

    def test_urgent_preempts(self, go_workspace, monkeypatch):
        """URGENT priority (0) tasks are picked first regardless of lane."""
        from mesh_server import pick_task_braided, get_db, _write_lane_pointer

        # Reset lane pointer
        _write_lane_pointer(-1, None)

        with get_db() as conn:
            # Insert regular task first
            conn.execute("""
                INSERT INTO tasks (type, desc, status, lane, priority, lane_rank, created_at)
                VALUES ('backend', 'Regular task', 'pending', 'backend', 10, 0, ?)
            """, (int(time.time()),))

            # Insert urgent task second (should be picked first)
            conn.execute("""
                INSERT INTO tasks (type, desc, status, lane, priority, lane_rank, created_at)
                VALUES ('frontend', 'URGENT task', 'pending', 'frontend', 0, 1, ?)
            """, (int(time.time()) + 1,))
            conn.commit()

        result = json.loads(pick_task_braided("test_worker"))

        assert result["status"] == "OK"
        assert result["description"] == "URGENT task"
        assert result.get("preempted") == True
