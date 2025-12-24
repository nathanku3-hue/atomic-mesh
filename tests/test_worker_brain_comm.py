"""
Test: Worker-Brain Complete System (v24.2)

Verifies all phases:
- Phase 1: Ownership + Leases
- Phase 3: Message logging
- Phase 4: Approve/Reject workflow with escalation
- Phase 5: Evidence capture
- Phase 6: Admin recovery tools
"""
import json
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest


@pytest.fixture
def comm_workspace(tmp_path):
    """Create a temporary workspace with full v24.2 schema."""
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)

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
            progress INTEGER DEFAULT 0,
            output TEXT,
            worker_id TEXT,
            lease_id TEXT DEFAULT '',
            updated_at INTEGER,
            retry_count INTEGER DEFAULT 0,
            priority INTEGER DEFAULT 10,
            files_changed TEXT DEFAULT '[]',
            test_result TEXT DEFAULT 'SKIPPED',
            strictness TEXT DEFAULT 'normal',
            auditor_status TEXT DEFAULT 'pending',
            auditor_feedback TEXT DEFAULT '[]',
            source_ids TEXT DEFAULT '[]',
            source_plan_hash TEXT DEFAULT '',
            task_signature TEXT DEFAULT '',
            archetype TEXT DEFAULT 'GENERIC',
            dependencies TEXT DEFAULT '[]',
            trace_reasoning TEXT DEFAULT '',
            override_justification TEXT DEFAULT '',
            review_decision TEXT DEFAULT '',
            review_notes TEXT DEFAULT '',
            risk TEXT DEFAULT 'LOW',
            qa_status TEXT DEFAULT 'NONE',
            lane TEXT DEFAULT '',
            lane_rank INTEGER DEFAULT 0,
            created_at INTEGER DEFAULT 0,
            exec_class TEXT DEFAULT 'exclusive',
            plan_key TEXT DEFAULT '',
            model_tier TEXT DEFAULT 'sonnet',
            heartbeat_at INTEGER DEFAULT 0,
            blocker_msg TEXT DEFAULT '',
            manager_feedback TEXT DEFAULT '',
            worker_output TEXT DEFAULT '',
            lease_expires_at INTEGER DEFAULT 0,
            attempt_count INTEGER DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS task_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            msg_type TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (task_id) REFERENCES tasks(id)
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS decisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            priority TEXT NOT NULL,
            question TEXT NOT NULL,
            context TEXT,
            status TEXT DEFAULT 'pending',
            answer TEXT,
            created_at INTEGER
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT)
    """)
    conn.execute("INSERT OR IGNORE INTO config (key, value) VALUES ('mode', 'vibe')")
    conn.commit()
    conn.close()

    return tmp_path


def insert_task(conn, lane, desc, status='pending', worker_id=None, lease_expires_at=0):
    """Helper to insert a task."""
    now = int(time.time())
    cursor = conn.execute("""
        INSERT INTO tasks (type, desc, status, lane, worker_id, lease_expires_at, updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (lane, desc, status, lane, worker_id, lease_expires_at, now, now))
    conn.commit()
    return cursor.lastrowid


# =============================================================================
# PHASE 4 TESTS: APPROVE/REJECT
# =============================================================================

class TestApproveWork:
    """Test approval workflow."""

    def test_approve_sets_completed(self, comm_workspace, monkeypatch):
        """approve_work should set status='completed'."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import approve_work

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Test task', status='review_needed')
        conn.close()

        result = json.loads(approve_work(task_id, "Looks good!"))
        assert result["status"] == "OK"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, review_decision FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "completed"
        assert task["review_decision"] == "approved"


class TestRejectWork:
    """Test rejection workflow."""

    def test_reject_increments_attempt(self, comm_workspace, monkeypatch):
        """reject_work should increment attempt_count."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import reject_work

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Test task', status='review_needed', worker_id='worker_1')
        conn.close()

        result = json.loads(reject_work(task_id, "Needs more tests"))
        assert result["status"] == "OK"
        assert result["attempt_count"] == 1

        # Reject again
        conn = sqlite3.connect(str(db_path))
        conn.execute("UPDATE tasks SET status='review_needed' WHERE id=?", (task_id,))
        conn.commit()
        conn.close()

        result = json.loads(reject_work(task_id, "Still needs work"))
        assert result["attempt_count"] == 2

    def test_reject_escalates_after_max_attempts(self, comm_workspace, monkeypatch):
        """After MAX_REJECTION_ATTEMPTS, should auto-escalate."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))
        monkeypatch.setattr('mesh_server.MAX_REJECTION_ATTEMPTS', 2)  # Lower for testing

        from mesh_server import reject_work

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Test task', status='review_needed')
        conn.execute("UPDATE tasks SET attempt_count=1 WHERE id=?", (task_id,))
        conn.commit()
        conn.close()

        result = json.loads(reject_work(task_id, "Too many issues"))
        assert result["status"] == "ESCALATED"
        assert result["attempt_count"] == 2

        # Verify decision was created
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        decision = conn.execute("SELECT * FROM decisions WHERE question LIKE ?", (f"%{task_id}%",)).fetchone()
        task = conn.execute("SELECT status FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert decision is not None
        assert task["status"] == "blocked"


# =============================================================================
# PHASE 5 TESTS: EVIDENCE CAPTURE
# =============================================================================

class TestEvidenceCapture:
    """Test enhanced submission with evidence."""

    def test_submit_with_evidence_captures_all_fields(self, comm_workspace, monkeypatch):
        """submit_for_review_with_evidence should capture structured evidence."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import submit_for_review_with_evidence

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Test task', status='in_progress', worker_id='worker_1')
        conn.close()

        result = json.loads(submit_for_review_with_evidence(
            task_id,
            summary="Implemented OAuth",
            artifacts="src/auth.py, src/oauth.py",
            worker_id="worker_1",
            test_cmd="pytest tests/test_auth.py",
            test_result="PASS",
            git_sha="abc123def",
            files_changed="src/auth.py, src/oauth.py"
        ))

        assert result["status"] == "OK"
        assert "evidence" in result
        assert result["evidence"]["test_result"] == "PASS"
        assert result["evidence"]["git_sha"] == "abc123def"
        assert len(result["evidence"]["files_changed"]) == 2


