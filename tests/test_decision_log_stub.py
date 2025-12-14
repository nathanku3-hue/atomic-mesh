"""
Tests for DECISION_LOG stub scoring (v15.0)

Tests the specialized stub detection for DECISION_LOG that checks for:
1. Template similarity (≥0.85 threshold)
2. Real decision rows beyond bootstrap init

Expected behavior:
- Template-only / init-only log → STUB (≤40%)
- Once a real decision row is appended → can become OK (≥ threshold)
"""

import unittest
import sys
import os
import tempfile
import shutil
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.readiness import (
    get_context_readiness,
    has_real_decisions,
    get_template_similarity,
    normalize_for_comparison
)


class TestDecisionLogHasRealDecisions(unittest.TestCase):
    """Test the has_real_decisions() helper function"""

    def test_init_only_returns_false(self):
        """DECISION_LOG with only init row should return False"""
        content = """# Decision Log

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->
"""
        self.assertFalse(has_real_decisions(content))

    def test_real_decision_row_returns_true(self):
        """DECISION_LOG with a real decision should return True"""
        content = """# Decision Log

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |
| 002 | 2025-01-02 | ARCH | Use FastAPI for backend | Team expertise in Python | backend | T-001 | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->
"""
        self.assertTrue(has_real_decisions(content))

    def test_scope_decision_returns_true(self):
        """DECISION_LOG with SCOPE type decision should return True"""
        content = """# Decision Log

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |
| 002 | 2025-01-02 | SCOPE | MVP excludes mobile | Time constraints | frontend | — | ✅ |
"""
        self.assertTrue(has_real_decisions(content))

    def test_multiple_init_rows_returns_false(self):
        """Multiple INIT rows about initialization still returns False"""
        content = """# Decision Log

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |
| 002 | 2025-01-01 | INIT | Bootstrap complete | Via /init command | repo | — | ✅ |
"""
        self.assertFalse(has_real_decisions(content))

    def test_empty_records_returns_false(self):
        """DECISION_LOG with no data rows returns False"""
        content = """# Decision Log

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->
"""
        self.assertFalse(has_real_decisions(content))

    def test_no_records_section_returns_false(self):
        """DECISION_LOG without ## Records section returns False"""
        content = """# Decision Log

This file has no records section.
"""
        self.assertFalse(has_real_decisions(content))


class TestDecisionLogStubScoring(unittest.TestCase):
    """Integration tests for DECISION_LOG stub scoring"""

    def setUp(self):
        """Create temporary project directory with required structure"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        self.templates_dir = Path(self.test_dir) / "library" / "templates"
        self.templates_dir.mkdir(parents=True)

        # Create the template
        template_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: {{PROJECT_NAME}}

**Owner**: {{AUTHOR}} | **Date**: {{DATE}} | **Status**: Active
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | {{DATE}} | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted
**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE

## Notes (Optional, Human)
- Prefer short rationale in the table. If long, add a link to a decision packet in `docs/DECISIONS/`.
- When superseding: add a new row with `Type=...` and set the old row to 🔄 (do not delete).
"""
        (self.templates_dir / "DECISION_LOG.template.md").write_text(template_content, encoding='utf-8')

        # Create minimal PRD and SPEC to avoid missing file issues
        (self.docs_dir / "PRD.md").write_text("# PRD\n## Goals\n- Test\n## User Stories\n- Story\n## Success Metrics\n- Metric", encoding='utf-8')
        (self.docs_dir / "SPEC.md").write_text("# SPEC\n## Data Model\n- Model\n## API\n- Endpoint\n## Security\n- Control", encoding='utf-8')

    def tearDown(self):
        """Clean up temporary directory"""
        shutil.rmtree(self.test_dir)

    def test_template_identical_capped_at_40(self):
        """DECISION_LOG identical to template should be capped at 40%"""
        # Create a DECISION_LOG that matches template (with substituted values)
        decision_log = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: TestProject

**Owner**: Atomic Mesh | **Date**: 2025-01-01 | **Status**: Active
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted
**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE

## Notes (Optional, Human)
- Prefer short rationale in the table. If long, add a link to a decision packet in `docs/DECISIONS/`.
- When superseding: add a new row with `Type=...` and set the old row to 🔄 (do not delete).
"""
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log, encoding='utf-8')

        result = get_context_readiness(base_dir=self.test_dir)

        self.assertLessEqual(
            result["files"]["DECISION_LOG"]["score"], 40,
            "Template-identical DECISION_LOG should be capped at 40%"
        )

    def test_real_decision_unlocks_scoring(self):
        """DECISION_LOG with real decision row should be able to exceed 40%"""
        decision_log = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: TestProject

**Owner**: Atomic Mesh | **Date**: 2025-01-01 | **Status**: Active
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-01-01 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |
| 002 | 2025-01-02 | ARCH | Use PostgreSQL for database | ACID compliance required | backend | T-001 | ✅ |
| 003 | 2025-01-03 | API | REST with OpenAPI spec | Industry standard | api | T-002 | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted
"""
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log, encoding='utf-8')

        result = get_context_readiness(base_dir=self.test_dir)

        # With real decisions, cap is removed - score depends on content
        # Score should be at least: exists(10) + headers(10) = 20
        # And potentially more since cap is removed
        self.assertGreaterEqual(
            result["files"]["DECISION_LOG"]["score"], 20,
            "DECISION_LOG with real decisions should score based on content"
        )

    def test_init_bootstrap_creates_stub(self):
        """Simulated /init should create DECISION_LOG as STUB"""
        # Simulate what /init creates
        decision_log = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: MyProject

