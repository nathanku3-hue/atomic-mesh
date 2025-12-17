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
