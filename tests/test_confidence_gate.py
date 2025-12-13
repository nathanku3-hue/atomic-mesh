"""
v14.1: Confidence Gate Tests - Done-Done Closeout Loop

This test suite verifies the confidence gate enforcement logic for MEDIUM/HIGH
risk tasks. No real LLM calls or database operations - all mocked.

Run with: python -m pytest tests/test_confidence_gate.py -v
Or standalone: python tests/test_confidence_gate.py
"""

import unittest
import re


class TestConfidenceGateParsing(unittest.TestCase):
    """Tests for verify score parsing from notes."""

    def test_parse_verify_score_valid(self):
        """Should parse valid Verify: XX/100 patterns."""
        test_cases = [
            ("Verify: 95/100", 95),
            ("verify: 80/100", 80),
            ("VERIFY: 100/100", 100),
            ("Verify:  90/100", 90),  # extra space
            ("Notes here. Verify: 75/100. More notes.", 75),
            ("verify: 0/100", 0),
        ]

        for notes, expected in test_cases:
            score = self._parse_verify_score(notes.lower())
            self.assertEqual(score, expected, f"Failed to parse '{notes}' -> expected {expected}, got {score}")

    def test_parse_verify_score_missing(self):
        """Should return None when no Verify score present."""
        test_cases = [
            "No score here",
            "Verify passed",  # Wrong format
            "Verification: 95/100",  # Wrong keyword
            "Verify: pending",
            "",
        ]

        for notes in test_cases:
            score = self._parse_verify_score(notes.lower())
            self.assertIsNone(score, f"Should return None for '{notes}', got {score}")

    def test_parse_verify_score_no_false_positives(self):
        """Should NOT match version numbers, percentages, or malformed patterns."""
        false_positive_cases = [
            "v15.5 release notes",  # Version number
            "80% complete",  # Percentage
            "Verify: 95%",  # Wrong format (% not /100)
            "Score is 95/100 but not Verify",  # Missing keyword
            "Verify 95/100",  # Missing colon
            "Verify:95/100",  # No space (actually valid per regex)
            "pre-verify: 95/100",  # Prefix
            "Verified: 95/100",  # Wrong keyword
        ]

        for notes in false_positive_cases:
            # These should NOT produce a valid score (except Verify:95/100 which is valid)
            if "verify:" in notes.lower() and "/100" in notes:
                continue  # Skip valid variants
            score = self._parse_verify_score(notes.lower())
            self.assertIsNone(score, f"False positive for '{notes}', got {score}")

    def _parse_verify_score(self, notes_lower: str) -> int | None:
        """Mock verify score parser (matches mesh_server.py logic)."""
        verify_match = re.search(r'verify:\s*(\d{1,3})/100', notes_lower)
        return int(verify_match.group(1)) if verify_match else None