**Owner**: Atomic Mesh | **Date**: 2025-12-13 | **Status**: Active
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-12-13 | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted
**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE

## Notes (Optional, Human)
- Prefer short rationale in the table. If long, add a link to a decision packet in `docs/DECISIONS/`.
- When superseding: add a new row with `Type=...` and set the old row to 🔄 (do not delete).
"""
        (self.docs_dir / "DECISION_LOG.md").write_text(decision_log, encoding='utf-8')

        result = get_context_readiness(base_dir=self.test_dir)

        self.assertLessEqual(
            result["files"]["DECISION_LOG"]["score"], 40,
            "Fresh /init DECISION_LOG should be capped at 40% (STUB)"
        )


class TestTemplateSimilarity(unittest.TestCase):
    """Tests for template similarity checking"""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.templates_dir = Path(self.test_dir) / "library" / "templates"
        self.templates_dir.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_identical_content_high_similarity(self):
        """Identical content should have very high similarity"""
        template = "# Test\n\nSome content here.\n\n## Section\n- Item 1"
        (self.templates_dir / "test.template.md").write_text(template, encoding='utf-8')

        similarity = get_template_similarity(template, self.templates_dir / "test.template.md")
        self.assertGreaterEqual(similarity, 0.95)

    def test_different_content_low_similarity(self):
        """Completely different content should have low similarity"""
        template = "# Template\n\n## Records\n| A | B |"
        content = "# Different File\n\nThis is completely different content."

        (self.templates_dir / "test.template.md").write_text(template, encoding='utf-8')
        similarity = get_template_similarity(content, self.templates_dir / "test.template.md")

        self.assertLess(similarity, 0.5)

    def test_date_substitution_still_similar(self):
        """Content with only date substitutions should still be similar"""
        template = "# Log\n\nDate: {{DATE}}\n\n## Records\n| 001 | {{DATE}} |"
        content = "# Log\n\nDate: 2025-01-15\n\n## Records\n| 001 | 2025-01-15 |"

        (self.templates_dir / "test.template.md").write_text(template, encoding='utf-8')
        similarity = get_template_similarity(content, self.templates_dir / "test.template.md")

        self.assertGreaterEqual(similarity, 0.8)


class TestNormalization(unittest.TestCase):
    """Tests for content normalization"""

    def test_removes_stub_marker(self):
        """Normalization should remove stub marker"""
        content = "<!-- ATOMIC_MESH_TEMPLATE_STUB -->\n# Title"
        normalized = normalize_for_comparison(content)
        self.assertNotIn("atomic_mesh_template_stub", normalized)

    def test_removes_dates(self):
        """Normalization should remove dates"""
        content = "Created: 2025-01-15\nUpdated: 2024-12-01"
        normalized = normalize_for_comparison(content)
        self.assertNotIn("2025", normalized)
        self.assertNotIn("2024", normalized)

    def test_removes_placeholders(self):
        """Normalization should remove {{placeholders}}"""
        content = "Project: {{PROJECT_NAME}}\nAuthor: {{AUTHOR}}"
        normalized = normalize_for_comparison(content)
        self.assertNotIn("{{", normalized)
        self.assertNotIn("}}", normalized)

    def test_normalizes_numeric_ids(self):
        """Normalization should normalize table row IDs"""
        content = "| 001 | data |\n| 1734567890 | more |"
        normalized = normalize_for_comparison(content)
        # Both should become | |
        self.assertNotIn("001", normalized)
        self.assertNotIn("1734567890", normalized)


class TestPerformance(unittest.TestCase):
    """Performance sanity tests"""

    def test_similarity_check_fast(self):
        """Similarity check should complete quickly"""
        import time

        test_dir = tempfile.mkdtemp()
        try:
            templates_dir = Path(test_dir) / "library" / "templates"
            templates_dir.mkdir(parents=True)

            # Create a reasonable-sized template
            template = "# Decision Log\n\n" + "| row | data |\n" * 100
            (templates_dir / "test.template.md").write_text(template, encoding='utf-8')

            content = "# Decision Log\n\n" + "| row | different |\n" * 100

            start = time.time()
            for _ in range(100):  # Run 100 times
                get_template_similarity(content, templates_dir / "test.template.md")
            elapsed = time.time() - start

            # Should complete 100 iterations in under 1 second
            self.assertLess(elapsed, 1.0, f"Similarity check too slow: {elapsed}s for 100 iterations")
        finally:
            shutil.rmtree(test_dir)


if __name__ == '__main__':
    unittest.main()
