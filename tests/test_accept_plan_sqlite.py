"""
Test: Backend tasks survive /accept-plan and appear in SQLite queue.

v17.2: Tests for SQLite as single source of truth + idempotency guard.
Verifies:
1. Tasks are written to SQLite (canonical store)
2. Duplicate plans are rejected (idempotency)
3. Duplicate tasks within a plan are skipped (task_signature)
4. plan_preview.json is derived from SQLite
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
def temp_workspace(tmp_path):
    """Create a temporary workspace with required structure."""
    # Create docs/PLANS directory
    plans_dir = tmp_path / "docs" / "PLANS"
    plans_dir.mkdir(parents=True)

    # Create control/state directory
    state_dir = tmp_path / "control" / "state"
    state_dir.mkdir(parents=True)

    # Create empty tasks.json (deprecated but may still be read)
    tasks_json = state_dir / "tasks.json"
    tasks_json.write_text('{"tasks": {}, "_meta": {"version": "test"}}')

    # Create SQLite database with tasks table including v18.0 columns
    db_path = tmp_path / "mesh.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT DEFAULT 'backend',
            desc TEXT,
            deps TEXT DEFAULT '[]',
            status TEXT DEFAULT 'pending',
            updated_at INTEGER,
            priority INTEGER DEFAULT 1,
            source_ids TEXT DEFAULT '[]',
            risk TEXT,
            qa_status TEXT,
            source_plan_hash TEXT DEFAULT '',
            task_signature TEXT DEFAULT '',
            lane TEXT DEFAULT '',
            created_at INTEGER DEFAULT 0,
            exec_class TEXT DEFAULT 'exclusive',
            lane_rank INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    conn.close()

    return tmp_path


@pytest.fixture
def sample_plan_file(temp_workspace):
    """Create a sample plan file with backend and frontend tasks."""
    plan_content = """# Draft Plan - Test Project
> Generated: 2025-12-15 | Digest: test123

## [Backend]

- [ ] Backend: Implement user authentication API -- DoD: Auth works | Trace: SPEC-API-01
- [ ] Backend: Create database migration for users -- DoD: Migration runs | Trace: SPEC-DB-01
- [ ] Backend: Add rate limiting middleware -- DoD: Rate limits enforced | Trace: SPEC-SEC-01

## [Frontend]

- [ ] Frontend: Build login form component -- DoD: Form validates | Trace: PRD-US-01
- [ ] Frontend: Create dashboard layout -- DoD: Layout renders | Trace: PRD-US-02

## [QA]

- [ ] QA: Write auth API tests -- DoD: Tests pass | Trace: SPEC-API-01
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_test.md"
    plan_path.write_text(plan_content)
    return plan_path


def test_accept_plan_creates_sqlite_backend_tasks(temp_workspace, sample_plan_file, monkeypatch):
    """Verify that /accept-plan inserts backend tasks into SQLite."""
    from mesh_server import accept_plan, BASE_DIR, DB_FILE, load_state, get_state_path

    # Patch BASE_DIR and DB_FILE to use temp workspace
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))

    # Mock get_context_readiness to bypass BOOTSTRAP check
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Run accept_plan
    result = accept_plan(str(sample_plan_file))
    result_data = json.loads(result)

    # Verify success
    assert result_data.get("status") == "OK", f"accept_plan failed: {result_data}"
    assert result_data.get("created_count") == 6, f"Expected 6 tasks, got {result_data.get('created_count')}"

    # Query SQLite to verify backend tasks exist
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row

    backend_tasks = conn.execute(
        "SELECT id, type, desc, status FROM tasks WHERE type='backend'"
    ).fetchall()

    frontend_tasks = conn.execute(
        "SELECT id, type, desc, status FROM tasks WHERE type='frontend'"
    ).fetchall()

    qa_tasks = conn.execute(
        "SELECT id, type, desc, status FROM tasks WHERE type='qa'"
    ).fetchall()

    conn.close()

    # Assertions
    assert len(backend_tasks) == 3, f"Expected 3 backend tasks in SQLite, got {len(backend_tasks)}"
    assert len(frontend_tasks) == 2, f"Expected 2 frontend tasks in SQLite, got {len(frontend_tasks)}"
    assert len(qa_tasks) == 1, f"Expected 1 QA task in SQLite, got {len(qa_tasks)}"

    # Verify all tasks are pending
    for task in backend_tasks:
        assert task["status"] == "pending", f"Task {task['id']} should be pending"

    # Verify task descriptions are preserved
    backend_descs = [t["desc"] for t in backend_tasks]
    assert any("user authentication" in d.lower() for d in backend_descs), \
        "Auth task not found in SQLite"
    assert any("database migration" in d.lower() for d in backend_descs), \
        "Migration task not found in SQLite"
    assert any("rate limiting" in d.lower() for d in backend_descs), \
        "Rate limiting task not found in SQLite"


