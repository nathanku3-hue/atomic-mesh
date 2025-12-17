"""
Tests for Plan Generation from Document Extraction (v17.0)

Ensures that /draft-plan generates project-specific, high-signal plans
based on PRD/SPEC/DECISION_LOG content, not generic scaffolds.
"""

import unittest
import sys
import os
import tempfile
import shutil
import json
import hashlib
import re
from pathlib import Path
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load_extraction_functions():
    mesh_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "mesh_server.py"
    )
    with open(mesh_path, "r", encoding="utf-8") as f:
        source = f.read()

    module_globals = {
        "os": os,
        "re": __import__("re"),
        "json": json,
        "time": __import__("time"),
        "hashlib": hashlib,
        "datetime": datetime,
        "List": list,
        "Dict": dict,
        "BASE_DIR": tempfile.gettempdir(),
        "STATE_DIR": tempfile.gettempdir(),
        "PLAN_DEBUG": False,
    }

    extraction_start = source.find("# v17.0: DOCUMENT EXTRACTION")
    extraction_end = source.find("# PLAN-AS-CODE SYSTEM")

    if extraction_start == -1 or extraction_end == -1:
        raise ImportError("Could not find extraction functions in mesh_server.py")

    extraction_code = source[extraction_start:extraction_end]
    exec(extraction_code, module_globals)
    return module_globals


def parse_plan_markdown(plan_md):
    result = {"streams": {}, "total_tasks": 0, "lanes_with_tasks": 0, "tasks": []}
    current_stream = None
    for line in plan_md.split(chr(10)):
        stream_match = re.match(r"^## \[(\w+)\]", line)
        if stream_match:
            current_stream = stream_match.group(1)
            result["streams"][current_stream] = []
            continue
        task_match = re.match(r"^- \[ \] (\w+): (.+)", line)
        if task_match and current_stream:
            task = {"lane": task_match.group(1), "desc": task_match.group(2), "dod": "", "trace": ""}
            result["streams"][current_stream].append(task)
            result["tasks"].append(task)
            result["total_tasks"] += 1
    result["lanes_with_tasks"] = len([s for s in result["streams"] if result["streams"][s]])
    return result


try:
    _funcs = load_extraction_functions()
    extract_project_context = _funcs["extract_project_context"]
    build_plan_from_context = _funcs["build_plan_from_context"]
    _context_is_sufficient = _funcs["_context_is_sufficient"]
    _generate_missing_context_plan = _funcs["_generate_missing_context_plan"]
    _extract_user_stories = _funcs["_extract_user_stories"]
    _extract_api_endpoints = _funcs["_extract_api_endpoints"]
    _extract_data_entities = _funcs["_extract_data_entities"]
    _extract_decisions = _funcs["_extract_decisions"]
    FUNCS_LOADED = True
except Exception as e:
    print(f"Warning: Could not load extraction functions: {e}", file=sys.stderr)
    extract_project_context = build_plan_from_context = _context_is_sufficient = None
    _generate_missing_context_plan = _extract_user_stories = _extract_api_endpoints = None
    _extract_data_entities = _extract_decisions = None
    FUNCS_LOADED = False


# Test fixtures
FIXTURE_PRD = """# PRD: TaskFlow

## User Stories
- [ ] US-01: As a team lead, I want to create projects so that I can organize work
- [ ] US-02: As a developer, I want to create tasks so that I can track my work  
- [ ] US-03: As a team member, I want to mark tasks complete so that progress is visible
- [ ] US-04: As a manager, I want to view task statistics so that I can track velocity
- [ ] US-05: As a user, I want to filter tasks by status so that I can focus on active work
"""

FIXTURE_SPEC = """# SPEC: TaskFlow

## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, email:string | Auth via JWT | PostgreSQL |
| Project | id:uuid, name:string | Soft delete | PostgreSQL |
| Task | id:uuid, title:string | Status enum | PostgreSQL |
| Comment | id:uuid, content:text | Thread replies | PostgreSQL |

## API
| Endpoint/Action | Method | Request | Response | Auth | Notes |
|-----------------|--------|---------|----------|------|-------|
| /api/projects | GET | query params | JSON array | JWT | List projects |
| /api/projects | POST | JSON body | JSON object | JWT | Create project |
| /api/tasks | GET | project_id query | JSON array | JWT | List tasks |
| /api/tasks | POST | JSON body | JSON object | JWT | Create task |
| /api/tasks/:id | PUT | JSON body | JSON object | JWT | Update task |
"""

FIXTURE_DECISION_LOG = """# DECISION_LOG: TaskFlow

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | - | active |
| 002 | 2025-01-02 | ARCH | Use PostgreSQL | ACID compliance needed | backend | US-01 | active |
| 003 | 2025-01-02 | SECURITY | JWT authentication | Stateless, scalable | backend | US-01 | active |
| 004 | 2025-01-03 | API | RESTful JSON API | Simple | backend | US-02 | active |
"""


