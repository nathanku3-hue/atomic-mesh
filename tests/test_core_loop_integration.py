"""
Core loop integration test:

draft_plan() -> accept_plan() -> pick_task_braided()

This is intentionally tiny and deterministic: it verifies the scheduler + SQLite
plumbing works end-to-end without relying on any external services.
"""

import json
import os
import sqlite3
import sys

import pytest

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _init_minimal_db(db_path: str):
    conn = sqlite3.connect(db_path)
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
            lease_id TEXT DEFAULT '',
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
            plan_key TEXT DEFAULT ''
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


def _write_minimal_docs(docs_dir: str):
    os.makedirs(docs_dir, exist_ok=True)

    prd = """# PRD

## Goals
- Build a tiny end-to-end loop.

## User Stories
- [ ] US-01: As a user, I want to view a dashboard so that I can see status
- [ ] US-02: As a user, I want to trigger a run so that results update
- [ ] US-03: As a user, I want to export data so that I can share it
"""

    spec = """# SPEC

## API
Use `GET /api/ping` to check health.
Use `POST /api/run` to trigger a run.
Use `GET /api/results` to fetch results.

## Data Model
| Entity | Fields | Notes |
| User | id:int, email:text | Auth identity |
| Run | id:int, started_at:int | Execution record |
| Result | id:int, run_id:int, payload:json | Output |
"""

    decision_log = """# DECISION_LOG

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
| 001 | 2025-12-01 | ARCH | Use SQLite WAL mode | Better concurrent reads | core | db | ACCEPTED |
"""

    with open(os.path.join(docs_dir, "PRD.md"), "w", encoding="utf-8") as f:
        f.write(prd)
    with open(os.path.join(docs_dir, "SPEC.md"), "w", encoding="utf-8") as f:
        f.write(spec)
    with open(os.path.join(docs_dir, "DECISION_LOG.md"), "w", encoding="utf-8") as f:
        f.write(decision_log)


def test_core_loop_draft_accept_pick(tmp_path, monkeypatch):
    import mesh_server
    from mesh_server import draft_plan, accept_plan, pick_task_braided

    base_dir = str(tmp_path)
    docs_dir = os.path.join(base_dir, "docs")
    plans_dir = os.path.join(docs_dir, "PLANS")
    state_dir = os.path.join(base_dir, "control", "state")
    db_path = os.path.join(base_dir, "mesh.db")
    preview_path = os.path.join(state_dir, "plan_preview.json")

    os.makedirs(plans_dir, exist_ok=True)
    os.makedirs(state_dir, exist_ok=True)

    _init_minimal_db(db_path)
    _write_minimal_docs(docs_dir)

    # Patch mesh_server paths into the temp workspace
    monkeypatch.setattr(mesh_server, "BASE_DIR", base_dir)
    monkeypatch.setattr(mesh_server, "DOCS_DIR", docs_dir)
    monkeypatch.setattr(mesh_server, "STATE_DIR", state_dir)
    monkeypatch.setattr(mesh_server, "DB_PATH", db_path)
    monkeypatch.setattr(mesh_server, "DB_FILE", db_path)
    monkeypatch.setattr(mesh_server, "PLAN_PREVIEW_PATH", preview_path)
    monkeypatch.setattr(mesh_server, "get_context_readiness", lambda: '{"status": "OK"}')

    draft = json.loads(draft_plan())
    assert draft.get("status") == "OK", f"draft_plan failed: {draft}"
    assert os.path.exists(draft.get("path", "")), "draft_plan should write a plan file"

    accepted = json.loads(accept_plan(draft["path"]))
    assert accepted.get("status") == "OK", f"accept_plan failed: {accepted}"
    assert accepted.get("created_count", 0) > 0, "accept_plan should hydrate at least one task"

    picked = json.loads(pick_task_braided(worker_id="integration_worker"))
    assert picked.get("status") == "OK", f"pick_task_braided should find work: {picked}"
    assert picked.get("id") is not None
    assert picked.get("lane") in ("backend", "frontend", "qa", "ops", "docs")
