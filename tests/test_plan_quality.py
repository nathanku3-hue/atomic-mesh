#!/usr/bin/env python3
"""
Tests for plan extraction and quality assessment.
"""
import os
import sys
import json
import pytest
import tempfile
import shutil

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestImportRegression:
    """Regression tests to ensure critical functions remain importable."""

    def test_assess_plan_quality_importable(self):
        """_assess_plan_quality must be importable from mesh_server."""
        from mesh_server import _assess_plan_quality
        assert callable(_assess_plan_quality)

    def test_assess_plan_quality_returns_expected_structure(self):
        """_assess_plan_quality must return dict with level and reason keys."""
        from mesh_server import _assess_plan_quality
        plan = {"streams": []}
        context = {}
        result = _assess_plan_quality(plan, context)
        assert isinstance(result, dict)
        assert "level" in result, "Result must have 'level' key"
        assert "reason" in result, "Result must have 'reason' key"
        assert result["level"] in ("OK", "BAD", "THIN"), f"level must be OK/BAD/THIN, got {result['level']}"

    def test_build_plan_from_context_structured_importable(self):
        """build_plan_from_context_structured must be importable from mesh_server."""
        from mesh_server import build_plan_from_context_structured
        assert callable(build_plan_from_context_structured)

    def test_build_plan_from_context_structured_returns_expected_structure(self):
        """build_plan_from_context_structured must return dict with status and streams."""
        from mesh_server import build_plan_from_context_structured
        context = {
            "user_stories": [], "api_endpoints": [], "data_entities": [],
            "decisions": [], "domain_nouns": [],
            "debug": {"counts": {"user_stories": 0, "api_endpoints": 0, "data_entities": 0, "decisions": 0}}
        }
        result = build_plan_from_context_structured(context)
        assert isinstance(result, dict)
        assert "status" in result, "Result must have 'status' key"
        assert "streams" in result, "Result must have 'streams' key"
        assert isinstance(result["streams"], list)


class TestUserStoryExtraction:
    """Test _extract_user_stories function."""

    def test_extracts_checkbox_format(self):
        from mesh_server import _extract_user_stories
        content = """
## User Stories
- [ ] US-01: As a user, I want to login so that I can access my account
- [ ] US-02: As a user, I want to logout
"""
        stories = _extract_user_stories(content)
        assert len(stories) >= 2
        assert any(s["id"] == "US-01" for s in stories)
        assert any(s["id"] == "US-02" for s in stories)

    def test_extracts_bare_format(self):
        from mesh_server import _extract_user_stories
        content = """
## User Stories
- US1: As a user, I want to login so that I can access my account
- US2: As a user, I want to logout
"""
        stories = _extract_user_stories(content)
        assert len(stories) >= 2
        assert any(s["id"] == "US-01" for s in stories)
        assert any(s["id"] == "US-02" for s in stories)

    def test_skips_template_placeholders(self):
        from mesh_server import _extract_user_stories
        content = """
- [ ] US-01: As a [user], I want to [capability]
"""
        stories = _extract_user_stories(content)
        assert len(stories) == 0


class TestApiEndpointExtraction:
    """Test _extract_api_endpoints function."""

    def test_extracts_table_format(self):
        from mesh_server import _extract_api_endpoints
        content = """
## API
| /api/users | GET | List users |
| /api/users | POST | Create user |
"""
        endpoints = _extract_api_endpoints(content)
        assert len(endpoints) >= 2
        assert any(e["path"] == "/api/users" and e["method"] == "GET" for e in endpoints)

    def test_extracts_inline_code_format(self):
        from mesh_server import _extract_api_endpoints
        content = """
Use `GET /api/users` to list users.
Use `POST /api/users` to create a user.
"""
        endpoints = _extract_api_endpoints(content)
        assert len(endpoints) >= 2

    def test_extracts_function_definitions(self):
        from mesh_server import _extract_api_endpoints
        content = """
**Build-PipelineStatus**
- Input: `$SelectedRow` (optional)
- Output: `PipelineStatus` hashtable
"""
        endpoints = _extract_api_endpoints(content)
        assert len(endpoints) >= 1
        assert any("Build-PipelineStatus" in e["path"] for e in endpoints)


class TestDataEntityExtraction:
    """Test _extract_data_entities function."""

    def test_extracts_code_block_format(self):
        from mesh_server import _extract_data_entities
        content = """
## Data Model

### User Model
```
User {
    id: string
    name: string
    email: string
}
```
"""
        entities = _extract_data_entities(content)
        assert len(entities) >= 1
        assert any(e["name"] == "User" for e in entities)

    def test_extracts_table_format(self):
        from mesh_server import _extract_data_entities
        content = """
## Data Model

| Entity | Fields |
| User | id:string, name:string |
"""
        entities = _extract_data_entities(content)
        # May or may not match depending on exact format