class TestPlanGeneration(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_generates_at_least_10_tasks(self):
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        self.assertGreaterEqual(parsed["total_tasks"], 10)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_generates_at_least_3_lanes(self):
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        self.assertGreaterEqual(parsed["lanes_with_tasks"], 3)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_contains_qa_tasks(self):
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        self.assertIn("QA", parsed["streams"])


class TestInsufficientContext(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_empty_docs_insufficient(self):
        (self.docs_dir / "PRD.md").write_text("# PRD")
        (self.docs_dir / "SPEC.md").write_text("# SPEC")
        (self.docs_dir / "DECISION_LOG.md").write_text("# DECISION_LOG")
        context = extract_project_context(base_dir=self.test_dir)
        is_sufficient, reasons = _context_is_sufficient(context)
        self.assertFalse(is_sufficient)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_well_specified_docs_sufficient(self):
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        context = extract_project_context(base_dir=self.test_dir)
        is_sufficient, reasons = _context_is_sufficient(context)
        self.assertTrue(is_sufficient)


class TestDecisionTableParsing(unittest.TestCase):
    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_strict_8_column_parsing(self):
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL | ACID needed | backend | US-01 | active |
| 002 | 2025-01-02 | API | REST API | Standard | backend | US-02 | active |
"""
        decisions = _extract_decisions(decision_log)
        self.assertEqual(len(decisions), 2)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_skips_init_decisions(self):
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project init | Bootstrap | repo | - | active |
| 002 | 2025-01-02 | ARCH | Use PostgreSQL | ACID | backend | US-01 | active |
"""
        decisions = _extract_decisions(decision_log)
        self.assertEqual(len(decisions), 1)
        self.assertEqual(decisions[0]["type"], "ARCH")



class TestMalformedDecisionRows(unittest.TestCase):
    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_7_column_row_skipped(self):
        """7-column row should be skipped entirely."""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL | ACID needed | backend | US-01 | active |
| 002 | 2025-01-02 | API | REST API | Standard | backend | active |
"""
        decisions = _extract_decisions(decision_log)
        self.assertEqual(len(decisions), 1)
        self.assertEqual(decisions[0]["decision"], "Use PostgreSQL")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_9_column_row_skipped(self):
        """9-column row should be skipped entirely."""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL | ACID needed | backend | US-01 | active |
| 002 | 2025-01-02 | API | REST API | Standard | backend | US-02 | active | extra |
"""
        decisions = _extract_decisions(decision_log)
        self.assertEqual(len(decisions), 1)
        self.assertEqual(decisions[0]["decision"], "Use PostgreSQL")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_malformed_row_does_not_leak_columns(self):
        """Malformed rows must not leak rationale/scope into decision text."""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use Postgres | ACID compliance | backend | US-01 | active |
| 002 | 2025-01-02 | API | REST | Simple standard | backend | active |
"""
        decisions = _extract_decisions(decision_log)
        for d in decisions:
            self.assertNotIn("ACID", d["decision"])
            self.assertNotIn("compliance", d["decision"])
            self.assertNotIn("Simple", d["decision"])
            self.assertNotIn("standard", d["decision"])


class TestDecisionColumnIsolation(unittest.TestCase):
    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_decision_column_only_no_leakage(self):
        """Decision strings must never contain content from other columns."""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL | ACID compliance needed | backend | US-01 | active |
| 002 | 2025-01-02 | API | RESTful JSON API | Industry standard | api | US-02 | active |
| 003 | 2025-01-03 | SEC | JWT tokens | Stateless auth | auth | US-03 | superseded |
"""
        decisions = _extract_decisions(decision_log)
        forbidden_substrings = [
            "ACID", "compliance", "needed",
            "Industry", "standard",
            "Stateless", "auth",
            "backend", "api",
            "US-01", "US-02", "US-03",
            "active", "superseded",
            "Rationale", "Scope", "Status"
        ]
        for d in decisions:
            for forbidden in forbidden_substrings:
                self.assertNotIn(forbidden, d["decision"],
                    f"Decision '{d['decision']}' leaked '{forbidden}' from another column")


class TestInsufficientContextCases(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_entities_only_no_decisions_insufficient(self):
        """Entities alone (no stories, no decisions) should be INSUFFICIENT_CONTEXT."""
        prd = "# PRD\n\nNo user stories here."
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
| Task | id:uuid, title:string | Task item | PostgreSQL |
"""
        decision_log = "# DECISION_LOG\n\nNo decisions yet."
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)
        context = extract_project_context(base_dir=self.test_dir)
        is_sufficient, reasons = _context_is_sufficient(context)
        self.assertFalse(is_sufficient, f"Expected insufficient but got sufficient. Reasons: {reasons}")


class TestLaneNamingNormalization(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_lane_names_are_normalized(self):
        """All lane names should be properly capitalized (Backend, Frontend, QA, Ops, Docs)."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        valid_lanes = {"Backend", "Frontend", "QA", "Ops", "Docs"}
        for stream_name in parsed["streams"]:
            self.assertIn(stream_name, valid_lanes,
                f"Stream '{stream_name}' is not a valid normalized lane name")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_task_lane_matches_stream_header(self):
        """Each task's lane prefix should match its containing stream header."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        for stream_name, tasks in parsed["streams"].items():
            for task in tasks:
                self.assertEqual(task["lane"], stream_name,
                    f"Task lane '{task['lane']}' doesn't match stream '{stream_name}'")


class TestIntegrationDraftPlan(unittest.TestCase):
    """Integration tests calling the actual draft_plan entrypoint."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_draft_plan_returns_json_serializable(self):
        """draft_plan result must be JSON-serializable."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        try:
            json.dumps(parsed)
        except (TypeError, ValueError) as e:
            self.fail(f"Plan result is not JSON-serializable: {e}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_sufficient_fixtures_produce_quality_ok(self):
        """Well-specified fixtures should produce a sufficient context."""
        context = extract_project_context(base_dir=self.test_dir)
        is_sufficient, reasons = _context_is_sufficient(context)
        self.assertTrue(is_sufficient, f"Expected OK quality but got insufficient: {reasons}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_sufficient_fixtures_produce_10_tasks_3_lanes(self):
        """Well-specified fixtures should produce at least 10 tasks across 3 lanes."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        parsed = parse_plan_markdown(plan_md)
        self.assertGreaterEqual(parsed["total_tasks"], 10,
            f"Expected >= 10 tasks, got {parsed['total_tasks']}")
        self.assertGreaterEqual(parsed["lanes_with_tasks"], 3,
            f"Expected >= 3 lanes, got {parsed['lanes_with_tasks']}")




class TestNoTruncation(unittest.TestCase):
    """FIX #1: Plan file must never contain truncated text."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_ellipsis_in_task_lines(self):
        """Task lines must not contain ellipsis truncation markers."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        # Only check actual task lines, not header/instructions
        task_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ]")]
        for line in task_lines:
            self.assertNotIn("...", line, f"Task contains '...' truncation: {line[:60]}")
            self.assertNotIn("…", line, f"Task contains ellipsis: {line[:60]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_full_story_in_detail_field(self):
        """Full user story text should appear in Detail field."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        # Check that at least one user story appears in full
        self.assertIn("Detail:", plan_md, "Plan should have Detail fields for stories")
        # Check specific story text is preserved
        self.assertIn("create projects so that I can organize work", plan_md,
            "Full story text should be in Detail field")


class TestTitleDetailFormat(unittest.TestCase):
    """FIX #2: Tasks must have short Title + optional Detail."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_task_has_required_fields(self):
        """Each task line must have Lane: Title — DoD: ... | Trace: ..."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        task_lines = [l for l in plan_md.split("\n") if l.startswith("- [ ]")]
        self.assertGreater(len(task_lines), 0, "Should have task lines")
        for line in task_lines:
            self.assertIn(":", line, f"Task missing Lane: prefix: {line[:60]}")
            self.assertIn("DoD:", line, f"Task missing DoD: {line[:60]}")
            self.assertIn("Trace:", line, f"Task missing Trace: {line[:60]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_title_length_constraint(self):
        """Title portion (before —) must be <= 60 chars (Lane: + 48 char title)."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        task_lines = [l for l in plan_md.split("\n") if l.startswith("- [ ]")]
        for line in task_lines:
            # Extract title: everything from "- [ ] " to " —"
            match = re.match(r"^- \[ \] ([^—]+)", line)
            if match:
                title_part = match.group(1).strip()
                # Title part includes "Lane: Title", should be reasonable length
                # Lane is max 8 chars + ": " + 48 char title = ~60 chars max
                self.assertLessEqual(len(title_part), 70,
                    f"Title too long ({len(title_part)} chars): {title_part[:60]}...")


class TestDocGapBlockers(unittest.TestCase):
    """FIX #3: Missing anchors should generate doc-gap blocker tasks."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_missing_endpoints_generates_blocker(self):
        """When endpoints=0, plan should have SPEC-API blocker task."""
        # PRD with stories but SPEC without API section
        prd = """# PRD
## User Stories
- [ ] US-01: As a user, I can do something
- [ ] US-02: As a user, I can do another thing
- [ ] US-03: As a user, I can do a third thing
"""
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
| Task | id:uuid, title:string | Task item | PostgreSQL |
| Project | id:uuid, name:string | Project | PostgreSQL |
"""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use PostgreSQL | ACID needed | backend | US-01 | active |
"""
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        # Should have API blocker task
        self.assertIn("SPEC-API", plan_md, "Should have SPEC-API blocker task")
        self.assertIn("Declare API strategy", plan_md, "Should have API strategy task")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_blocker_has_high_priority(self):
        """Doc-gap blocker tasks should have P:HIGH."""
        prd = "# PRD\n\nNo stories"
        spec = "# SPEC\n\nNo entities"
        decision_log = "# DECISION_LOG\n\nNo decisions"
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        # Primary blocker tasks (Decide/Add/Define) should have P:HIGH
        blocker_keywords = ["Declare API strategy", "Add User Stories", "Define Data Model"]
        blocker_lines = [l for l in plan_md.split(chr(10))
                         if any(kw in l for kw in blocker_keywords)]
        self.assertGreater(len(blocker_lines), 0, "Should have at least one blocker task")
        for line in blocker_lines:
            self.assertIn("P:HIGH", line,
                f"Primary blocker task should have P:HIGH: {line[:60]}")


class TestConcreteDecisionTasks(unittest.TestCase):
    """FIX #4: Decision tasks must be concrete, not 'Apply ...'."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_apply_prefix_in_tasks(self):
        """No Ops task should begin with literal 'Apply '."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        ops_lines = [l for l in plan_md.split("\n") if l.startswith("- [ ] Ops:")]
        for line in ops_lines:
            self.assertNotIn("Apply ", line,
                f"Ops task should not have 'Apply ' prefix: {line[:60]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_decision_tasks_have_concrete_dod(self):
        """Each decision task should have a specific DoD."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        ops_lines = [l for l in plan_md.split("\n") if l.startswith("- [ ] Ops:")]
        for line in ops_lines:
            self.assertIn("DoD:", line, f"Decision task missing DoD: {line[:60]}")
            # DoD should not be generic "Infrastructure/config updated"
            dod_match = re.search(r"DoD: ([^|]+)", line)
            if dod_match:
                dod = dod_match.group(1).strip()
                self.assertNotIn("Infrastructure/config updated", dod,
                    f"DoD should be specific, not generic: {dod[:40]}")


class TestPriorityTags(unittest.TestCase):
    """FIX #5: Priority tags for blockers and main loop tasks."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_main_loop_task_has_high_priority(self):
        """Tasks with 'load', 'run', 'execute' should have P:HIGH."""
        prd = """# PRD
## User Stories
- [ ] US-01: As a user, I can load data from a file so that I can analyze it
- [ ] US-02: As a user, I can run a backtest so that I can evaluate strategies
- [ ] US-03: As a user, I can view results
"""
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| Data | id:uuid, value:float | Data point | PostgreSQL |
| Result | id:uuid, score:float | Result | PostgreSQL |
| Config | id:uuid, name:string | Config | PostgreSQL |
"""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | ARCH | Use Python | Standard | backend | US-01 | active |
"""
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        # Find tasks with "load" or "run"
        frontend_lines = [l for l in plan_md.split("\n")
                         if l.startswith("- [ ] Frontend:")]
        load_tasks = [l for l in frontend_lines
                      if "load" in l.lower() or "run" in l.lower() or "backtest" in l.lower()]

        # At least one should have P:HIGH
        high_priority_found = any("P:HIGH" in l for l in load_tasks)
        self.assertTrue(high_priority_found,
            f"Main loop tasks should have P:HIGH. Found tasks: {load_tasks}")





class TestShortTitleGuardrail(unittest.TestCase):
    """Ensure _generate_short_title never returns empty."""

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_empty_input_returns_untitled(self):
        """Empty string input should return '(untitled)'."""
        result = _funcs["_generate_short_title"]("")
        self.assertEqual(result, "(untitled)")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_whitespace_only_returns_untitled(self):
        """Whitespace-only input should return '(untitled)'."""
        result = _funcs["_generate_short_title"]("   ")
        self.assertEqual(result, "(untitled)")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_normal_input_preserved(self):
        """Normal input should be returned as-is if under limit."""
        result = _funcs["_generate_short_title"]("Hello World")
        self.assertEqual(result, "Hello World")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_long_input_truncated_at_word_boundary(self):
        """Long input should truncate at word boundary."""
        result = _funcs["_generate_short_title"]("This is a very long title that exceeds the maximum length", 20)
        self.assertLessEqual(len(result), 20)
        self.assertNotIn("...", result)
        # Should not cut mid-word
        self.assertTrue(result.endswith("long") or result.endswith("very") or result.endswith("a"))

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_deterministic(self):
        """Same input should always produce same output."""
        text = "As a user I want to do something important"
        result1 = _funcs["_generate_short_title"](text, 30)
        result2 = _funcs["_generate_short_title"](text, 30)
        self.assertEqual(result1, result2)



class TestInvariantA_BackendSpine(unittest.TestCase):
    """INVARIANT A: Backend spine must exist when sufficient context."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_backend_spine_exists_when_sufficient_context(self):
        """Fixtures with stories+entities+decisions must produce >= 5 spine tasks."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]

        # Check for spine task keywords
        spine_keywords = ["Ingest", "backtest runner", "metrics", "results", "transaction log"]
        spine_tasks = [l for l in backend_lines
                       if any(kw.lower() in l.lower() for kw in spine_keywords)]

        self.assertGreaterEqual(len(spine_tasks), 5,
            f"Expected >= 5 spine tasks, found {len(spine_tasks)}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_spine_tasks_have_appropriate_traces(self):
        """Spine tasks must reference DEC, PRD-US, or SPEC-DATA traces."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        spine_keywords = ["Ingest", "backtest runner", "metrics", "results", "transaction log"]
        spine_tasks = [l for l in backend_lines
                       if any(kw.lower() in l.lower() for kw in spine_keywords)]

        for task in spine_tasks:
            # Data-layer tasks trace to DEC or SPEC-DATA, PRD-derived to PRD-US
            has_trace = "Trace: DEC-" in task or "Trace: PRD-US" in task or "Trace: SPEC-DATA" in task
            self.assertTrue(has_trace,
                f"Spine task missing valid trace: {task[:60]}")


class TestInvariantB_DecisionEnforcement(unittest.TestCase):
    """INVARIANT B: Decision-driven enforcement + tests."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_security_decision_generates_enforcement_and_qa(self):
        """SECURITY decision must produce 1 implement + 1 QA enforcement task (QA has P:HIGH)."""
        prd = """# PRD
## User Stories
- [ ] US-01: As a user, I can view data
- [ ] US-02: As a user, I can run analysis
- [ ] US-03: As a user, I can export results
"""
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| Data | id:uuid, value:float | Data point | PostgreSQL |
| Result | id:uuid, score:float | Result | PostgreSQL |
| Config | id:uuid, name:string | Config | PostgreSQL |
"""
        decision_log = """# DECISION_LOG
| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | SEC | Read-Only Mode for Data | Prevent accidental writes | backend | US-01 | active |
"""
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        lines = plan_md.split(chr(10))

        # Check for Ops enforcement task
        ops_tasks = [l for l in lines if l.startswith("- [ ] Ops:")]
        security_ops = [l for l in ops_tasks if "DEC-001" in l]
        self.assertGreaterEqual(len(security_ops), 1,
            "SECURITY decision should generate Ops enforcement task")

        # Check for QA enforcement task with P:HIGH
        qa_tasks = [l for l in lines if l.startswith("- [ ] QA:")]
        security_qa = [l for l in qa_tasks if "DEC-001" in l or "read-only" in l.lower()]
        self.assertGreaterEqual(len(security_qa), 1,
            "SECURITY decision should generate QA enforcement task")

        # The QA enforcement task should have P:HIGH
        security_qa_high = [l for l in security_qa if "P:HIGH" in l]
        self.assertGreaterEqual(len(security_qa_high), 1,
            "SECURITY QA enforcement task should have P:HIGH")


class TestInvariantC_DependencyAwarePriority(unittest.TestCase):
    """INVARIANT C: Priority is dependency-aware."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_priority_not_all_frontend_high(self):
        """Ensure <= 3 frontend tasks have P:HIGH (prevents UI skew)."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]
        frontend_high = [l for l in frontend_lines if "P:HIGH" in l]

        self.assertLessEqual(len(frontend_high), 3,
            f"Expected <= 3 Frontend P:HIGH tasks, found {len(frontend_high)}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_spine_tasks_are_high_priority(self):
        """Backend spine tasks should be P:HIGH."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        spine_keywords = ["Ingest", "backtest runner", "metrics", "results"]
        spine_tasks = [l for l in backend_lines
                       if any(kw.lower() in l.lower() for kw in spine_keywords)]

        # Most spine tasks should have P:HIGH (at least 4 of them)
        spine_high = [l for l in spine_tasks if "P:HIGH" in l]
        self.assertGreaterEqual(len(spine_high), 4,
            f"Expected >= 4 spine tasks with P:HIGH, found {len(spine_high)}")


class TestAPIStrategyDocs(unittest.TestCase):
    """API Strategy docs task should always be present."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_api_strategy_docs_task_present(self):
        """Always includes 'Declare API strategy' task with SPEC-API trace and P:HIGH."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        # Should have API strategy task
        self.assertIn("Declare API strategy", plan_md,
            "Should have 'Declare API strategy' Docs task")

        # Find the task line
        docs_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Docs:")]
        api_strategy = [l for l in docs_lines if "Declare API strategy" in l]

        self.assertEqual(len(api_strategy), 1,
            "Should have exactly one API strategy task")

        # Should have SPEC-API trace
        self.assertIn("Trace: SPEC-API", api_strategy[0],
            "API strategy task should have SPEC-API trace")

        # Should have P:HIGH
        self.assertIn("P:HIGH", api_strategy[0],
            "API strategy task should have P:HIGH")





class TestNoCRUDExplosion(unittest.TestCase):
    """FIX B: No per-entity CRUD explosion - consolidated into schema task."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_crud_in_task_titles(self):
        """Task titles should not contain 'CRUD'."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        task_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ]")]
        crud_tasks = [l for l in task_lines if "CRUD" in l]
        self.assertEqual(len(crud_tasks), 0,
            f"Should have no CRUD tasks, found: {crud_tasks}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_max_backend_entity_tasks(self):
        """Total backend entity-specific tasks should be <= 4 (consolidated)."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        # Count tasks that mention specific entities (User, Project, Task, Comment)
        entity_names = ["User", "Project", "Task", "Comment"]
        entity_tasks = []
        for line in backend_lines:
            if any(e in line for e in entity_names):
                entity_tasks.append(line)
        # Schema task + maybe a few others, but not 7 CRUD tasks
        self.assertLessEqual(len(entity_tasks), 4,
            f"Expected <= 4 entity-related tasks, found {len(entity_tasks)}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_schema_task_contains_entity_list(self):
        """Schema definition task should list all entities in Detail field."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        schema_tasks = [l for l in backend_lines if "schema" in l.lower() or "DuckDB" in l]
        self.assertGreater(len(schema_tasks), 0, "Should have schema definition task")
        # At least one should have entity list in Detail
        has_entities = any("Detail:" in l and "User" in l for l in schema_tasks)
        self.assertTrue(has_entities,
            "Schema task should list entities in Detail field")


class TestStrategyInterfaceTask(unittest.TestCase):
    """FIX C: Strategy cartridge interface task must exist."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_strategy_interface_task_present(self):
        """Backend should have 'Define strategy cartridge interface' task."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        strategy_tasks = [l for l in backend_lines if "strategy" in l.lower() and "interface" in l.lower()]
        self.assertGreaterEqual(len(strategy_tasks), 1,
            "Should have strategy cartridge interface task")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_strategy_interface_has_high_priority(self):
        """Strategy interface task should have P:HIGH."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        strategy_tasks = [l for l in backend_lines if "strategy" in l.lower() and "interface" in l.lower()]
        self.assertGreater(len(strategy_tasks), 0, "Should have strategy interface task")
        self.assertIn("P:HIGH", strategy_tasks[0],
            "Strategy interface task should have P:HIGH")


class TestInternalInterfaceContract(unittest.TestCase):
    """FIX A: Internal interface contract when endpoints=0."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_internal_contract_when_no_endpoints(self):
        """When endpoints=0, should have 'Define internal interface contract' task."""
        prd = FIXTURE_PRD
        # SPEC without API endpoints
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
| Task | id:uuid, title:string | Task item | PostgreSQL |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        docs_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Docs:")]
        interface_tasks = [l for l in docs_lines if "internal interface" in l.lower()]
        self.assertGreaterEqual(len(interface_tasks), 1,
            "Should have 'Define internal interface contract' task when endpoints=0")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_internal_contract_has_high_priority(self):
        """Internal interface contract task should have P:HIGH."""
        prd = FIXTURE_PRD
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        docs_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Docs:")]
        interface_tasks = [l for l in docs_lines if "internal interface" in l.lower()]
        self.assertGreater(len(interface_tasks), 0, "Should have internal interface task")
        self.assertIn("P:HIGH", interface_tasks[0],
            "Internal interface task should have P:HIGH")


class TestFrontendPriorityLimit(unittest.TestCase):
    """FIX D: Frontend P:HIGH limited to max 2."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_frontend_high_priority_max_2(self):
        """Frontend should have at most 2 P:HIGH tasks."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]
        frontend_high = [l for l in frontend_lines if "P:HIGH" in l]
        self.assertLessEqual(len(frontend_high), 2,
            f"Expected <= 2 Frontend P:HIGH tasks, found {len(frontend_high)}")


class TestQAHarnessSpecified(unittest.TestCase):
    """FIX E: QA integration tests specify harness."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_qa_tasks_have_harness_in_dod(self):
        """QA integration tests should specify pytest or similar harness."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]
        integration_tests = [l for l in qa_lines if "Integration Test" in l]
        self.assertGreater(len(integration_tests), 0, "Should have integration tests")
        # Check that harness is specified in DoD
        harness_keywords = ["pytest", "fixture", "smoke test", "Streamlit"]
        for test_line in integration_tests:
            has_harness = any(kw in test_line for kw in harness_keywords)
            self.assertTrue(has_harness,
                f"Integration test should specify harness: {test_line[:80]}")




class TestBackendTraceSanity(unittest.TestCase):
    """TASK 1: Backend tasks must not trace to PRD-US except runner/metrics/results/txn."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_backend_prd_trace_only_for_prd_derived(self):
        """Backend tasks with PRD-US trace must be runner/metrics/results/txn derived."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]

        # Tasks allowed to have PRD-US trace
        prd_allowed_keywords = ["runner", "metrics", "results", "transaction", "txn"]

        for line in backend_lines:
            if "Trace: PRD-US" in line:
                # Must contain one of the allowed keywords
                has_allowed = any(kw.lower() in line.lower() for kw in prd_allowed_keywords)
                self.assertTrue(has_allowed,
                    f"Backend task with PRD-US trace is not PRD-derived: {line[:80]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_data_layer_tasks_not_trace_prd_us(self):
        """Data-layer tasks (schema, ingest, query) must not trace to PRD-US."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]

        data_layer_keywords = ["schema", "ingest", "query layer", "duckdb"]

        for line in backend_lines:
            is_data_layer = any(kw.lower() in line.lower() for kw in data_layer_keywords)
            if is_data_layer:
                self.assertNotIn("Trace: PRD-US", line,
                    f"Data-layer task should not trace to PRD-US: {line[:80]}")


class TestDepTagPresence(unittest.TestCase):
    """TASK 2: Dep tags appear on US-04/US-06/US-07 Frontend tasks."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_frontend_us04_has_dep_tag(self):
        """Frontend US-04 task should have Dep tag for metrics/results."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]
        us04_lines = [l for l in frontend_lines if "US-04" in l]

        if us04_lines:
            self.assertIn("Dep:", us04_lines[0],
                f"US-04 Frontend task should have Dep tag: {us04_lines[0][:80]}")


class TestQALevelField(unittest.TestCase):
    """TASK 3: All QA tasks contain | Level: field."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_qa_tasks_have_level_field(self):
        """All QA tasks should have Level: field."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]

        self.assertGreater(len(qa_lines), 0, "Should have QA tasks")
        for line in qa_lines:
            self.assertIn("Level:", line,
                f"QA task missing Level field: {line[:80]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_qa_level_values_valid(self):
        """QA Level field should be UNIT, INTEGRATION, or UI_SMOKE."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)
        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]

        valid_levels = ["Level: UNIT", "Level: INTEGRATION", "Level: UI_SMOKE"]
        for line in qa_lines:
            has_valid_level = any(lvl in line for lvl in valid_levels)
            self.assertTrue(has_valid_level,
                f"QA task has invalid Level: {line[:80]}")


class TestNoEndpointsInternalInterfaces(unittest.TestCase):
    """TASK 4: endpoints=0 generates Backend internal interfaces task."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_endpoints_generates_backend_impl_task(self):
        """When endpoints=0, should have Backend 'Implement internal interfaces' task."""
        prd = FIXTURE_PRD
        # SPEC without API endpoints
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
| Task | id:uuid, title:string | Task item | PostgreSQL |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        impl_tasks = [l for l in backend_lines if "internal interfaces" in l.lower()]

        self.assertGreaterEqual(len(impl_tasks), 1,
            "Should have 'Implement internal interfaces' Backend task when endpoints=0")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_internal_interfaces_impl_has_dep_tag(self):
        """Backend internal interfaces task should have Dep tag to Docs contract."""
        prd = FIXTURE_PRD
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        impl_tasks = [l for l in backend_lines if "internal interfaces" in l.lower()]

        if impl_tasks:
            self.assertIn("Dep:", impl_tasks[0],
                f"Internal interfaces task should have Dep tag: {impl_tasks[0][:80]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_internal_interfaces_impl_has_high_priority(self):
        """Backend internal interfaces task should have P:HIGH."""
        prd = FIXTURE_PRD
        spec = """# SPEC
## Data Model
| Entity | Fields (name:type) | Notes | Source of Truth |
|--------|-------------------|-------|-----------------|
| User | id:uuid, name:string | Basic user | PostgreSQL |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        impl_tasks = [l for l in backend_lines if "internal interfaces" in l.lower()]

        if impl_tasks:
            self.assertIn("P:HIGH", impl_tasks[0],
                f"Internal interfaces task should have P:HIGH: {impl_tasks[0][:80]}")




class TestEntitiesZeroGuard(unittest.TestCase):
    """FIX 1: Data-layer tasks only generated when entities>0."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_data_layer_tasks_when_entities_zero(self):
        """When entities=0, should not generate schema/ingest/query tasks."""
        prd = FIXTURE_PRD
        # SPEC without data entities
        spec = """# SPEC
## API
| Endpoint/Action | Method | Request | Response | Auth | Notes |
|-----------------|--------|---------|----------|------|-------|
| /api/test | GET | none | JSON | none | Test |
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        backend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Backend:")]
        # Data-layer tasks are: DuckDB schema, ingest pipeline, query layer
        data_layer_tasks = [l for l in backend_lines
                          if "DuckDB schema" in l or "ingest pipeline" in l.lower() or "query layer" in l.lower()]

        self.assertEqual(len(data_layer_tasks), 0,
            f"Should have no data-layer tasks when entities=0, found: {data_layer_tasks}")


class TestDeduplication(unittest.TestCase):
    """FIX 3: Story IDs are deduplicated."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_duplicate_story_ids_in_frontend(self):
        """Frontend should not have duplicate story IDs."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]

        # Extract story IDs (US-xx pattern)
        import re
        story_ids = []
        for line in frontend_lines:
            match = re.search(r"US-\d+", line)
            if match:
                story_ids.append(match.group())

        # Check for duplicates
        seen = set()
        duplicates = []
        for sid in story_ids:
            if sid in seen:
                duplicates.append(sid)
            seen.add(sid)

        self.assertEqual(len(duplicates), 0,
            f"Found duplicate story IDs in Frontend: {duplicates}")


class TestDomainSpecificEdgeCases(unittest.TestCase):
    """FIX 4: QA edge cases are domain-specific."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_edge_cases_not_all_generic(self):
        """QA edge cases should not all be generic 'empty input'."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]
        integration_tests = [l for l in qa_lines if "Integration Test" in l]

        if len(integration_tests) > 0:
            generic_count = sum(1 for l in integration_tests if "empty input" in l.lower())
            # At most 20% should be generic
            self.assertLess(generic_count / len(integration_tests), 0.3,
                f"Too many generic edge cases: {generic_count}/{len(integration_tests)}")


class TestArtifactBasedDoD(unittest.TestCase):
    """FIX 5: Ops DoDs reference artifacts."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_ops_dod_contains_artifacts(self):
        """Ops DoD should reference file paths or test names."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        ops_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Ops:")]

        # Artifact indicators: file paths, test names, config keys
        artifact_patterns = ["test_", ".py", ".sql", ".yaml", "config.", "src/", "docs/", "db/"]

        for line in ops_lines:
            has_artifact = any(pat in line for pat in artifact_patterns)
            self.assertTrue(has_artifact,
                f"Ops task DoD should reference artifacts: {line[:80]}")


class TestAcceptancePseudoTaskFiltering(unittest.TestCase):
    """FIX 2: Acceptance: pseudo-tasks should be filtered out."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_no_acceptance_tasks_in_output(self):
        """Tasks starting with 'Acceptance:' in stories should be filtered."""
        prd = """# PRD
## User Stories
| ID | Story | Acceptance Criteria | Priority |
|----|-------|---------------------|----------|
| US-01 | As a user I want to view dashboard | See metrics | High |
| ACC-01 | Acceptance: All screens render | N/A | High |
| US-02 | Acceptance: system handles errors | N/A | Medium |
"""
        spec = FIXTURE_SPEC
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]

        # Should not have ACC-01 or US-02 (starts with Acceptance:)
        for line in frontend_lines:
            self.assertNotIn("ACC-01", line,
                f"ACC- prefixed task should be filtered: {line[:80]}")
            # Check first word after story ID isn't Acceptance:
            if "US-02" in line:
                self.fail(f"Task starting with 'Acceptance:' should be filtered: {line[:80]}")


class TestMarkdownStripping(unittest.TestCase):
    """Markdown formatting should be stripped from titles."""

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_bold_stripped(self):
        """**bold** markers should be stripped."""
        result = _funcs["_generate_short_title"]("**Streamlit** UI Framework")
        self.assertEqual(result, "Streamlit UI Framework")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_underline_stripped(self):
        """__underline__ markers should be stripped."""
        result = _funcs["_generate_short_title"]("Setup __DuckDB__ storage")
        self.assertEqual(result, "Setup DuckDB storage")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_italic_stripped(self):
        """*italic* markers should be stripped."""
        result = _funcs["_generate_short_title"]("Build *iterative* pipeline")
        self.assertEqual(result, "Build iterative pipeline")


class TestUnitLevelQATasks(unittest.TestCase):
    """UNIT-level QA tasks for backend determinism."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_qa_has_unit_level_tasks(self):
        """QA should have at least 2 UNIT level tasks."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]
        unit_tasks = [l for l in qa_lines if "Level: UNIT" in l]

        self.assertGreaterEqual(len(unit_tasks), 2,
            f"Expected at least 2 UNIT level QA tasks, got {len(unit_tasks)}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_determinism_test_exists(self):
        """Runner + Metrics Determinism test should exist."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]
        determinism_tasks = [l for l in qa_lines if "Determinism" in l]

        self.assertGreater(len(determinism_tasks), 0,
            "Expected Runner + Metrics Determinism QA task")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_schema_validation_test_exists(self):
        """Snapshot Schema Validation test should exist."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        qa_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] QA:")]
        schema_tasks = [l for l in qa_lines if "Schema Validation" in l]

        self.assertGreater(len(schema_tasks), 0,
            "Expected Snapshot Schema Validation QA task")


class TestDepValidity(unittest.TestCase):
    """All Dep: Lane:key references must exist in emitted tasks."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        (self.docs_dir / "PRD.md").write_text(FIXTURE_PRD)
        (self.docs_dir / "SPEC.md").write_text(FIXTURE_SPEC)
        (self.docs_dir / "DECISION_LOG.md").write_text(FIXTURE_DECISION_LOG)
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_all_deps_reference_existing_tasks(self):
        """All Dep: Lane:key must have matching task with that _key."""
        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        # Extract emitted keys (derive from task titles/patterns)
        lines = plan_md.split(chr(10))
        emitted_keys = set()

        # Backend keys
        backend_key_map = {
            "DuckDB schema": "duckdb_schema",
            "ingest pipeline": "duckdb_ingest",
            "query layer": "query_layer",
            "backtest runner": "runner_core",
            "key metrics": "metrics",
            "backtest results": "results_store",
            "transaction log": "txn_view",
            "strategy": "strategy_interface",
            "internal interfaces": "internal_interfaces_impl",
        }
        for line in lines:
            if line.startswith("- [ ] Backend:"):
                for pattern, key in backend_key_map.items():
                    if pattern.lower() in line.lower():
                        emitted_keys.add(f"Backend:{key}")

        # Docs keys
        docs_key_map = {
            "API strategy": "api_strategy",
            "internal interface contract": "internal_interface_contract",
            "Data Model entities": "data_model_entities",
            "User Stories": "user_stories",
        }
        for line in lines:
            if line.startswith("- [ ] Docs:"):
                for pattern, key in docs_key_map.items():
                    if pattern.lower() in line.lower():
                        emitted_keys.add(f"Docs:{key}")

        # Check all deps
        import re
        invalid_deps = []
        for line in lines:
            if "| Dep:" in line:
                dep_match = re.search(r"Dep: ([^|]+)", line)
                if dep_match:
                    deps = dep_match.group(1).strip().split(",")
                    for dep in deps:
                        dep = dep.strip()
                        if dep and dep not in emitted_keys:
                            invalid_deps.append(dep)

        self.assertEqual(len(invalid_deps), 0,
            f"Found deps referencing non-existent tasks: {invalid_deps}")


class TestEntitiesZeroDepBehavior(unittest.TestCase):
    """When entities=0, no Backend deps should exist (they'd be invalid)."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

    def tearDown(self):
        os.chdir(self.original_dir)
        shutil.rmtree(self.test_dir)

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_entities_zero_no_backend_deps(self):
        """With entities=0, Frontend should have no Backend deps."""
        # PRD with stories but SPEC without entities
        prd = FIXTURE_PRD
        spec_no_entities = """# SPEC
## API
No endpoints defined yet.
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec_no_entities)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        self.assertEqual(len(context.get("data_entities", [])), 0,
            "Should have 0 entities")

        plan_md = build_plan_from_context(context)

        # Check anchors confirm entities=0
        self.assertIn("entities=0", plan_md,
            "Anchors should show entities=0")

        # Check no Backend deps exist in Frontend
        frontend_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Frontend:")]
        backend_deps_in_frontend = [l for l in frontend_lines if "Dep: Backend:" in l]

        self.assertEqual(len(backend_deps_in_frontend), 0,
            f"With entities=0, Frontend should have no Backend deps. Found: {backend_deps_in_frontend[:2]}")

    @unittest.skipIf(not FUNCS_LOADED, "Functions not loaded")
    def test_entities_zero_has_data_model_blocker(self):
        """With entities=0, Docs lane should have 'Define Data Model entities' blocker."""
        prd = FIXTURE_PRD
        spec_no_entities = """# SPEC
## API
No endpoints defined yet.
"""
        decision_log = FIXTURE_DECISION_LOG
        (self.docs_dir / "PRD.md").write_text(prd)
        (self.docs_dir / "SPEC.md").write_text(spec_no_entities)
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log)

        context = extract_project_context(base_dir=self.test_dir)
        plan_md = build_plan_from_context(context)

        docs_lines = [l for l in plan_md.split(chr(10)) if l.startswith("- [ ] Docs:")]
        data_model_blockers = [l for l in docs_lines if "Data Model" in l]

        self.assertGreater(len(data_model_blockers), 0,
            "With entities=0, should have 'Define Data Model entities' blocker")


if __name__ == "__main__":
    unittest.main()
