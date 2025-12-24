"""
Test: Worker-Brain Complete System - Edge Cases (v24.2)

Enhanced coverage for:
- Rejection/escalation edge cases
- Evidence capture validation
- Admin tool edge conditions
- Concurrency scenarios
- Stale lease edge cases
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


def insert_task(conn, lane, desc, status='pending', worker_id=None, lease_expires_at=0, attempt_count=0):
    """Helper to insert a task."""
    now = int(time.time())
    cursor = conn.execute("""
        INSERT INTO tasks (type, desc, status, lane, worker_id, lease_expires_at, attempt_count, updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (lane, desc, status, lane, worker_id, lease_expires_at, attempt_count, now, now))
    conn.commit()
    return cursor.lastrowid


def setup_mesh_server(monkeypatch, comm_workspace):
    """Common monkeypatch setup for mesh_server."""
    import mesh_server
    monkeypatch.setattr('mesh_server.BASE_DIR', str(comm_workspace))
    monkeypatch.setattr('mesh_server.DB_PATH', str(comm_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DB_FILE', str(comm_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(comm_workspace / "control" / "state"))


# =============================================================================
# EDGE CASE: REJECTION & ESCALATION
# =============================================================================

class TestRejectionEdgeCases:
    """Edge cases for rejection workflow."""

    def test_rejection_logs_to_task_messages(self, comm_workspace, monkeypatch):
        """Rejection feedback should be logged in task_messages."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import reject_work, get_task_history

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='review_needed')
        conn.close()

        reject_work(task_id, "Missing error handling")

        history = json.loads(get_task_history(task_id))
        rejection_msgs = [m for m in history["messages"] if m["msg_type"] == "rejection"]
        
        assert len(rejection_msgs) >= 1
        assert "Missing error handling" in rejection_msgs[0]["content"]

    def test_escalation_creates_decision_entry(self, comm_workspace, monkeypatch):
        """Escalation should create a decision queue entry."""
        setup_mesh_server(monkeypatch, comm_workspace)
        monkeypatch.setattr('mesh_server.MAX_REJECTION_ATTEMPTS', 2)
        from mesh_server import reject_work

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Problematic task', status='review_needed', attempt_count=1)
        conn.close()

        result = json.loads(reject_work(task_id, "Fundamentally broken"))
        assert result["status"] == "ESCALATED"

        # Verify decision created with correct priority
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        decision = conn.execute("SELECT * FROM decisions WHERE question LIKE ?", (f"%{task_id}%",)).fetchone()
        conn.close()

        assert decision is not None
        assert decision["priority"] == "red"
        assert "rejected" in decision["question"].lower()

    def test_reject_with_reassign_false_clears_worker(self, comm_workspace, monkeypatch):
        """reject_work with reassign=False should clear worker assignment."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import reject_work

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='review_needed', worker_id='worker_1')
        conn.close()

        result = json.loads(reject_work(task_id, "Try different approach", reassign=False))
        assert result["status"] == "OK"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, worker_id FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "pending"
        assert task["worker_id"] is None


# =============================================================================
# EDGE CASE: EVIDENCE CAPTURE
# =============================================================================

class TestEvidenceEdgeCases:
    """Edge cases for evidence capture."""

    def test_evidence_with_empty_optional_fields(self, comm_workspace, monkeypatch):
        """Evidence should work with empty optional fields."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import submit_for_review_with_evidence

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='in_progress')
        conn.close()

        result = json.loads(submit_for_review_with_evidence(
            task_id,
            summary="Quick fix",
            artifacts="src/fix.py",
            # All optional evidence fields empty
        ))

        assert result["status"] == "OK"
        assert result["evidence"]["test_result"] == "SKIPPED"
        assert result["evidence"]["git_sha"] == ""
        assert result["evidence"]["files_changed"] == []

    def test_evidence_stored_and_readable(self, comm_workspace, monkeypatch):
        """Evidence JSON should be stored in worker_output and readable."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import submit_for_review_with_evidence

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='in_progress')
        conn.close()

        submit_for_review_with_evidence(
            task_id,
            summary="OAuth implementation",
            artifacts="src/auth.py",
            test_cmd="pytest tests/",
            test_result="PASS",
            git_sha="abc123",
            files_changed="src/auth.py, src/oauth.py"
        )

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT worker_output, test_result FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert "EVIDENCE:" in task["worker_output"]
        assert task["test_result"] == "PASS"
        
        # Parse evidence from worker_output
        evidence_json = task["worker_output"].split("EVIDENCE:")[1].strip()
        evidence = json.loads(evidence_json)
        assert evidence["git_sha"] == "abc123"
        assert len(evidence["files_changed"]) == 2


# =============================================================================
# EDGE CASE: ADMIN TOOLS
# =============================================================================