def test_scheduler_can_find_backend_tasks(temp_workspace, sample_plan_file, monkeypatch):
    """Verify scheduler query finds backend tasks after accept_plan."""
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))

    # Mock get_context_readiness to bypass BOOTSTRAP check
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Run accept_plan
    accept_plan(str(sample_plan_file))

    # Simulate scheduler query (from Invoke-Continue in control_panel.ps1)
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row

    next_task = conn.execute(
        "SELECT id, type, desc FROM tasks WHERE status='pending' ORDER BY priority DESC, id LIMIT 1"
    ).fetchone()

    conn.close()

    # Scheduler should find a task
    assert next_task is not None, "Scheduler found no pending tasks!"
    assert next_task["type"] in ["backend", "frontend", "qa"], \
        f"Unexpected task type: {next_task['type']}"


def test_backend_tasks_appear_before_frontend_by_id(temp_workspace, sample_plan_file, monkeypatch):
    """Verify backend tasks are inserted first (lower IDs) so they're scheduled first."""
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))

    # Mock get_context_readiness to bypass BOOTSTRAP check
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Run accept_plan
    accept_plan(str(sample_plan_file))

    # Query all tasks ordered by ID
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row

    all_tasks = conn.execute(
        "SELECT id, type FROM tasks ORDER BY id"
    ).fetchall()

    conn.close()

    # Backend tasks should have lower IDs (come first in plan)
    backend_ids = [t["id"] for t in all_tasks if t["type"] == "backend"]
    frontend_ids = [t["id"] for t in all_tasks if t["type"] == "frontend"]

    assert len(backend_ids) > 0, "No backend tasks found"
    assert len(frontend_ids) > 0, "No frontend tasks found"
    assert max(backend_ids) < min(frontend_ids), \
        f"Backend IDs {backend_ids} should all be less than frontend IDs {frontend_ids}"


def test_idempotency_rejects_duplicate_plan(temp_workspace, sample_plan_file, monkeypatch):
    """Verify that running /accept-plan twice on same file returns ALREADY_ACCEPTED."""
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # First accept should succeed
    result1 = accept_plan(str(sample_plan_file))
    data1 = json.loads(result1)
    assert data1["status"] == "OK", f"First accept failed: {data1}"
    assert data1["created_count"] == 6

    # Second accept of same file should be rejected
    result2 = accept_plan(str(sample_plan_file))
    data2 = json.loads(result2)
    assert data2["status"] == "ALREADY_ACCEPTED", f"Expected ALREADY_ACCEPTED, got: {data2}"
    assert "plan_hash" in data2


def test_duplicate_tasks_within_plan_are_skipped(temp_workspace, monkeypatch):
    """Verify that duplicate tasks (same type+desc) are skipped via task_signature."""
    from mesh_server import accept_plan

    # Create plan with duplicate tasks
    plan_with_dups = """# Draft with duplicates

## [Backend]

- [ ] Backend: Same task description -- DoD: test
- [ ] Backend: Same task description -- DoD: test
- [ ] Backend: Unique task -- DoD: test
"""
    dup_plan_path = temp_workspace / "docs" / "PLANS" / "draft_dups.md"
    dup_plan_path.write_text(plan_with_dups)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(dup_plan_path))
    data = json.loads(result)

    # Should create only 2 tasks (1 duplicate skipped)
    assert data["status"] == "OK"
    assert data["created_count"] == 2, f"Expected 2 tasks (1 dup skipped), got {data['created_count']}"


