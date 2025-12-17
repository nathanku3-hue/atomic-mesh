"""
Tests for JSON-safe output from plan functions (v16.5 fix)

These tests verify that draft_plan, refresh_plan_preview, and accept_plan
always return valid JSON, even when errors occur. This prevents the
"Invalid JSON primitive: Traceback..." error in PowerShell.
"""

import unittest
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestPlanJsonSafety(unittest.TestCase):
    """Test that plan functions always return valid JSON"""

    def setUp(self):
        """Create temporary project directory"""
        self.test_dir = tempfile.mkdtemp()
        self.original_env = os.environ.get("MESH_BASE_DIR")
        os.environ["MESH_BASE_DIR"] = self.test_dir

        # Create minimal directory structure
        docs_dir = Path(self.test_dir) / "docs"
        docs_dir.mkdir(exist_ok=True)
        (Path(self.test_dir) / "control" / "state").mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        """Clean up temporary directory"""
        if self.original_env:
            os.environ["MESH_BASE_DIR"] = self.original_env
        else:
            os.environ.pop("MESH_BASE_DIR", None)
        shutil.rmtree(self.test_dir)

    def test_draft_plan_returns_valid_json(self):
        """draft_plan() should always return valid JSON"""
        # Import after setting env var
        from mesh_server import draft_plan

        result = draft_plan()

        # Must be parseable as JSON
        parsed = json.loads(result)

        # Must have status field
        self.assertIn("status", parsed)
        self.assertIn(parsed["status"], ["OK", "ERROR", "BLOCKED"])

    def test_refresh_plan_preview_returns_valid_json(self):
        """refresh_plan_preview() should always return valid JSON"""
        from mesh_server import refresh_plan_preview

        result = refresh_plan_preview()

        # Must be parseable as JSON
        parsed = json.loads(result)

        # Must have status field
        self.assertIn("status", parsed)
        self.assertIn(parsed["status"], ["FRESH", "ERROR", "BLOCKED"])

    def test_accept_plan_returns_valid_json_file_not_found(self):
        """accept_plan() should return valid JSON even for missing files"""
        from mesh_server import accept_plan

        result = accept_plan("nonexistent_file.md")

        # Must be parseable as JSON
        parsed = json.loads(result)

        # Must have status field (could be ERROR or BLOCKED depending on readiness)
        self.assertIn("status", parsed)
        self.assertIn(parsed["status"], ["ERROR", "BLOCKED"])
        self.assertIn("message", parsed)

    def test_draft_plan_json_has_no_stderr_contamination(self):
        """draft_plan() output should start with '{' (no stderr mixed in)"""
        from mesh_server import draft_plan

        result = draft_plan()

        # Output must start with JSON object
        self.assertTrue(result.strip().startswith("{"),
                       f"Output should start with '{{', got: {result[:100]}")

    def test_refresh_plan_json_has_no_stderr_contamination(self):
        """refresh_plan_preview() output should start with '{' (no stderr mixed in)"""
        from mesh_server import refresh_plan_preview

        result = refresh_plan_preview()

        # Output must start with JSON object
        self.assertTrue(result.strip().startswith("{"),
                       f"Output should start with '{{', got: {result[:100]}")


if __name__ == "__main__":
    unittest.main()
