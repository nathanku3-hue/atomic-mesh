"""
Test: v18.2 Lane Activity Counts
Validates that Get-LaneActivityCounts SQL queries correctly count distinct lanes
for pending and active statuses.

Run: pytest tests/test_lane_counts.py -v
"""
import sqlite3
import tempfile
import os
import pytest


# Status arrays matching $Global:PendingStatuses and $Global:ActiveStatuses
PENDING_STATUSES = ["pending", "next", "planned"]
ACTIVE_STATUSES = ["in_progress", "running"]


def create_test_db(db_path: str) -> sqlite3.Connection:
    """Create a test database with the tasks table schema."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            type TEXT,
            lane TEXT,
            status TEXT,
            title TEXT,
            risk TEXT,
            qa_status TEXT
        )
    """)
    conn.commit()
    return conn


def insert_task(conn: sqlite3.Connection, task_id: str, task_type: str,
                lane: str, status: str, title: str = "Test Task"):
    """Insert a task into the test database."""
    conn.execute("""
        INSERT INTO tasks (id, type, lane, status, title)
        VALUES (?, ?, ?, ?, ?)
    """, (task_id, task_type, lane, status, title))
    conn.commit()


def get_lane_counts(conn: sqlite3.Connection,
                    pending_statuses: list, active_statuses: list) -> dict:
    """
    Replicate the SQL logic from Get-LaneActivityCounts.
    Uses LOWER(COALESCE(NULLIF(lane,''), type)) for lane expression.
    """
    lane_expr = "LOWER(COALESCE(NULLIF(lane,''), type))"

    # Build IN clauses
    pending_in = ",".join(f"'{s.lower()}'" for s in pending_statuses)
    active_in = ",".join(f"'{s.lower()}'" for s in active_statuses)

    # Query pending lanes
    cursor = conn.execute(f"""
        SELECT COUNT(DISTINCT {lane_expr}) as c
        FROM tasks
        WHERE LOWER(status) IN ({pending_in})
    """)
    pending_count = cursor.fetchone()["c"] or 0

    # Query active lanes
    cursor = conn.execute(f"""
        SELECT COUNT(DISTINCT {lane_expr}) as c
        FROM tasks
        WHERE LOWER(status) IN ({active_in})
    """)
    active_count = cursor.fetchone()["c"] or 0

    return {
        "pendingLaneCount": pending_count,
        "activeLaneCount": active_count
    }


class TestLaneActivityCounts:
    """Test suite for lane activity counting logic."""

    @pytest.fixture
    def temp_db(self):
        """Create a temporary database for testing."""
        fd, db_path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
        conn = create_test_db(db_path)
        yield conn, db_path
        conn.close()
        os.unlink(db_path)

    def test_empty_database_returns_zero_counts(self, temp_db):
        """Empty database should return 0 for both pending and active lanes."""
        conn, _ = temp_db
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 0
        assert counts["activeLaneCount"] == 0

    def test_pending_status_counted(self, temp_db):
        """Tasks with 'pending' status should be counted in pending lanes."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "pending")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 1
        assert counts["activeLaneCount"] == 0

    def test_next_status_counted_as_pending(self, temp_db):
        """Tasks with 'next' status should be counted in pending lanes."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "next")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 1
        assert counts["activeLaneCount"] == 0

    def test_planned_status_counted_as_pending(self, temp_db):
        """Tasks with 'planned' status should be counted in pending lanes."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "planned")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 1
        assert counts["activeLaneCount"] == 0

    def test_in_progress_status_counted_as_active(self, temp_db):
        """Tasks with 'in_progress' status should be counted in active lanes."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "in_progress")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 0
        assert counts["activeLaneCount"] == 1

    def test_running_status_counted_as_active(self, temp_db):
        """Tasks with 'running' status should be counted in active lanes."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "running")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 0
        assert counts["activeLaneCount"] == 1

    def test_completed_status_not_counted(self, temp_db):
        """Tasks with 'completed' status should not be counted in either bucket."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "completed")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 0
        assert counts["activeLaneCount"] == 0

    def test_distinct_lanes_counted_not_tasks(self, temp_db):
        """Multiple tasks in the same lane should count as 1 lane."""
        conn, _ = temp_db
        # 3 tasks in the same lane, all pending
        insert_task(conn, "T-001", "backend", "stream-a", "pending")
        insert_task(conn, "T-002", "backend", "stream-a", "pending")
        insert_task(conn, "T-003", "backend", "stream-a", "next")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        # Should be 1 lane, not 3 tasks
        assert counts["pendingLaneCount"] == 1

    def test_different_lanes_counted_separately(self, temp_db):
        """Tasks in different lanes should each contribute to the count."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "pending")
        insert_task(conn, "T-002", "frontend", "stream-b", "pending")
        insert_task(conn, "T-003", "qa", "stream-c", "pending")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 3

    def test_empty_lane_falls_back_to_type(self, temp_db):
        """Tasks with empty lane should use type as lane identifier."""
        conn, _ = temp_db
        # Lane is empty, should fall back to 'backend' type
        insert_task(conn, "T-001", "backend", "", "pending")
        insert_task(conn, "T-002", "frontend", "", "pending")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 2

    def test_null_lane_falls_back_to_type(self, temp_db):
        """Tasks with NULL lane should use type as lane identifier."""
        conn, _ = temp_db
        conn.execute("""
            INSERT INTO tasks (id, type, lane, status, title)
            VALUES ('T-001', 'backend', NULL, 'pending', 'Test')
        """)
        conn.commit()
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 1

    def test_case_insensitive_status_matching(self, temp_db):
        """Status matching should be case-insensitive."""
        conn, _ = temp_db
        insert_task(conn, "T-001", "backend", "stream-a", "PENDING")
        insert_task(conn, "T-002", "frontend", "stream-b", "Pending")
        insert_task(conn, "T-003", "qa", "stream-c", "IN_PROGRESS")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 2
        assert counts["activeLaneCount"] == 1

    def test_mixed_statuses_in_same_lane(self, temp_db):
        """Same lane with tasks in different statuses should count in both."""
        conn, _ = temp_db
        # Same lane (stream-a) has both pending and active tasks
        insert_task(conn, "T-001", "backend", "stream-a", "pending")
        insert_task(conn, "T-002", "backend", "stream-a", "in_progress")
        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        # Lane appears in both pending AND active
        assert counts["pendingLaneCount"] == 1
        assert counts["activeLaneCount"] == 1

    def test_all_status_types_comprehensive(self, temp_db):
        """Comprehensive test with all status types."""
        conn, _ = temp_db
        # Pending statuses (3 different lanes)
        insert_task(conn, "T-001", "backend", "lane-1", "pending")
        insert_task(conn, "T-002", "frontend", "lane-2", "next")
        insert_task(conn, "T-003", "qa", "lane-3", "planned")

        # Active statuses (2 different lanes)
        insert_task(conn, "T-004", "backend", "lane-4", "in_progress")
        insert_task(conn, "T-005", "frontend", "lane-5", "running")

        # Statuses that should NOT be counted
        insert_task(conn, "T-006", "qa", "lane-6", "completed")
        insert_task(conn, "T-007", "backend", "lane-7", "blocked")
        insert_task(conn, "T-008", "frontend", "lane-8", "failed")

        counts = get_lane_counts(conn, PENDING_STATUSES, ACTIVE_STATUSES)
        assert counts["pendingLaneCount"] == 3, \
            f"Expected 3 pending lanes, got {counts['pendingLaneCount']}"
        assert counts["activeLaneCount"] == 2, \
            f"Expected 2 active lanes, got {counts['activeLaneCount']}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