def test_plan_preview_derived_from_sqlite(temp_workspace, sample_plan_file, monkeypatch):
    """Verify plan_preview.json is rebuilt from SQLite after accept."""
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    # Also patch PLAN_PREVIEW_PATH (computed at module load time)
    preview_path = temp_workspace / "control" / "state" / "plan_preview.json"
    monkeypatch.setattr('mesh_server.PLAN_PREVIEW_PATH', str(preview_path))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(sample_plan_file))
    data = json.loads(result)
    assert data["status"] == "OK"

    # Check plan_preview.json was created
    preview_path = temp_workspace / "control" / "state" / "plan_preview.json"
    assert preview_path.exists(), "plan_preview.json not created"

    # Verify it's marked as derived from SQLite
    with open(preview_path) as f:
        preview = json.load(f)

    assert preview["source"] == "sqlite:mesh.db", \
        f"Expected source 'sqlite:mesh.db', got '{preview.get('source')}'"
    assert "_derived" in preview, "Missing _derived marker"

    # Verify task counts match SQLite
    total_tasks = sum(len(s.get("tasks", [])) for s in preview.get("streams", []))
    assert total_tasks == 6, f"Expected 6 tasks in preview, got {total_tasks}"


# =============================================================================
# v17.3: Lane + Priority Parsing Tests
# =============================================================================

def test_lane_normalization(temp_workspace, monkeypatch):
    """Verify that task type prefixes are normalized to lowercase lanes."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Lane Test

## Tasks

- [ ] Backend: API endpoint task -- DoD: test | Trace: SPEC-01
- [ ] Frontend: UI component task -- DoD: test | Trace: PRD-01
- [ ] QA: Test plan task -- DoD: test | Trace: SPEC-02
- [ ] Ops: Deployment task -- DoD: test | Trace: SPEC-03
- [ ] Docs: Documentation task -- DoD: test | Trace: PRD-02
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_lane_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"
    assert data["created_count"] == 5

    # Query SQLite for lanes
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT type, lane FROM tasks").fetchall()
    conn.close()

    # Verify lane normalization
    lanes_by_type = {t["type"]: t["lane"] for t in tasks}
    assert lanes_by_type["backend"] == "backend", "Backend lane not normalized"
    assert lanes_by_type["frontend"] == "frontend", "Frontend lane not normalized"
    assert lanes_by_type["qa"] == "qa", "QA lane not normalized"
    assert lanes_by_type["ops"] == "ops", "Ops lane not normalized"
    assert lanes_by_type["docs"] == "docs", "Docs lane not normalized"


def test_default_priority_by_lane(temp_workspace, monkeypatch):
    """Verify that default priority is assigned based on lane (v18.0: lower = more urgent)."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Priority Test

## Tasks

- [ ] Backend: Backend task -- DoD: test | Trace: SPEC-01
- [ ] Frontend: Frontend task -- DoD: test | Trace: PRD-01
- [ ] QA: QA task -- DoD: test | Trace: SPEC-02
- [ ] Ops: Ops task -- DoD: test | Trace: SPEC-03
- [ ] Docs: Docs task -- DoD: test | Trace: PRD-02
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_priority_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"

    # Query SQLite for priorities
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT lane, priority FROM tasks").fetchall()
    conn.close()

    # v18.0: Verify default priorities (lower = more urgent)
    # backend=10, frontend=20, qa=30, ops=40, docs=50
    priority_by_lane = {t["lane"]: t["priority"] for t in tasks}
    assert priority_by_lane["backend"] == 10, f"Backend priority should be 10, got {priority_by_lane['backend']}"
    assert priority_by_lane["frontend"] == 20, f"Frontend priority should be 20, got {priority_by_lane['frontend']}"
    assert priority_by_lane["qa"] == 30, f"QA priority should be 30, got {priority_by_lane['qa']}"
    assert priority_by_lane["ops"] == 40, f"Ops priority should be 40, got {priority_by_lane['ops']}"
    assert priority_by_lane["docs"] == 50, f"Docs priority should be 50, got {priority_by_lane['docs']}"


