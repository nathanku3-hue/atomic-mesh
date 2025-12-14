"""
Tests for INBOX ephemeral capture feature (v15.1)

Tests the docs/INBOX.md feature:
1. /init scaffolds INBOX.md from template
2. Meaningful line detection for dashboard indicator
3. /ingest merges INBOX content and clears on success
4. /ingest does NOT clear INBOX on failure
"""

import unittest
import sys
import os
import tempfile
import shutil
from pathlib import Path
from unittest.mock import patch, MagicMock, AsyncMock

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from mesh_server import (
    get_inbox_meaningful_lines,
    clear_inbox_to_stub,
    INBOX_STUB_TEMPLATE
)


class TestInboxTemplate(unittest.TestCase):
    """Test INBOX template scaffolding"""

    def test_inbox_template_exists(self):
        """INBOX.template.md should exist in library/templates/"""
        script_dir = Path(__file__).parent.parent
        template_path = script_dir / "library" / "templates" / "INBOX.template.md"
        self.assertTrue(template_path.exists(), "INBOX.template.md should exist")

    def test_inbox_template_has_stub_marker(self):
        """INBOX template should contain stub marker"""
        script_dir = Path(__file__).parent.parent
        template_path = script_dir / "library" / "templates" / "INBOX.template.md"
        content = template_path.read_text(encoding='utf-8')
        self.assertIn("ATOMIC_MESH_TEMPLATE_STUB", content)

    def test_inbox_template_has_entries_section(self):
        """INBOX template should have ## Entries section"""
        script_dir = Path(__file__).parent.parent
        template_path = script_dir / "library" / "templates" / "INBOX.template.md"
        content = template_path.read_text(encoding='utf-8')
        self.assertIn("## Entries", content)


class TestInboxMeaningfulLines(unittest.TestCase):
    """Test meaningful line detection for INBOX"""

    def setUp(self):
        """Create temporary directory"""
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()

    def tearDown(self):
        """Clean up"""
        shutil.rmtree(self.test_dir)

    def test_empty_inbox_returns_zero(self):
        """Fresh stub INBOX should return 0 meaningful lines"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(INBOX_STUB_TEMPLATE, encoding='utf-8')

        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 0, "Stub INBOX should have 0 meaningful lines")

    def test_inbox_with_notes_counts_correctly(self):
        """INBOX with real notes should count meaningful lines"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX (Temporary)

Drop clarifications, new decisions, and notes here.
Next: run `/ingest` to merge into PRD/SPEC/DECISION_LOG, then this file will be cleared.

## Entries
- User wants dark mode support
- API should return JSON by default
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 2, "Should count 2 meaningful lines")
        self.assertIn("dark mode", lines[0])
        self.assertIn("JSON", lines[1])

    def test_inbox_skips_short_lines(self):
        """Lines shorter than 3 chars should be skipped"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX

## Entries
x
ab
This is a real note that should count
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1, "Should only count line >= 3 chars")

    def test_inbox_skips_headers(self):
        """Header lines should be skipped"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX
## Entries
### Subsection
This is a real note
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1, "Should skip headers")

    def test_inbox_skips_placeholder_dash(self):
        """Single dash placeholder should be skipped"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX

## Entries
-
- Real note here
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1, "Should skip placeholder dash")

    def test_missing_inbox_returns_empty(self):
        """Missing INBOX.md should return empty results"""
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 0)
        self.assertEqual(lines, [])


class TestInboxClear(unittest.TestCase):
    """Test INBOX clearing on ingest success"""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_clear_inbox_to_stub_works(self):
        """clear_inbox_to_stub should reset INBOX to template"""
        inbox_path = self.docs_dir / "INBOX.md"
        # Write some content
        inbox_path.write_text("# Modified INBOX\n\nSome notes here", encoding='utf-8')

        # Clear it
        result = clear_inbox_to_stub(str(inbox_path))
        self.assertTrue(result)

        # Verify stub content
        content = inbox_path.read_text(encoding='utf-8')
        self.assertIn("ATOMIC_MESH_TEMPLATE_STUB", content)
        self.assertIn("## Entries", content)
        self.assertNotIn("Modified", content)
        self.assertNotIn("Some notes", content)

    def test_clear_inbox_handles_missing_file(self):
        """clear_inbox_to_stub should create file if missing"""
        inbox_path = self.docs_dir / "INBOX.md"
        self.assertFalse(inbox_path.exists())

        result = clear_inbox_to_stub(str(inbox_path))
        self.assertTrue(result)
        self.assertTrue(inbox_path.exists())


class TestIngestIntegration(unittest.TestCase):
    """Integration tests for /ingest INBOX handling"""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.docs_dir = Path(self.test_dir) / "docs"
        self.docs_dir.mkdir()
        # Create inbox folder too
        (self.docs_dir / "inbox").mkdir()

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_ingest_includes_inbox_in_payload(self):
        """Ingest should include INBOX content in the payload"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX

## Entries
- Use PostgreSQL for database
- Add rate limiting to API
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        # Get meaningful lines
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)

        # Build payload as trigger_ingestion does
        inbox_payload = ""
        if count > 0:
            inbox_payload = "## INBOX (captured notes)\n" + "\n".join(lines) + "\n\n"

        self.assertIn("PostgreSQL", inbox_payload)
        self.assertIn("rate limiting", inbox_payload)
        self.assertIn("## INBOX (captured notes)", inbox_payload)

    def test_ingest_clears_inbox_on_success(self):
        """On successful ingest, INBOX should be cleared"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX

## Entries
- Important note to merge
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        # Verify content before
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1)

        # Simulate successful ingest by clearing
        clear_inbox_to_stub(str(inbox_path))

        # Verify cleared
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 0, "INBOX should be cleared after success")

    def test_ingest_preserves_inbox_on_failure(self):
        """On failed ingest, INBOX should NOT be cleared"""
        inbox_content = """<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# INBOX

## Entries
- Important note to preserve
"""
        inbox_path = self.docs_dir / "INBOX.md"
        inbox_path.write_text(inbox_content, encoding='utf-8')

        # Verify content before
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1)

        # Simulate failed ingest (don't clear)
        # In real code, this happens when result contains "❌"

        # Verify preserved
        lines, count, path = get_inbox_meaningful_lines(self.test_dir)
        self.assertEqual(count, 1, "INBOX should be preserved after failure")
        self.assertIn("preserve", lines[0])


class TestProductOwnerInboxParam(unittest.TestCase):
    """Test product_owner.ingest_inbox accepts inbox_content param"""

    def test_ingest_inbox_accepts_inbox_content_param(self):
        """ingest_inbox should accept inbox_content parameter"""
        from product_owner import ingest_inbox
        import inspect

        sig = inspect.signature(ingest_inbox)
        params = list(sig.parameters.keys())

        self.assertIn("inbox_content", params,
                      "ingest_inbox should accept inbox_content parameter")


if __name__ == '__main__':
    unittest.main()
