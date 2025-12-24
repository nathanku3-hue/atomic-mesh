"""
Regression Tests for Threshold Fallback Chain

Ensures that when the readiness.py subprocess fails, snapshot.py falls back to
imported THRESHOLDS from readiness.py (single source of truth).

This prevents "updated one place, forgot the other" drift between files.

Fallback chain:
1. Subprocess call to readiness.py (primary - includes scoring)
2. Import THRESHOLDS from readiness.py (if subprocess fails)
3. Hardcoded last-resort (if even import fails - rare)
"""

import unittest
import sys
import os
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.readiness import THRESHOLDS
from tools.snapshot import get_readiness_data, _get_fallback_thresholds


class TestThresholdSingleSource(unittest.TestCase):
    """Tests that THRESHOLDS constant is the single source of truth"""

    def test_thresholds_constant_exists(self):
        """THRESHOLDS constant should be defined in readiness.py"""
        self.assertIsInstance(THRESHOLDS, dict)
        self.assertIn("PRD", THRESHOLDS)
        self.assertIn("SPEC", THRESHOLDS)
        self.assertIn("DECISION_LOG", THRESHOLDS)

    def test_thresholds_have_expected_values(self):
        """THRESHOLDS should have production values (90/90/60)"""
        self.assertEqual(THRESHOLDS["PRD"], 90)
        self.assertEqual(THRESHOLDS["SPEC"], 90)
        self.assertEqual(THRESHOLDS["DECISION_LOG"], 60)


class TestFallbackThresholds(unittest.TestCase):
    """Tests for _get_fallback_thresholds() function"""

    def test_fallback_returns_imported_thresholds(self):
        """_get_fallback_thresholds should return values from readiness.THRESHOLDS"""
        fallback = _get_fallback_thresholds()

        # Should match the imported THRESHOLDS
        self.assertEqual(fallback["PRD"], THRESHOLDS["PRD"])
        self.assertEqual(fallback["SPEC"], THRESHOLDS["SPEC"])
        self.assertEqual(fallback["DECISION_LOG"], THRESHOLDS["DECISION_LOG"])

    def test_fallback_returns_copy(self):
        """_get_fallback_thresholds should return a copy, not the original"""
        fallback = _get_fallback_thresholds()

        # Modifying fallback should not affect THRESHOLDS
        original_prd = THRESHOLDS["PRD"]
        fallback["PRD"] = 999

        self.assertEqual(THRESHOLDS["PRD"], original_prd)


class TestSubprocessFailureFallback(unittest.TestCase):
    """Tests that subprocess failure falls back to imported thresholds"""

    @patch('tools.snapshot.subprocess.run')
    def test_subprocess_failure_uses_imported_thresholds(self, mock_run):
        """When subprocess fails, should use thresholds from readiness.THRESHOLDS"""
        # Simulate subprocess failure
        mock_run.side_effect = Exception("Subprocess failed")

        result = get_readiness_data(Path("/fake/repo"))

        # Should return default result with imported thresholds
        self.assertEqual(result["doc_scores"]["PRD"]["threshold"], THRESHOLDS["PRD"])
        self.assertEqual(result["doc_scores"]["SPEC"]["threshold"], THRESHOLDS["SPEC"])
        self.assertEqual(result["doc_scores"]["DECISION_LOG"]["threshold"], THRESHOLDS["DECISION_LOG"])

    @patch('tools.snapshot.subprocess.run')
    def test_subprocess_timeout_uses_imported_thresholds(self, mock_run):
        """When subprocess times out, should use thresholds from readiness.THRESHOLDS"""
        import subprocess
        mock_run.side_effect = subprocess.TimeoutExpired(cmd="python", timeout=1)

        result = get_readiness_data(Path("/fake/repo"))

        # Should return default result with imported thresholds
        self.assertEqual(result["doc_scores"]["PRD"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["SPEC"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["DECISION_LOG"]["threshold"], 60)

    @patch('tools.snapshot.subprocess.run')
    def test_subprocess_nonzero_exit_uses_imported_thresholds(self, mock_run):
        """When subprocess returns non-zero, should use thresholds from readiness.THRESHOLDS"""
        mock_result = MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ""
        mock_run.return_value = mock_result

        result = get_readiness_data(Path("/fake/repo"))

        # Should return default result with imported thresholds
        self.assertEqual(result["doc_scores"]["PRD"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["SPEC"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["DECISION_LOG"]["threshold"], 60)

    @patch('tools.snapshot.subprocess.run')
    def test_subprocess_empty_output_uses_imported_thresholds(self, mock_run):
        """When subprocess returns empty output, should use thresholds from readiness.THRESHOLDS"""
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = ""  # Empty output
        mock_run.return_value = mock_result

        result = get_readiness_data(Path("/fake/repo"))

        # Should return default result with imported thresholds
        self.assertEqual(result["doc_scores"]["PRD"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["SPEC"]["threshold"], 90)
        self.assertEqual(result["doc_scores"]["DECISION_LOG"]["threshold"], 60)


class TestThresholdDriftPrevention(unittest.TestCase):
    """Meta-tests to ensure thresholds stay in sync"""

    def test_no_hardcoded_thresholds_in_snapshot_defaults(self):
        """
        Regression test: snapshot.py should not have hardcoded threshold values
        that could drift from readiness.py.

        The fallback chain should be:
        1. Import from readiness.py
        2. Hardcoded last-resort only in _get_fallback_thresholds()
        """
        import inspect
        from tools import snapshot

        # Get source of get_readiness_data
        source = inspect.getsource(snapshot.get_readiness_data)

        # Should NOT contain hardcoded threshold values in the function body
        # (they should come from _get_fallback_thresholds)
        self.assertNotIn('"threshold": 90', source,
                        "get_readiness_data should not have hardcoded thresholds")
        self.assertNotIn('"threshold": 60', source,
                        "get_readiness_data should not have hardcoded thresholds")

    def test_fallback_thresholds_match_readiness_constant(self):
        """
        Verify that _get_fallback_thresholds returns exactly what readiness.THRESHOLDS defines.
        This is the key regression test for threshold drift.
        """
        fallback = _get_fallback_thresholds()

        # These must match exactly - if they don't, there's drift
        self.assertEqual(
            fallback,
            THRESHOLDS,
            f"Fallback thresholds {fallback} don't match readiness.THRESHOLDS {THRESHOLDS}"
        )


if __name__ == '__main__':
    unittest.main()