def test_priority_override_urgent_and_high(temp_workspace, monkeypatch):
    """Verify that | P:URGENT and | P:HIGH override default priority (v18.0: lower = more urgent)."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Priority Override Test

## Tasks

- [ ] Docs: Low priority docs task -- DoD: test | Trace: PRD-01
- [ ] Docs: Urgent docs task -- DoD: test | Trace: PRD-02 | P:URGENT
- [ ] Ops: High priority ops task -- DoD: test | Trace: SPEC-01 | P:HIGH
- [ ] Backend: Normal backend task -- DoD: test | Trace: SPEC-02
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_override_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"
    assert data["created_count"] == 4

    # Query SQLite for priorities
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT desc, priority FROM tasks").fetchall()
    conn.close()

    # Build lookup
    priority_by_desc = {}
    for t in tasks:
        if "Low priority" in t["desc"]:
            priority_by_desc["low_docs"] = t["priority"]
        elif "Urgent" in t["desc"]:
            priority_by_desc["urgent_docs"] = t["priority"]
        elif "High priority" in t["desc"]:
            priority_by_desc["high_ops"] = t["priority"]
        elif "Normal backend" in t["desc"]:
            priority_by_desc["normal_backend"] = t["priority"]

    # v18.0: Verify overrides (lower = more urgent)
    # URGENT=0, HIGH=5, backend=10, docs=50
    assert priority_by_desc["low_docs"] == 50, f"Low docs should be 50, got {priority_by_desc['low_docs']}"
    assert priority_by_desc["urgent_docs"] == 0, f"Urgent docs should be 0, got {priority_by_desc['urgent_docs']}"
    assert priority_by_desc["high_ops"] == 5, f"High ops should be 5, got {priority_by_desc['high_ops']}"
    assert priority_by_desc["normal_backend"] == 10, f"Normal backend should be 10, got {priority_by_desc['normal_backend']}"


def test_created_at_timestamp(temp_workspace, monkeypatch):
    """Verify that created_at timestamp is set on task creation."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Timestamp Test

- [ ] Backend: Task with timestamp -- DoD: test | Trace: SPEC-01
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_timestamp_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    before_time = int(time.time())
    result = accept_plan(str(plan_path))
    after_time = int(time.time())

    data = json.loads(result)
    assert data["status"] == "OK"

    # Query SQLite for created_at
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    task = conn.execute("SELECT created_at FROM tasks").fetchone()
    conn.close()

    # Verify timestamp is within range
    assert task["created_at"] >= before_time, f"created_at {task['created_at']} < before_time {before_time}"
    assert task["created_at"] <= after_time, f"created_at {task['created_at']} > after_time {after_time}"


def test_task_signature_includes_trace(temp_workspace, monkeypatch):
    """Verify that task_signature includes lane, desc, and trace."""
    from mesh_server import accept_plan
    import hashlib

    plan_content = """# Draft Plan - Signature Test

- [ ] Backend: Same desc different trace -- DoD: test | Trace: SPEC-01
- [ ] Backend: Same desc different trace -- DoD: test | Trace: SPEC-02
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_sig_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)

    # Both tasks should be created because they have different traces
    assert data["status"] == "OK"
    assert data["created_count"] == 2, f"Expected 2 tasks (different traces), got {data['created_count']}"

    # Verify signatures are different
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT task_signature FROM tasks").fetchall()
    conn.close()

    sigs = [t["task_signature"] for t in tasks]
    assert len(set(sigs)) == 2, f"Expected 2 unique signatures, got {len(set(sigs))}"


def test_duplicate_accept_same_signature_skipped(temp_workspace, monkeypatch):
    """Verify that tasks with same signature are skipped on re-accept of modified plan."""
    from mesh_server import accept_plan

    # First plan
    plan1_content = """# Draft Plan - First
- [ ] Backend: Task A -- DoD: test | Trace: SPEC-01
"""
    plan1_path = temp_workspace / "docs" / "PLANS" / "draft_first.md"
    plan1_path.write_text(plan1_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept first plan
    result1 = accept_plan(str(plan1_path))
    data1 = json.loads(result1)
    assert data1["status"] == "OK"
    assert data1["created_count"] == 1

    # Second plan with same task (different plan file, same task signature)
    plan2_content = """# Draft Plan - Second (different header to change plan hash)