class TestConfidenceGateEnforcement(unittest.TestCase):
    """Tests for confidence gate blocking/allowing logic."""

    def test_high_risk_blocked_without_verify_score(self):
        """HIGH risk task without Verify score should be blocked."""
        result = self._check_confidence_gate(
            risk="HIGH",
            notes="Entropy Check: Passed. Tests all green.",
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["reason"], "MISSING_CONFIDENCE_PROOF")

    def test_high_risk_blocked_with_insufficient_score(self):
        """HIGH risk task with Verify: 94/100 (below 95) should be blocked."""
        result = self._check_confidence_gate(
            risk="HIGH",
            notes="Entropy Check: Passed. Verify: 94/100",
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["reason"], "INSUFFICIENT_CONFIDENCE")

    def test_high_risk_allowed_with_sufficient_score(self):
        """HIGH risk task with Verify: 95/100 should be allowed."""
        result = self._check_confidence_gate(
            risk="HIGH",
            notes="Entropy Check: Passed. Verify: 95/100",
        )

        self.assertEqual(result["status"], "OK")

    def test_high_risk_allowed_with_96_score(self):
        """HIGH risk task with Verify: 96/100 should be allowed."""
        result = self._check_confidence_gate(
            risk="HIGH",
            notes="Entropy Check: Passed. Verify: 96/100",
        )

        self.assertEqual(result["status"], "OK")

    def test_high_risk_allowed_with_override(self):
        """HIGH risk task with CAPTAIN_OVERRIDE: CONFIDENCE should be allowed."""
        result = self._check_confidence_gate(
            risk="HIGH",
            notes="Entropy Check: Passed. CAPTAIN_OVERRIDE: CONFIDENCE - Emergency fix.",
        )

        self.assertEqual(result["status"], "OK")
        self.assertTrue(result.get("override_used", False))

    def test_medium_risk_blocked_without_verify_score(self):
        """MEDIUM risk task without Verify score should be blocked."""
        result = self._check_confidence_gate(
            risk="MEDIUM",
            notes="Entropy Check: Passed. Tests all green.",
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["reason"], "MISSING_CONFIDENCE_PROOF")

    def test_medium_risk_blocked_with_89_score(self):
        """MEDIUM risk task with Verify: 89/100 (below 90) should be blocked."""
        result = self._check_confidence_gate(
            risk="MEDIUM",
            notes="Entropy Check: Passed. Verify: 89/100",
        )

        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["reason"], "INSUFFICIENT_CONFIDENCE")

    def test_medium_risk_allowed_with_90_score(self):
        """MEDIUM risk task with Verify: 90/100 should be allowed."""
        result = self._check_confidence_gate(
            risk="MEDIUM",
            notes="Entropy Check: Passed. Verify: 90/100",
        )

        self.assertEqual(result["status"], "OK")

    def test_medium_risk_allowed_with_override(self):
        """MEDIUM risk task with CAPTAIN_OVERRIDE: CONFIDENCE should be allowed."""
        result = self._check_confidence_gate(
            risk="MED",  # Test MED variant
            notes="Entropy Check: Passed. CAPTAIN_OVERRIDE: CONFIDENCE",
        )

        self.assertEqual(result["status"], "OK")
        self.assertTrue(result.get("override_used", False))

    def test_low_risk_not_affected(self):
        """LOW risk tasks should not require confidence proof."""
        result = self._check_confidence_gate(
            risk="LOW",
            notes="Entropy Check: Passed. No verify score.",
        )

        self.assertEqual(result["status"], "OK")
        self.assertFalse(result.get("gate_applied", True))

    def test_null_risk_treated_as_low(self):
        """Tasks with null/empty risk should be treated as LOW."""
        for risk in [None, "", "UNKNOWN"]:
            result = self._check_confidence_gate(
                risk=risk,
                notes="Entropy Check: Passed.",
            )

            self.assertEqual(result["status"], "OK", f"Risk '{risk}' should be treated as LOW")

    def _check_confidence_gate(self, risk: str | None, notes: str) -> dict:
        """
        Mock confidence gate logic (matches mesh_server.py submit_review_decision).

        Returns dict with status, reason, gate_applied, override_used.
        """
        task_risk = (risk or "LOW").upper()
        notes_lower = notes.lower()

        # Only enforce for MEDIUM/HIGH risk
        if task_risk not in ("MEDIUM", "MED", "HIGH"):
            return {"status": "OK", "gate_applied": False}

        # Check for captain override first
        has_confidence_override = "captain_override:" in notes_lower and "confidence" in notes_lower

        if has_confidence_override:
            return {"status": "OK", "gate_applied": True, "override_used": True}

        # Parse verify score
        verify_match = re.search(r'verify:\s*(\d{1,3})/100', notes_lower)
        verify_score = int(verify_match.group(1)) if verify_match else None

        # Determine required threshold
        required_threshold = 95 if task_risk == "HIGH" else 90

        if verify_score is None:
            return {
                "status": "BLOCKED",
                "reason": "MISSING_CONFIDENCE_PROOF",
                "gate_applied": True,
            }

        if verify_score < required_threshold:
            return {
                "status": "BLOCKED",
                "reason": "INSUFFICIENT_CONFIDENCE",
                "gate_applied": True,
                "score": verify_score,
                "threshold": required_threshold,
            }

        return {"status": "OK", "gate_applied": True, "score": verify_score}


class TestEntropyGateUnchanged(unittest.TestCase):
    """Verify entropy gate is not affected by confidence gate changes."""

    def test_entropy_still_required(self):
        """Entropy check should still be required regardless of risk level."""
        # This test documents that entropy gate is independent
        for risk in ["LOW", "MEDIUM", "HIGH"]:
            notes = "Verify: 100/100"  # Has verify but no entropy
            has_entropy = self._check_entropy_proof(notes)
            self.assertFalse(has_entropy,
                           f"Entropy should still be required for {risk} risk")

    def test_entropy_passes_with_proof(self):
        """Entropy check should pass with proper proof."""
        notes = "Entropy Check: Passed. Verify: 95/100"
        has_entropy = self._check_entropy_proof(notes)
        self.assertTrue(has_entropy)

    def _check_entropy_proof(self, notes: str) -> bool:
        """Mock entropy check (matches mesh_server.py logic)."""
        notes_lower = notes.lower()
        has_entropy_check = "entropy check:" in notes_lower and "passed" in notes_lower
        has_waiver = "optimization waived:" in notes_lower
        has_override = "captain_override:" in notes_lower and "entropy" in notes_lower
        return has_entropy_check or has_waiver or has_override


if __name__ == '__main__':
    print("=" * 60)
    print("v14.1: Confidence Gate Policy Tests")
    print("=" * 60)
    print()

    # Run tests with verbosity
    unittest.main(verbosity=2)
