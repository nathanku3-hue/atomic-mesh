"""
Tests for ACTIVE_SPEC hydration (Auto-Flight v15.0)

Tests the write_active_spec_snapshot() function which deterministically
generates docs/ACTIVE_SPEC.md from PRD.md + SPEC.md content.
"""

import unittest
import sys
import os
import tempfile
import shutil
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mesh_server import write_active_spec_snapshot


class TestActiveSpecHydration(unittest.TestCase):
    """Test deterministic hydration of ACTIVE_SPEC.md"""

    def setUp(self):
        """Create temporary project directory with docs/"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()

    def tearDown(self):
        """Clean up temporary directory"""
        shutil.rmtree(self.test_dir)

    def test_hydration_creates_active_spec(self):
        """Hydration should create docs/ACTIVE_SPEC.md"""
        # Create minimal PRD
        prd_content = """# PRD: Test Project

## Goals
- [ ] Build a working prototype
- [ ] Achieve 80% test coverage

## User Stories
- [ ] As a user, I can login to access my dashboard
- [ ] As an admin, I can manage users

## Out of Scope
- Mobile app support
- Offline mode
"""
        (self.docs_dir / "PRD.md").write_text(prd_content, encoding='utf-8')

        # Create minimal SPEC
        spec_content = """# SPEC: Test Project

## API
- GET /api/users - List all users
- POST /api/login - Authenticate user

## Data Model
- User: id, email, password_hash
- Session: id, user_id, token

## Technical Constraints
- Database: PostgreSQL
- Auth: JWT tokens
- API Style: REST
"""
        (self.docs_dir / "SPEC.md").write_text(spec_content, encoding='utf-8')

        # Run hydration
        result = write_active_spec_snapshot(base_dir=self.test_dir)

        # Assertions
        self.assertTrue(result["ok"], f"Hydration failed: {result.get('reason')}")
        active_spec_path = self.docs_dir / "ACTIVE_SPEC.md"
        self.assertTrue(active_spec_path.exists(), "ACTIVE_SPEC.md should be created")

    def test_hydration_contains_derived_from(self):
        """ACTIVE_SPEC should contain 'Derived from' header"""
        # Create PRD
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test goal", encoding='utf-8')

        # Run hydration
        write_active_spec_snapshot(base_dir=self.test_dir)

        # Check content
        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("Derived from", content)

    def test_hydration_extracts_goals_from_prd(self):
        """Hydration should extract goals from PRD"""
        prd_content = """# PRD

## Goals
- [ ] G1: Implement user authentication system
- [ ] G2: Add dashboard analytics
- [x] G3: Setup CI/CD pipeline
"""
        (self.docs_dir / "PRD.md").write_text(prd_content, encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        self.assertTrue(result["ok"])
        self.assertGreaterEqual(result.get("goals_count", 0), 1, "Should extract at least 1 goal")

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("user authentication", content.lower())

    def test_hydration_extracts_user_stories_from_prd(self):
        """Hydration should extract user stories from PRD"""
        prd_content = """# PRD

## Goals
- Test goal

## User Stories
### Must Have (MVP)
- [ ] US1: As a developer, I can run tests locally
- [ ] US2: As a user, I can view my profile page
"""
        (self.docs_dir / "PRD.md").write_text(prd_content, encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        self.assertTrue(result["ok"])
        self.assertGreaterEqual(result.get("stories_count", 0), 1, "Should extract at least 1 story")

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("developer", content.lower())

    def test_hydration_extracts_endpoints_from_spec(self):
        """Hydration should extract API endpoints from SPEC"""
        spec_content = """# SPEC