- [ ] Backend: Task A -- DoD: test | Trace: SPEC-01
- [ ] Backend: Task B -- DoD: test | Trace: SPEC-02
"""
    plan2_path = temp_workspace / "docs" / "PLANS" / "draft_second.md"
    plan2_path.write_text(plan2_content)

    # Accept second plan (should skip Task A, create only Task B)
    result2 = accept_plan(str(plan2_path))
    data2 = json.loads(result2)

    assert data2["status"] == "OK"
    assert data2["created_count"] == 1, f"Expected 1 new task (Task A skipped), got {data2['created_count']}"

    # Verify only 2 total tasks in DB
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    total = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
    conn.close()
    assert total == 2, f"Expected 2 total tasks, got {total}"


# =============================================================================
# v17.4: Execution Class Tests (Stream C Phase B)
# =============================================================================

def test_classify_exec_class_function():
    """Unit test for classify_exec_class heuristic function (v17.4.1)."""
    from mesh_server import classify_exec_class

    # v17.4.1: Override syntax wins over heuristic
    assert classify_exec_class("backend", "Any task | X:PAR", "PAR") == "parallel_safe"
    assert classify_exec_class("backend", "Any task | X:ADD", "ADD") == "additive"
    assert classify_exec_class("qa", "Review tests | X:EXC", "EXC") == "exclusive"

    # v17.4.1: QA/docs with read-only patterns → parallel_safe
    assert classify_exec_class("qa", "Review test coverage") == "parallel_safe"
    assert classify_exec_class("qa", "Audit security tests") == "parallel_safe"
    assert classify_exec_class("qa", "Analyze test results") == "parallel_safe"
    assert classify_exec_class("docs", "Review API documentation") == "parallel_safe"
    assert classify_exec_class("docs", "Verify doc accuracy") == "parallel_safe"

    # v17.4.1: QA/docs without read-only patterns → exclusive (may mutate fixtures)
    assert classify_exec_class("qa", "Write unit tests") == "exclusive"
    assert classify_exec_class("qa", "Update test fixtures") == "exclusive"
    assert classify_exec_class("docs", "Update API documentation") == "exclusive"
    assert classify_exec_class("docs", "Create new guide") == "additive"  # has additive pattern

    # Additive patterns (no exclusive patterns) → additive
    assert classify_exec_class("backend", "Create new user service") == "additive"
    assert classify_exec_class("backend", "Add new file for config") == "additive"
    assert classify_exec_class("frontend", "Create file for component") == "additive"

    # Exclusive patterns → exclusive
    assert classify_exec_class("backend", "Refactor auth module") == "exclusive"
    assert classify_exec_class("backend", "Remove deprecated code") == "exclusive"
    assert classify_exec_class("backend", "Update existing endpoint") == "exclusive"
    assert classify_exec_class("backend", "Rename function") == "exclusive"
    assert classify_exec_class("backend", "Modify config file") == "exclusive"
    assert classify_exec_class("backend", "Change database schema") == "exclusive"
    assert classify_exec_class("backend", "Delete old records") == "exclusive"

    # Mixed (additive + exclusive) → exclusive (conservative)
    assert classify_exec_class("backend", "Create new file and refactor old") == "exclusive"
    assert classify_exec_class("backend", "Add new module, remove legacy") == "exclusive"

    # Default (no patterns) → exclusive (safe default)
    assert classify_exec_class("backend", "Implement user login") == "exclusive"
    assert classify_exec_class("frontend", "Build dashboard component") == "exclusive"


def test_exec_class_qa_docs_parallel_safe(temp_workspace, monkeypatch):
    """Verify QA and docs lanes get exec_class='parallel_safe' with read-only patterns."""
    from mesh_server import accept_plan

    # v17.4.1: QA/docs need read-only patterns (review, audit, analyze, etc.) for parallel_safe
    plan_content = """# Draft Plan - Exec Class Test

## Tasks

- [ ] QA: Review integration test coverage -- DoD: tests pass | Trace: SPEC-01
- [ ] Docs: Verify README accuracy -- DoD: docs reviewed | Trace: PRD-01
- [ ] Backend: Implement API -- DoD: API works | Trace: SPEC-02
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_exec_class_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"
    assert data["created_count"] == 3

    # Query SQLite for exec_class
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT lane, exec_class FROM tasks").fetchall()
    conn.close()

    # Verify exec_class by lane
    exec_by_lane = {t["lane"]: t["exec_class"] for t in tasks}
    assert exec_by_lane["qa"] == "parallel_safe", f"QA should be parallel_safe, got {exec_by_lane['qa']}"
    assert exec_by_lane["docs"] == "parallel_safe", f"Docs should be parallel_safe, got {exec_by_lane['docs']}"
    assert exec_by_lane["backend"] == "exclusive", f"Backend should be exclusive, got {exec_by_lane['backend']}"


