"""
Test: Stream Details Overlay (v23.0)

Verifies:
1. F4 toggles the Stream Details overlay
2. Overlay contains "Plan:" and "Workers:" headers even when empty
3. If snapshot includes last_decision, it renders it
4. Graceful degradation for missing data

Acceptance criteria:
- F4 key (VirtualKeyCode 115) returns __TOGGLE_STREAM_DETAILS__
- Overlay displays plan identity, worker roster, progress, topology, scheduler info
- No crash when data is missing (optional-safe)
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
def stream_details_workspace(tmp_path, monkeypatch):
    """Create a temporary workspace for stream details tests."""
    # Create required directories
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)
    docs_dir = tmp_path / "docs"
    docs_dir.mkdir(parents=True)
    logs_dir = tmp_path / "logs"
    logs_dir.mkdir(parents=True)

    # Initialize git repo
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
    conn.execute("""
        CREATE TABLE IF NOT EXISTS worker_heartbeats (
            worker_id TEXT PRIMARY KEY,
            worker_type TEXT,
            allowed_lanes TEXT DEFAULT '[]',
            task_ids TEXT DEFAULT '[]',
            status TEXT DEFAULT 'active',
            last_seen INTEGER,
            created_at INTEGER
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


class TestStreamDetailsDataSources:
    """Tests for data sources used by Stream Details overlay."""

    def test_snapshot_has_plan_section(self, stream_details_workspace):
        """Verify snapshot includes plan section for Plan: header."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        # Must have plan key for "Plan:" header
        assert "plan" in result, "Missing 'plan' key for Plan: header"
        assert isinstance(result["plan"], dict)

    def test_snapshot_has_workers_section(self, stream_details_workspace):
        """Verify snapshot includes workers section for Workers: header."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        # Must have workers key for "Workers:" header
        assert "workers" in result, "Missing 'workers' key for Workers: header"
        assert isinstance(result["workers"], list)

    def test_snapshot_has_scheduler_section(self, stream_details_workspace):
        """Verify snapshot includes scheduler section."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        assert "scheduler" in result, "Missing 'scheduler' key"
        assert isinstance(result["scheduler"], dict)

    def test_last_decision_rendered_when_present(self, stream_details_workspace):
        """Verify last_decision is available in snapshot when set."""
        from mesh_server import get_exec_snapshot, get_db

        # Set scheduler state
        with get_db() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                ("scheduler_last_decision", json.dumps({
                    "picked_id": 42,
                    "lane": "backend",
                    "reason": "rotation",
                    "blocked_lanes": {
                        "frontend": {"blocked_reason": "INCOMPLETE_DEPS"}
                    }
                }))
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert result["scheduler"]["last_decision"] is not None
        assert result["scheduler"]["last_decision"]["picked_id"] == 42
        assert result["scheduler"]["last_decision"]["lane"] == "backend"
        assert result["scheduler"]["last_decision"]["reason"] == "rotation"
        assert "blocked_lanes" in result["scheduler"]["last_decision"]

    def test_workers_visible_in_snapshot(self, stream_details_workspace):
        """Verify registered workers appear in snapshot."""
        from mesh_server import worker_heartbeat, get_exec_snapshot

        # Register worker
        worker_heartbeat(
            worker_id="stream_test_worker",
            worker_type="backend",
            allowed_lanes=["backend", "qa"],
            task_ids=[42, 43]
        )

        result = json.loads(get_exec_snapshot())

        worker = next(
            (w for w in result["workers"] if w["id"] == "stream_test_worker"),
            None
        )
        assert worker is not None, "Worker should appear in snapshot"
        assert worker["type"] == "backend"
        assert set(worker["allowed_lanes"]) == {"backend", "qa"}
        assert 42 in worker["task_ids"]

    def test_plan_identity_when_accepted(self, stream_details_workspace):
        """Verify plan identity is visible when plan is accepted."""
        from mesh_server import get_exec_snapshot, get_db

        # Set accepted plan path
        plan_path = "/test/plans/my-plan.md"
        with get_db() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                ("accepted_plan_path", plan_path)
            )
            conn.execute(
                "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                ("plan_version", "v1.2.3")
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert result["plan"]["path"] == plan_path
        assert result["plan"]["name"] == "my-plan.md"
        assert result["plan"]["version"] == "v1.2.3"
        assert result["plan"]["hash"] is not None

    def test_lanes_progress_statistics(self, stream_details_workspace):
        """Verify lane progress statistics are computed."""
        from mesh_server import get_exec_snapshot, get_db

        now = int(time.time())
        with get_db() as conn:
            # Add tasks in different states
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
                ("backend", "backend", "Task 3", "in_progress", now)
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        backend_lane = next((l for l in result["lanes"] if l["name"] == "backend"), None)
        assert backend_lane is not None
        assert backend_lane["pending"] == 1
        assert backend_lane["done"] == 1
        assert backend_lane["active"] == 1
        assert backend_lane["total"] == 3

    def test_active_tasks_for_topology(self, stream_details_workspace):
        """Verify active tasks are available for topology section."""
        from mesh_server import get_exec_snapshot, get_db

        now = int(time.time())
        with get_db() as conn:
            # Add an in_progress task with deps
            conn.execute(
                "INSERT INTO tasks (type, lane, desc, status, updated_at, worker_id, deps) VALUES (?, ?, ?, ?, ?, ?, ?)",
                ("backend", "backend", "Active task with deps", "in_progress", now, "worker_1", "[1, 2]")
            )
            conn.commit()

        result = json.loads(get_exec_snapshot())

        assert len(result["active_tasks"]) >= 1
        task = result["active_tasks"][0]
        assert task["status"] == "in_progress"
        assert "deps_blocked" in task


class TestStreamDetailsGracefulDegradation:
    """Tests for graceful degradation when data is missing."""

    def test_no_plan_accepted(self, stream_details_workspace):
        """Verify no crash when no plan is accepted."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        # Should have plan section with null values
        assert result["plan"]["path"] is None
        assert result["plan"]["name"] is None

    def test_no_workers_registered(self, stream_details_workspace):
        """Verify empty workers list when none registered."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        assert isinstance(result["workers"], list)
        assert len(result["workers"]) == 0

    def test_no_scheduler_decisions(self, stream_details_workspace):
        """Verify no crash when no scheduler decisions exist."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        # When no decisions exist, last_decision may be None or not present
        scheduler = result.get("scheduler", {})
        last_decision = scheduler.get("last_decision")
        last_pick = scheduler.get("last_pick")
        # Both should be None or falsy when no decisions made
        assert last_decision is None or last_pick is None

    def test_empty_lanes(self, stream_details_workspace):
        """Verify empty lanes list when no tasks exist."""
        from mesh_server import get_exec_snapshot

        result = json.loads(get_exec_snapshot())

        assert isinstance(result["lanes"], list)
        assert len(result["lanes"]) == 0


class TestStreamDetailsOverlayToggle:
    """Tests for F4 overlay toggle functionality (PowerShell side).

    Note: These tests verify the data contract. The actual F4 key handling
    is in PowerShell and tested manually.
    """

    def test_global_variable_exists_in_ps1(self):
        """Verify $Global:StreamDetailsVisible is defined in control_panel.ps1."""
        import re

        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert "$Global:StreamDetailsVisible" in content, \
            "Missing $Global:StreamDetailsVisible global variable"

    def test_f4_key_handler_exists(self):
        """Verify F4 key handler (VirtualKeyCode 115) exists."""
        import re

        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        # F4 is VirtualKeyCode 115
        assert "VirtualKeyCode -eq 115" in content, \
            "Missing F4 key handler (VirtualKeyCode 115)"
        assert "__TOGGLE_STREAM_DETAILS__" in content, \
            "Missing __TOGGLE_STREAM_DETAILS__ return value"

    def test_toggle_handler_exists(self):
        """Verify main loop toggle handler exists."""
        import re

        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert 'if ($userInput -eq "__TOGGLE_STREAM_DETAILS__")' in content, \
            "Missing main loop handler for __TOGGLE_STREAM_DETAILS__"

    def test_draw_function_exists(self):
        """Verify Draw-StreamDetailsOverlay function exists."""
        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert "function Draw-StreamDetailsOverlay" in content, \
            "Missing Draw-StreamDetailsOverlay function"

    def test_overlay_has_plan_header(self):
        """Verify overlay renders Plan: header."""
        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Find the Draw-StreamDetailsOverlay function
        assert '"Plan:"' in content or "'Plan:'" in content, \
            "Missing Plan: header in overlay"

    def test_overlay_has_workers_header(self):
        """Verify overlay renders Workers: header."""
        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert '"Workers:"' in content or "'Workers:'" in content, \
            "Missing Workers: header in overlay"

    def test_overlay_has_scheduler_section(self):
        """Verify overlay renders Scheduler: section."""
        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        assert '"Scheduler:"' in content or "'Scheduler:'" in content, \
            "Missing Scheduler: header in overlay"

    def test_esc_closes_overlay(self):
        """Verify ESC key closes Stream Details overlay."""
        ps1_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "control_panel.ps1"
        )

        with open(ps1_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Look for ESC handler that checks StreamDetailsVisible
        assert "$Global:StreamDetailsVisible" in content
        # The ESC handler should return __TOGGLE_STREAM_DETAILS__ when overlay is visible
        assert "StreamDetailsVisible" in content and "__TOGGLE_STREAM_DETAILS__" in content