## API
- GET /api/health - Health check endpoint
- POST /api/users - Create new user
- DELETE /api/users/:id - Remove user
"""
        (self.docs_dir / "SPEC.md").write_text(spec_content, encoding='utf-8')
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test", encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        self.assertTrue(result["ok"])
        self.assertGreaterEqual(result.get("endpoints_count", 0), 1, "Should extract at least 1 endpoint")

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("/api", content)

    def test_hydration_contains_batch_focus_section(self):
        """ACTIVE_SPEC should contain Current Batch Focus section"""
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test", encoding='utf-8')

        write_active_spec_snapshot(base_dir=self.test_dir)

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("Current Batch Focus", content)
        self.assertIn("correctness > speed > elegance", content)

    def test_hydration_handles_missing_prd(self):
        """Hydration should succeed even without PRD (fail-open)"""
        # Only create SPEC
        (self.docs_dir / "SPEC.md").write_text("# SPEC\n## API\n- GET /test", encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        # Should still succeed (fail-open)
        self.assertTrue(result["ok"])
        self.assertTrue((self.docs_dir / "ACTIVE_SPEC.md").exists())

    def test_hydration_handles_missing_spec(self):
        """Hydration should succeed even without SPEC (fail-open)"""
        # Only create PRD
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Build something", encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        # Should still succeed (fail-open)
        self.assertTrue(result["ok"])
        self.assertTrue((self.docs_dir / "ACTIVE_SPEC.md").exists())

    def test_hydration_records_decision_log_presence(self):
        """Hydration should note if DECISION_LOG.md is present"""
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test", encoding='utf-8')
        (self.docs_dir / "DECISION_LOG.md").write_text("# Decision Log\n## Records\n| ID | Date |", encoding='utf-8')

        write_active_spec_snapshot(base_dir=self.test_dir)

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("DECISION_LOG.md", content)

    def test_hydration_deterministic(self):
        """Same input should produce same output (minus timestamp)"""
        prd_content = """# PRD
## Goals
- [ ] Goal A
- [ ] Goal B

## User Stories
- [ ] Story 1
"""
        spec_content = """# SPEC
## API
- GET /test
"""
        (self.docs_dir / "PRD.md").write_text(prd_content, encoding='utf-8')
        (self.docs_dir / "SPEC.md").write_text(spec_content, encoding='utf-8')

        # Run twice
        write_active_spec_snapshot(base_dir=self.test_dir)
        content1 = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')

        write_active_spec_snapshot(base_dir=self.test_dir)
        content2 = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')

        # Should be identical (same day, deterministic extraction)
        self.assertEqual(content1, content2)


class TestHydrationEdgeCases(unittest.TestCase):
    """Edge case tests for hydration"""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_hydration_skips_template_placeholders(self):
        """Should not include {{placeholder}} lines in output"""
        prd_content = """# PRD
## Goals
- [ ] {{GOAL_PLACEHOLDER}}
- [ ] Real goal here
- [ ] {{ANOTHER_PLACEHOLDER}}
"""
        (self.docs_dir / "PRD.md").write_text(prd_content, encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertNotIn("{{", content)
        self.assertIn("Real goal", content)

    def test_hydration_extracts_constraints(self):
        """Should extract technical constraints from SPEC"""
        spec_content = """# SPEC

## Technical Constraints
- Database: SQLite
- Auth: API Keys
- API Style: GraphQL
- Runtime: Node.js
"""
        (self.docs_dir / "SPEC.md").write_text(spec_content, encoding='utf-8')
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test", encoding='utf-8')

        write_active_spec_snapshot(base_dir=self.test_dir)

        content = (self.docs_dir / "ACTIVE_SPEC.md").read_text(encoding='utf-8')
        self.assertIn("SQLite", content)

    def test_hydration_fallback_to_active_spec(self):
        """If SPEC.md missing, should fallback to existing ACTIVE_SPEC.md"""
        # Create existing ACTIVE_SPEC with some content
        (self.docs_dir / "ACTIVE_SPEC.md").write_text("""# ACTIVE SPEC
## API
- GET /legacy/endpoint
""", encoding='utf-8')
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test", encoding='utf-8')

        result = write_active_spec_snapshot(base_dir=self.test_dir)

        self.assertTrue(result["ok"])
        self.assertIn("ACTIVE_SPEC.md (fallback)", result.get("reason", ""))


if __name__ == '__main__':
    unittest.main()