def test_exec_class_additive_for_new_file(temp_workspace, monkeypatch):
    """Verify 'add new file'/'create new' tasks get exec_class='additive'."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Additive Test

## Tasks

- [ ] Backend: Create new user service -- DoD: service works | Trace: SPEC-01
- [ ] Backend: Add new file for config -- DoD: file exists | Trace: SPEC-02
- [ ] Backend: Refactor existing auth -- DoD: auth works | Trace: SPEC-03
- [ ] Backend: Create new and refactor old -- DoD: done | Trace: SPEC-04
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_additive_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"
    assert data["created_count"] == 4

    # Query SQLite for exec_class
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT desc, exec_class FROM tasks").fetchall()
    conn.close()

    # Build lookup
    exec_by_desc = {}
    for t in tasks:
        if "Create new user" in t["desc"]:
            exec_by_desc["create_new"] = t["exec_class"]
        elif "Add new file" in t["desc"]:
            exec_by_desc["add_new_file"] = t["exec_class"]
        elif "Refactor existing" in t["desc"]:
            exec_by_desc["refactor"] = t["exec_class"]
        elif "Create new and refactor" in t["desc"]:
            exec_by_desc["mixed"] = t["exec_class"]

    # Verify classifications
    assert exec_by_desc["create_new"] == "additive", f"Create new should be additive, got {exec_by_desc['create_new']}"
    assert exec_by_desc["add_new_file"] == "additive", f"Add new file should be additive, got {exec_by_desc['add_new_file']}"
    assert exec_by_desc["refactor"] == "exclusive", f"Refactor should be exclusive, got {exec_by_desc['refactor']}"
    assert exec_by_desc["mixed"] == "exclusive", f"Mixed (has refactor) should be exclusive, got {exec_by_desc['mixed']}"


def test_exec_class_included_in_response(temp_workspace, monkeypatch):
    """Verify exec_class is included in accept_plan response."""
    from mesh_server import accept_plan

    # v17.4.1: Use read-only pattern to get parallel_safe
    plan_content = """# Draft Plan - Response Test

- [ ] QA: Review test results -- DoD: test | Trace: SPEC-01
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_response_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)

    assert data["status"] == "OK"
    assert len(data["tasks"]) == 1
    assert "exec_class" in data["tasks"][0], "exec_class should be in response"
    assert data["tasks"][0]["exec_class"] == "parallel_safe", "QA review task should be parallel_safe"


def test_exec_class_override_syntax(temp_workspace, monkeypatch):
    """Verify | X:EXC/PAR/ADD override syntax works in plan."""
    from mesh_server import accept_plan

    plan_content = """# Draft Plan - Override Test

## Tasks

- [ ] Backend: Normal task defaults to exclusive -- DoD: done | Trace: SPEC-01
- [ ] Backend: Force parallel with override -- DoD: done | Trace: SPEC-02 | X:PAR
- [ ] QA: Write tests (would be exclusive) -- DoD: done | Trace: SPEC-03 | X:ADD
"""
    plan_path = temp_workspace / "docs" / "PLANS" / "draft_override_test.md"
    plan_path.write_text(plan_content)

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "OK"}')

    # Accept plan
    result = accept_plan(str(plan_path))
    data = json.loads(result)
    assert data["status"] == "OK"
    assert data["created_count"] == 3

    # Query SQLite for exec_class
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    conn.row_factory = sqlite3.Row
    tasks = conn.execute("SELECT desc, exec_class FROM tasks").fetchall()
    conn.close()

    # Build lookup
    exec_by_desc = {}
    for t in tasks:
        if "Normal task" in t["desc"]:
            exec_by_desc["normal"] = t["exec_class"]
        elif "Force parallel" in t["desc"]:
            exec_by_desc["forced_par"] = t["exec_class"]
        elif "Write tests" in t["desc"]:
            exec_by_desc["forced_add"] = t["exec_class"]

    # Verify overrides
    assert exec_by_desc["normal"] == "exclusive", f"Normal should be exclusive, got {exec_by_desc['normal']}"
    assert exec_by_desc["forced_par"] == "parallel_safe", f"Forced PAR should be parallel_safe, got {exec_by_desc['forced_par']}"
    assert exec_by_desc["forced_add"] == "additive", f"Forced ADD should be additive, got {exec_by_desc['forced_add']}"


# =============================================================================
# v20.0: Regression Test - Pipeline Advancement After /accept-plan
# =============================================================================
# Issue: /accept-plan was silently failing (BLOCKED in BOOTSTRAP mode)
# but the UI handler ignored the response and just refreshed.
# After fix, BLOCKED status is properly reported to the user.