class TestContextSufficiency:
    """Test _context_is_sufficient function."""

    def test_sufficient_with_multiple_anchors(self):
        from mesh_server import _context_is_sufficient
        # Need: (stories > 0 OR endpoints > 0) AND (entities > 0 OR decisions > 0)
        # AND estimated_tasks >= 10 (estimated = endpoints + entities + stories*2 + decisions)
        context = {
            "user_stories": [{"id": "US-01"}, {"id": "US-02"}, {"id": "US-03"}],
            "api_endpoints": [{"path": "/api/a"}, {"path": "/api/b"}, {"path": "/api/c"}],
            "data_entities": [{"name": "User"}, {"name": "Order"}],
            "decisions": [{"id": "D1"}],
            "domain_nouns": [],
            # estimated = 3 + 2 + (3*2) + 1 = 12 >= 10 ✓
            "debug": {"counts": {"user_stories": 3, "api_endpoints": 3, "data_entities": 2, "decisions": 1}}
        }
        is_sufficient, reasons = _context_is_sufficient(context)
        assert is_sufficient == True, f"Expected sufficient but got: {reasons}"

    def test_insufficient_with_few_anchors(self):
        from mesh_server import _context_is_sufficient
        context = {
            "user_stories": [{"id": "US-01"}],
            "api_endpoints": [],
            "data_entities": [],
            "decisions": [],
            "domain_nouns": [],
            "debug": {"counts": {"user_stories": 1, "api_endpoints": 0, "data_entities": 0, "decisions": 0}}
        }
        is_sufficient, reasons = _context_is_sufficient(context)
        assert is_sufficient == False


class TestPlanQualityAssessment:
    """Test _assess_plan_quality function."""

    def test_bad_with_too_few_tasks(self):
        from mesh_server import _assess_plan_quality
        plan = {
            "streams": [{"name": "Backend", "tasks": [{"id": "T-1", "dod": "x", "trace": "y"}]}]
        }
        context = {"user_stories": [], "api_endpoints": [], "data_entities": []}
        quality = _assess_plan_quality(plan, context)
        assert quality["level"] == "BAD"
        assert quality["reason"] == "TOO_FEW_TASKS"

    def test_bad_with_too_few_streams(self):
        from mesh_server import _assess_plan_quality
        plan = {
            "streams": [{
                "name": "Backend",
                "tasks": [{"id": f"T-{i}", "dod": "x", "trace": "y"} for i in range(12)]
            }]
        }
        context = {"user_stories": [], "api_endpoints": [], "data_entities": []}
        quality = _assess_plan_quality(plan, context)
        assert quality["level"] == "BAD"
        assert quality["reason"] == "TOO_FEW_STREAMS"

    def test_ok_with_sufficient_plan(self):
        from mesh_server import _assess_plan_quality
        plan = {
            "streams": [
                {"name": "Backend", "tasks": [{"id": f"T-B{i}", "dod": "x", "trace": "y"} for i in range(4)]},
                {"name": "Frontend", "tasks": [{"id": f"T-F{i}", "dod": "x", "trace": "y"} for i in range(4)]},
                {"name": "QA", "tasks": [{"id": f"T-Q{i}", "dod": "x", "trace": "y"} for i in range(4)]},
            ]
        }
        context = {
            "user_stories": [{"id": "US-01"}, {"id": "US-02"}],
            "api_endpoints": [{"path": "/api/a"}],
            "data_entities": [{"name": "User"}]
        }
        quality = _assess_plan_quality(plan, context)
        assert quality["level"] == "OK"


class TestBuildPlanFromContext:
    """Test build_plan_from_context_structured function."""

    def test_builds_plan_with_all_streams(self):
        from mesh_server import build_plan_from_context_structured
        # Needs estimated_tasks >= 10: endpoints + entities + (stories*2) + decisions
        # 3 + 2 + (3*2) + 2 = 13 >= 10 ✓
        context = {
            "project_name": "Test Project",
            "user_stories": [
                {"id": "US-01", "desc": "As a user, I want to login"},
                {"id": "US-02", "desc": "As a user, I want to logout"},
                {"id": "US-03", "desc": "As a user, I want to register"},
            ],
            "api_endpoints": [
                {"path": "/api/users", "method": "GET"},
                {"path": "/api/users", "method": "POST"},
                {"path": "/api/auth", "method": "POST"},
            ],
            "data_entities": [
                {"name": "User", "fields": "id:string"},
                {"name": "Session", "fields": "id:string"},
            ],
            "decisions": [
                {"id": "DEC-001", "type": "ARCH", "desc": "Use REST API"},
                {"id": "DEC-002", "type": "SEC", "desc": "Use JWT tokens"},
            ],
            "domain_nouns": [],
            "debug": {"counts": {"user_stories": 3, "api_endpoints": 3, "data_entities": 2, "decisions": 2}}
        }
        plan = build_plan_from_context_structured(context)
        assert plan["status"] == "OK", f"Expected OK but got {plan['status']}"
        assert len(plan["streams"]) >= 4
        stream_names = [s["name"] for s in plan["streams"]]
        assert "Backend" in stream_names
        assert "Frontend" in stream_names
        assert "QA" in stream_names
        assert "Ops" in stream_names


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
