import os
import sqlite3
import sys

import pytest


@pytest.fixture
def mesh_with_db(tmp_path, monkeypatch):
    """
    Provision a fresh mesh_server instance backed by a real sqlite file.
    Ensures init_db() runs and creates indexes.
    """
    base_dir = tmp_path / "mesh_env"
    base_dir.mkdir(parents=True, exist_ok=True)
    db_path = base_dir / "mesh.db"
    db_path.touch()  # init_db requires the file to already exist

    monkeypatch.setenv("MESH_BASE_DIR", str(base_dir))
    monkeypatch.setenv("ATOMIC_MESH_DB", str(db_path))
    monkeypatch.chdir(base_dir)

    # Reload mesh_server to pick up new env + DB path
    if "mesh_server" in sys.modules:
        del sys.modules["mesh_server"]
    import importlib
    import mesh_server

    mesh_server = importlib.reload(mesh_server)
    mesh_server.init_db()
    return mesh_server, db_path


def test_tasks_indexes_exist(mesh_with_db):
    mesh_server, db_path = mesh_with_db

    expected_indexes = {
        "idx_tasks_pick_preempt",
        "idx_tasks_pick_lane",
        "idx_tasks_auditor_status_status",
        "idx_tasks_status_archetype",
        "idx_tasks_status_updated_at",
        "idx_tasks_source_plan_hash",
        "idx_tasks_task_signature",
    }

    conn = sqlite3.connect(db_path)
    rows = conn.execute("PRAGMA index_list('tasks')").fetchall()
    names = {row[1] for row in rows}
    conn.close()

    missing = expected_indexes - names
    assert not missing, f"Missing expected indexes: {missing}"


def test_hot_queries_use_indexes(mesh_with_db):
    _, db_path = mesh_with_db

    conn = sqlite3.connect(db_path)

    def assert_uses(sql, index_name, params=()):
        plan = conn.execute(f"EXPLAIN QUERY PLAN {sql}", params).fetchall()
        detail = " ".join(row[-1] for row in plan)
        assert index_name in detail, f"Expected {index_name} in plan, got: {detail}"

    assert_uses(
        "SELECT id FROM tasks WHERE auditor_status='pending' AND status='reviewing'",
        "idx_tasks_auditor_status_status",
    )
    assert_uses(
        "SELECT id FROM tasks WHERE status='reviewing' AND archetype='SEC'",
        "idx_tasks_status_archetype",
    )
    assert_uses(
        "SELECT id FROM tasks WHERE status='completed' ORDER BY updated_at DESC LIMIT 1",
        "idx_tasks_status_updated_at",
    )
    assert_uses(
        "SELECT id FROM tasks WHERE source_plan_hash='abc123'",
        "idx_tasks_source_plan_hash",
    )
    assert_uses(
        "SELECT id FROM tasks WHERE task_signature='deadbeef'",
        "idx_tasks_task_signature",
    )

    conn.close()


def test_init_db_upgrades_legacy_schema(tmp_path, monkeypatch):
    """
    Ensure init_db can upgrade a legacy tasks table (db_pool.py schema)
    and still create performance indexes without errors.
    """
    base_dir = tmp_path / "legacy_env"
    base_dir.mkdir(parents=True, exist_ok=True)
    db_path = base_dir / "mesh.db"
    db_path.touch()

    # Create legacy tasks table (db_pool.py schema)
    conn = sqlite3.connect(db_path)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            desc TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            priority INTEGER DEFAULT 1,
            worker_id TEXT,
            retry_count INTEGER DEFAULT 0,
            output TEXT,
            created_at INTEGER,
            updated_at INTEGER
        );
        """
    )
    conn.commit()
    conn.close()

    # Run init_db to apply migrations + indexes
    monkeypatch.setenv("MESH_BASE_DIR", str(base_dir))
    monkeypatch.setenv("ATOMIC_MESH_DB", str(db_path))
    monkeypatch.chdir(base_dir)

    if "mesh_server" in sys.modules:
        del sys.modules["mesh_server"]
    import importlib
    import mesh_server

    mesh_server = importlib.reload(mesh_server)
    mesh_server.init_db()

    # Verify required columns were added
    conn = sqlite3.connect(db_path)
    cols = {row[1] for row in conn.execute("PRAGMA table_info('tasks')").fetchall()}
    required_cols = {
        "auditor_status",
        "archetype",
        "lane",
        "lane_rank",
        "created_at",
        "exec_class",
        "task_signature",
        "source_plan_hash",
        "plan_key",
    }
    missing = required_cols - cols
    assert not missing, f"Missing columns after migration: {missing}"

    # Verify indexes exist
    index_names = {row[1] for row in conn.execute("PRAGMA index_list('tasks')")}
    expected_indexes = {
        "idx_tasks_pick_preempt",
        "idx_tasks_pick_lane",
        "idx_tasks_auditor_status_status",
        "idx_tasks_status_archetype",
        "idx_tasks_status_updated_at",
        "idx_tasks_source_plan_hash",
        "idx_tasks_task_signature",
    }
    missing_idx = expected_indexes - index_names
    assert not missing_idx, f"Missing indexes after migration: {missing_idx}"
    conn.close()