# =============================================================================
# PHASE 6 TESTS: ADMIN RECOVERY
# =============================================================================

class TestRequeueTask:
    """Test task requeue functionality."""

    def test_requeue_resets_to_pending(self, comm_workspace, monkeypatch):
        """requeue_task should reset to pending and clear worker."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import requeue_task

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Stuck task', status='in_progress', worker_id='dead_worker')
        conn.close()

        result = json.loads(requeue_task(task_id, "Worker crashed"))
        assert result["status"] == "OK"
        assert result["previous_status"] == "in_progress"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, worker_id FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "pending"
        assert task["worker_id"] is None


class TestForceUnblock:
    """Test force unblock functionality."""

    def test_force_unblock_clears_blocker(self, comm_workspace, monkeypatch):
        """force_unblock should clear blocker and set appropriate status."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import force_unblock

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task_id = insert_task(conn, 'backend', 'Blocked task', status='blocked', worker_id='worker_1')
        conn.execute("UPDATE tasks SET blocker_msg='Waiting forever' WHERE id=?", (task_id,))
        conn.commit()
        conn.close()

        result = json.loads(force_unblock(task_id, "Override"))
        assert result["status"] == "OK"
        assert result["new_status"] == "in_progress"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, blocker_msg FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "in_progress"
        assert task["blocker_msg"] is None


class TestCancelTask:
    """Test task cancellation."""

    def test_cancel_requires_reason(self, comm_workspace, monkeypatch):
        """cancel_task should require a reason."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import cancel_task

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Obsolete task', status='pending')
        conn.close()

        result = json.loads(cancel_task(task_id, ""))
        assert result["status"] == "ERROR"

        result = json.loads(cancel_task(task_id, "Feature no longer needed"))
        assert result["status"] == "OK"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "cancelled"


class TestSweepStaleLeases:
    """Test stale lease sweeper."""

    def test_sweep_requeues_expired_leases(self, comm_workspace, monkeypatch):
        """sweep_stale_leases should requeue tasks with expired leases."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import sweep_stale_leases

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        
        # Task with expired lease (10 seconds ago)
        expired_time = int(time.time()) - 10
        stale_id = insert_task(conn, 'backend', 'Stale task', status='in_progress', 
                               worker_id='dead_worker', lease_expires_at=expired_time)
        
        # Task with valid lease (future)
        valid_time = int(time.time()) + 300
        valid_id = insert_task(conn, 'backend', 'Valid task', status='in_progress',
                               worker_id='live_worker', lease_expires_at=valid_time)
        conn.close()

        result = json.loads(sweep_stale_leases())
        assert result["status"] == "OK"
        assert result["requeued_count"] == 1
        assert stale_id in result["requeued_ids"]
        assert valid_id not in result["requeued_ids"]

        # Verify stale task was requeued
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        stale = conn.execute("SELECT status, worker_id FROM tasks WHERE id=?", (stale_id,)).fetchone()
        valid = conn.execute("SELECT status, worker_id FROM tasks WHERE id=?", (valid_id,)).fetchone()
        conn.close()

        assert stale["status"] == "pending"
        assert stale["worker_id"] is None
        assert valid["status"] == "in_progress"
        assert valid["worker_id"] == "live_worker"


# =============================================================================
# INTEGRATION TESTS
# =============================================================================

class TestFullWorkflow:
    """Test complete workflow from claim to completion."""

    def test_claim_work_approve_flow(self, comm_workspace, monkeypatch):
        """Full happy path: claim -> work -> submit -> approve."""
        import mesh_server
        monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
        monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
        monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))

        from mesh_server import (
            claim_task, submit_for_review, approve_work, get_task_history
        )

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Implement feature X', status='pending')
        conn.close()

        # 1. Claim
        result = json.loads(claim_task(task_id, "worker_1", 300))
        assert result["status"] == "OK"

        # 2. Submit
        result = json.loads(submit_for_review(task_id, "Implemented feature X", "src/feature.py", "worker_1"))
        assert result["status"] == "OK"

        # 3. Approve
        result = json.loads(approve_work(task_id, "Great work!"))
        assert result["status"] == "OK"

        # Verify final state
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, review_decision FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "completed"
        assert task["review_decision"] == "approved"

        # Verify history
        history = json.loads(get_task_history(task_id))
        msg_types = [m["msg_type"] for m in history["messages"]]
        assert "claim" in msg_types
        assert "submission" in msg_types
        assert "approval" in msg_types