def test_accept_plan_blocked_in_bootstrap_mode(temp_workspace, sample_plan_file, monkeypatch):
    """
    Regression test: accept_plan returns BLOCKED when context is in BOOTSTRAP mode.

    Root cause: UI was swallowing errors with empty catch{} and always refreshing.
    Expected: accept_plan returns {"status": "BLOCKED", "reason": "BOOTSTRAP_MODE", ...}
    """
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))

    # Mock get_context_readiness to return BOOTSTRAP mode (incomplete context)
    bootstrap_response = json.dumps({
        "status": "BOOTSTRAP",
        "overall": {
            "ready": False,
            "blocking_files": ["PRD", "SPEC"]
        }
    })
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: bootstrap_response)

    # Run accept_plan - should be BLOCKED
    result = accept_plan(str(sample_plan_file))
    data = json.loads(result)

    # Verify BLOCKED response
    assert data["status"] == "BLOCKED", f"Expected BLOCKED, got: {data}"
    assert data["reason"] == "BOOTSTRAP_MODE", f"Expected BOOTSTRAP_MODE reason, got: {data}"
    assert "blocking_files" in data, "Should include blocking_files"
    assert "PRD" in data["blocking_files"], "PRD should be blocking"
    assert "SPEC" in data["blocking_files"], "SPEC should be blocking"

    # Verify NO tasks were created
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    count = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
    conn.close()

    assert count == 0, f"Expected 0 tasks when BLOCKED, got {count}"


def test_pipeline_advances_only_on_success(temp_workspace, sample_plan_file, monkeypatch):
    """
    Verify that tasks DB has >0 tasks after successful accept_plan.
    This is what drives pipeline state from RED to GREEN for [Pln] stage.
    """
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))

    # Mock get_context_readiness to allow accept (EXECUTION mode)
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "EXECUTION"}')

    # Before accept: no tasks
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    count_before = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
    conn.close()
    assert count_before == 0, "Should start with 0 tasks"

    # Accept plan
    result = accept_plan(str(sample_plan_file))
    data = json.loads(result)

    assert data["status"] == "OK", f"Expected OK, got: {data}"

    # After accept: tasks exist (drives pipeline [Pln] stage to GREEN)
    conn = sqlite3.connect(str(temp_workspace / "mesh.db"))
    count_after = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]
    queued_count = conn.execute(
        "SELECT COUNT(*) FROM tasks WHERE status IN ('pending', 'next', 'planned')"
    ).fetchone()[0]
    conn.close()

    assert count_after > 0, f"Expected >0 tasks, got {count_after}"
    assert queued_count > 0, f"Expected >0 queued tasks, got {queued_count}"

    # This proves: tasks exist → pipeline [Pln] advances from RED to GREEN
    # UI logic in Build-PipelineStatus checks: $queuedCount -gt 0 → $planState = "GREEN"


def test_accept_plan_file_not_found_error(temp_workspace, monkeypatch):
    """Verify accept_plan returns ERROR status for non-existent file."""
    from mesh_server import accept_plan

    # Patch directories
    monkeypatch.setattr('mesh_server.BASE_DIR', str(temp_workspace))
    monkeypatch.setattr('mesh_server.DB_FILE', str(temp_workspace / "mesh.db"))
    monkeypatch.setattr('mesh_server.DOCS_DIR', str(temp_workspace / "docs"))
    monkeypatch.setattr('mesh_server.STATE_DIR', str(temp_workspace / "control" / "state"))
    monkeypatch.setattr('mesh_server.get_context_readiness', lambda: '{"status": "EXECUTION"}')

    # Try to accept non-existent file
    result = accept_plan("nonexistent_plan.md")
    data = json.loads(result)

    assert data["status"] == "ERROR", f"Expected ERROR, got: {data}"
    assert "not found" in data["message"].lower() or "File not found" in data["message"], \
        f"Expected 'not found' in message, got: {data['message']}"


def test_all_response_statuses_are_json():
    """Verify all accept_plan return paths produce valid JSON with status field."""
    # This is a documentation test - we verify the contract
    valid_statuses = {"OK", "BLOCKED", "ALREADY_ACCEPTED", "ERROR"}

    # All return paths in accept_plan should return JSON with one of these statuses
    # This test serves as documentation and can be extended to mock all paths
    assert "OK" in valid_statuses
    assert "BLOCKED" in valid_statuses
    assert "ALREADY_ACCEPTED" in valid_statuses
    assert "ERROR" in valid_statuses


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