class TestAdminToolEdgeCases:
    """Edge cases for admin recovery tools."""

    def test_requeue_already_pending_task(self, comm_workspace, monkeypatch):
        """Requeueing a pending task should still work (idempotent)."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import requeue_task

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='pending')
        conn.close()

        result = json.loads(requeue_task(task_id, "Double-check"))
        assert result["status"] == "OK"
        assert result["previous_status"] == "pending"

    def test_force_unblock_non_blocked_task(self, comm_workspace, monkeypatch):
        """Force unblock on non-blocked task should warn."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import force_unblock

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='in_progress')
        conn.close()

        result = json.loads(force_unblock(task_id, "Admin request"))
        assert result["status"] == "WARN"

    def test_cancel_already_cancelled_task(self, comm_workspace, monkeypatch):
        """Canceling an already-cancelled task should warn."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import cancel_task

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='cancelled')
        conn.close()

        result = json.loads(cancel_task(task_id, "Duplicate cancel"))
        assert result["status"] == "WARN"

    def test_force_unblock_without_worker_sets_pending(self, comm_workspace, monkeypatch):
        """Force unblock on task without worker should set to pending."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import force_unblock

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Test task', status='blocked', worker_id=None)
        conn.execute("UPDATE tasks SET blocker_msg='Question' WHERE id=?", (task_id,))
        conn.commit()
        conn.close()

        result = json.loads(force_unblock(task_id, "Admin override"))
        assert result["status"] == "OK"
        assert result["new_status"] == "pending"


# =============================================================================
# EDGE CASE: STALE LEASE SWEEP
# =============================================================================

class TestStaleLeaseSweepEdgeCases:
    """Edge cases for stale lease sweeper."""

    def test_sweep_ignores_tasks_without_lease(self, comm_workspace, monkeypatch):
        """Tasks with lease_expires_at=0 should not be swept."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import sweep_stale_leases

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        # Task without lease (lease_expires_at=0)
        task_id = insert_task(conn, 'backend', 'No lease task', status='in_progress', 
                              worker_id='worker_1', lease_expires_at=0)
        conn.close()

        result = json.loads(sweep_stale_leases())
        assert result["requeued_count"] == 0
        assert task_id not in result["requeued_ids"]

    def test_sweep_handles_multiple_stale_tasks(self, comm_workspace, monkeypatch):
        """Sweep should handle multiple stale tasks in one call."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import sweep_stale_leases

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        expired_time = int(time.time()) - 100
        
        # Create 3 stale tasks
        stale_ids = []
        for i in range(3):
            task_id = insert_task(conn, 'backend', f'Stale task {i}', status='in_progress',
                                  worker_id=f'worker_{i}', lease_expires_at=expired_time)
            stale_ids.append(task_id)
        conn.close()

        result = json.loads(sweep_stale_leases())
        assert result["requeued_count"] == 3
        for task_id in stale_ids:
            assert task_id in result["requeued_ids"]

    def test_sweep_logs_to_task_messages(self, comm_workspace, monkeypatch):
        """Sweep should log lease expiry to task_messages."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import sweep_stale_leases, get_task_history

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        expired_time = int(time.time()) - 100
        task_id = insert_task(conn, 'backend', 'Stale task', status='in_progress',
                              worker_id='dead_worker', lease_expires_at=expired_time)
        conn.close()

        sweep_stale_leases()

        history = json.loads(get_task_history(task_id))
        lease_msgs = [m for m in history["messages"] if m["msg_type"] == "lease_expired"]
        
        assert len(lease_msgs) >= 1
        assert "dead_worker" in lease_msgs[0]["content"]


# =============================================================================
# CONCURRENCY: RACE CONDITIONS
# =============================================================================

class TestConcurrencyEdgeCases:
    """Test race condition handling."""

    def test_claim_race_only_one_wins(self, comm_workspace, monkeypatch):
        """When two workers try to claim, only one should succeed."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import claim_task

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Race task', status='pending')
        conn.close()

        # First claim
        result1 = json.loads(claim_task(task_id, "worker_1", 300))
        # Second claim
        result2 = json.loads(claim_task(task_id, "worker_2", 300))

        assert result1["status"] == "OK"
        assert result2["status"] == "CONFLICT"

        # Verify only one worker owns it
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT worker_id FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["worker_id"] == "worker_1"


# =============================================================================
# FULL WORKFLOW: REJECTION CYCLE
# =============================================================================

class TestFullRejectionCycle:
    """Test complete rejection and resubmission cycle."""

    def test_reject_resubmit_approve_cycle(self, comm_workspace, monkeypatch):
        """Full cycle: submit -> reject -> resubmit -> approve."""
        setup_mesh_server(monkeypatch, comm_workspace)
        from mesh_server import (
            claim_task, submit_for_review, reject_work, approve_work, get_task_history
        )

        db_path = comm_workspace / "mesh.db"
        conn = sqlite3.connect(str(db_path))
        task_id = insert_task(conn, 'backend', 'Feature X', status='pending')
        conn.close()

        # 1. Claim
        claim_task(task_id, "worker_1", 300)

        # 2. Submit v1
        submit_for_review(task_id, "First attempt", "src/v1.py", "worker_1")

        # 3. Reject
        result = json.loads(reject_work(task_id, "Missing tests"))
        assert result["attempt_count"] == 1

        # 4. Resubmit v2
        submit_for_review(task_id, "Added tests", "src/v2.py, tests/test_v2.py", "worker_1")

        # 5. Approve
        result = json.loads(approve_work(task_id, "LGTM"))
        assert result["status"] == "OK"

        # Verify final state
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        task = conn.execute("SELECT status, attempt_count FROM tasks WHERE id=?", (task_id,)).fetchone()
        conn.close()

        assert task["status"] == "completed"
        assert task["attempt_count"] == 1

        # Verify history has full conversation
        history = json.loads(get_task_history(task_id))
        msg_types = [m["msg_type"] for m in history["messages"]]
        
        assert msg_types.count("submission") == 2  # Two submissions
        assert "rejection" in msg_types
        assert "approval" in msg_types
