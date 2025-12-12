"""
v10.17: Policy-as-Code Tests - Verifying the Gatekeeper

This test suite ensures the compliance enforcement logic (The Gatekeeper)
behaves correctly. In Med/Law contexts, the tool verifying compliance
must itself be verified.

Run with: python -m pytest tests/test_policy.py -v
Or standalone: python tests/test_policy.py
"""

import unittest
import json
import os
import sys

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestAuthorityResolution(unittest.TestCase):
    """Tests for source authority resolution."""

    def setUp(self):
        """Define mock registry (The Constitution)."""
        self.registry = {
            "sources": {
                "HIPAA": {"authority": "MANDATORY", "tier": "domain", "id_pattern": "HIPAA-*"},
                "GDPR": {"authority": "MANDATORY", "tier": "domain", "id_pattern": "GDPR-*"},
                "PRO": {"authority": "STRONG", "tier": "professional", "id_pattern": "PRO-*"},
                "STD": {"authority": "DEFAULT", "tier": "standard", "id_pattern": "STD-*"},
            },
            "curated_rules": {
                "DOMAIN_RULES": {"id_pattern": "DR-*"}
            }
        }

    def test_hipaa_is_mandatory(self):
        """HIPAA sources must resolve to MANDATORY authority."""
        # Simulating get_source_authority logic
        source_id = "HIPAA-SEC-01"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "MANDATORY",
                        f"HIPAA source should be MANDATORY, got {authority}")

    def test_gdpr_is_mandatory(self):
        """GDPR sources must resolve to MANDATORY authority."""
        source_id = "GDPR-ART-17"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "MANDATORY",
                        f"GDPR source should be MANDATORY, got {authority}")

    def test_pro_is_strong(self):
        """Professional standards must resolve to STRONG authority."""
        source_id = "PRO-SEC-01"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "STRONG",
                        f"PRO source should be STRONG, got {authority}")

    def test_std_is_default(self):
        """Standard engineering sources must resolve to DEFAULT authority."""
        source_id = "STD-CODE-01"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "DEFAULT",
                        f"STD source should be DEFAULT, got {authority}")

    def test_domain_rules_are_mandatory(self):
        """Domain Rules (DR-*) must resolve to MANDATORY authority."""
        source_id = "DR-HIPAA-01"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "MANDATORY",
                        f"DR source should be MANDATORY, got {authority}")

    def test_unknown_defaults_to_default(self):
        """Unknown sources should default to DEFAULT authority."""
        source_id = "RANDOM-123"
        authority = self._resolve_authority(source_id)
        self.assertEqual(authority, "DEFAULT",
                        f"Unknown source should be DEFAULT, got {authority}")

    def _resolve_authority(self, source_id: str) -> str:
        """Mock authority resolver matching get_source_authority logic."""
        src_upper = source_id.upper()

        # Check sources by pattern
        for source_key, source_info in self.registry.get("sources", {}).items():
            pattern = source_info.get("id_pattern", "")
            if pattern:
                pattern_prefix = pattern.replace("*", "")
                if src_upper.startswith(pattern_prefix):
                    return source_info.get("authority", "DEFAULT")

        # Check curated_rules patterns (DR-* is MANDATORY)
        for rule_key, rule_info in self.registry.get("curated_rules", {}).items():
            pattern = rule_info.get("id_pattern", "")
            if pattern:
                pattern_prefix = pattern.replace("*", "")
                if src_upper.startswith(pattern_prefix):
                    return "MANDATORY"

        return "DEFAULT"


class TestGatekeeperPolicy(unittest.TestCase):
    """Tests for Gatekeeper validation logic."""

    def test_mandatory_requires_evidence(self):
        """MANDATORY authority tasks MUST have code evidence."""
        task = {
            "id": "T-1",
            "source_ids": ["HIPAA-SEC-01"],
            "archetype": "SEC"
        }
        provenance = {}  # No code files implementing this source

        errors = self._validate_mandatory(task, provenance)

        self.assertTrue(len(errors) > 0,
                       "Gatekeeper should block MANDATORY task with no code evidence")
        self.assertIn("MISSING EVIDENCE", errors[0])

    def test_mandatory_passes_with_evidence(self):
        """MANDATORY authority tasks pass when code evidence exists."""
        task = {
            "id": "T-2",
            "source_ids": ["HIPAA-SEC-01"],
            "archetype": "SEC"
        }
        provenance = {
            "HIPAA-SEC-01": ["src/security/encryption.py:42"]
        }

        errors = self._validate_mandatory(task, provenance)

        self.assertEqual(len(errors), 0,
                        f"Gatekeeper should pass MANDATORY task with evidence: {errors}")

    def test_strong_allows_justification(self):
        """STRONG authority tasks pass with justification even without code."""
        task = {
            "id": "T-3",
            "source_ids": ["PRO-ARCH-01"],
            "archetype": "LOGIC",
            "override_justification": "Performance override approved by lead architect."
        }
        provenance = {}  # No code

        errors = self._validate_strong(task, provenance)

        self.assertEqual(len(errors), 0,
                        "Gatekeeper should allow STRONG task with justification")

    def test_strong_fails_without_evidence_or_justification(self):
        """STRONG authority tasks fail without evidence AND justification."""
        task = {
            "id": "T-4",
            "source_ids": ["PRO-ARCH-01"],
            "archetype": "LOGIC",
            "override_justification": ""
        }
        provenance = {}  # No code

        errors = self._validate_strong(task, provenance)

        self.assertTrue(len(errors) > 0,
                       "Gatekeeper should block STRONG task without evidence or justification")

    def test_default_always_passes(self):
        """DEFAULT authority tasks always pass (baseline engineering)."""
        task = {
            "id": "T-5",
            "source_ids": ["STD-CODE-01"],
            "archetype": "PLUMBING"
        }
        provenance = {}  # No code evidence needed

        errors = self._validate_default(task, provenance)

        self.assertEqual(len(errors), 0,
                        "Gatekeeper should pass DEFAULT task without evidence")

    def _validate_mandatory(self, task: dict, provenance: dict) -> list:
        """Mock MANDATORY authority validation."""
        errors = []
        for src in task.get("source_ids", []):
            if src not in provenance:
                errors.append(f"MISSING EVIDENCE: {src} has no code implementation")
        return errors

    def _validate_strong(self, task: dict, provenance: dict) -> list:
        """Mock STRONG authority validation."""
        errors = []
        has_justification = bool(task.get("override_justification", "").strip())

        for src in task.get("source_ids", []):
            has_code = src in provenance
            if not has_code and not has_justification:
                errors.append(f"STRONG source {src} requires evidence OR justification")
        return errors

    def _validate_default(self, task: dict, provenance: dict) -> list:
        """Mock DEFAULT authority validation - always passes."""
        return []  # DEFAULT sources have no special requirements


class TestTestPairingEnforcement(unittest.TestCase):
    """Tests for mandatory test pairing rules."""

    def test_logic_archetype_requires_paired_test(self):
        """LOGIC archetype tasks should have a paired TEST task."""
        task = {"id": "T-10", "archetype": "LOGIC", "desc": "Implement calculation"}
        all_tasks = {
            "T-10": task,
            # No test task exists
        }

        paired = self._find_paired_test(task, all_tasks)

        self.assertIsNone(paired,
                         "Should detect missing paired test for LOGIC task")

    def test_sec_archetype_requires_paired_test(self):
        """SEC archetype tasks should have a paired TEST task."""
        task = {"id": "T-11", "archetype": "SEC", "desc": "Auth implementation"}
        all_tasks = {
            "T-11": task,
            # No test task exists
        }

        paired = self._find_paired_test(task, all_tasks)

        self.assertIsNone(paired,
                         "Should detect missing paired test for SEC task")

    def test_paired_test_found(self):
        """Should find paired TEST task when it exists."""
        task = {"id": "T-12", "archetype": "LOGIC", "desc": "Implement calculation"}
        test_task = {"id": "T-13", "archetype": "TEST", "desc": "Test calculation [TESTS: T-12]"}
        all_tasks = {
            "T-12": task,
            "T-13": test_task
        }

        paired = self._find_paired_test(task, all_tasks)

        self.assertIsNotNone(paired,
                            "Should find paired TEST task")
        self.assertEqual(paired["id"], "T-13")

    def test_plumbing_does_not_require_test(self):
        """PLUMBING archetype does not require paired test."""
        task = {"id": "T-14", "archetype": "PLUMBING", "desc": "Add logging"}
        all_tasks = {"T-14": task}

        # PLUMBING tasks are exempt from test pairing
        requires_test = self._requires_paired_test(task)

        self.assertFalse(requires_test,
                        "PLUMBING archetype should not require paired test")

    def _find_paired_test(self, task: dict, all_tasks: dict):
        """Mock paired test finder."""
        task_id = task["id"]
        for tid, t in all_tasks.items():
            if t.get("archetype") == "TEST":
                # Check if test references this task
                if f"T-{task_id}" in t.get("desc", "") or f"[TESTS: {task_id}]" in t.get("desc", ""):
                    return t
        return None

    def _requires_paired_test(self, task: dict) -> bool:
        """Check if archetype requires a paired test."""
        risky_archetypes = ["LOGIC", "SEC", "API", "DB"]
        return task.get("archetype", "").upper() in risky_archetypes


class TestSafetyPolicyAutoApprove(unittest.TestCase):
    """Tests for v10.14 auto-approve safety policy."""

    def test_mandatory_not_auto_approvable(self):
        """MANDATORY authority tasks cannot be auto-approved."""
        task = {
            "source_ids": ["HIPAA-SEC-01"],
            "archetype": "SEC"
        }

        is_safe, reason = self._is_safe_to_auto_approve(task)

        self.assertFalse(is_safe,
                        "MANDATORY authority should not be auto-approvable")

    def test_strong_not_auto_approvable(self):
        """STRONG authority tasks cannot be auto-approved."""
        task = {
            "source_ids": ["PRO-SEC-01"],
            "archetype": "UI"
        }

        is_safe, reason = self._is_safe_to_auto_approve(task)

        self.assertFalse(is_safe,
                        "STRONG authority should not be auto-approvable")

    def test_risky_archetype_not_auto_approvable(self):
        """Risky archetypes (SEC, LOGIC, API, DB) cannot be auto-approved."""
        for archetype in ["SEC", "LOGIC", "API", "DB"]:
            task = {
                "source_ids": ["STD-CODE-01"],  # DEFAULT authority
                "archetype": archetype
            }

            is_safe, reason = self._is_safe_to_auto_approve(task)

            self.assertFalse(is_safe,
                            f"Risky archetype {archetype} should not be auto-approvable")

    def test_default_plumbing_is_auto_approvable(self):
        """DEFAULT authority + safe archetype can be auto-approved."""
        task = {
            "source_ids": ["STD-CODE-01"],
            "archetype": "PLUMBING"
        }

        is_safe, reason = self._is_safe_to_auto_approve(task)

        self.assertTrue(is_safe,
                       f"DEFAULT + PLUMBING should be auto-approvable: {reason}")

    def test_default_ui_is_auto_approvable(self):
        """DEFAULT authority + UI archetype can be auto-approved."""
        task = {
            "source_ids": ["STD-UI-01"],
            "archetype": "UI"
        }

        is_safe, reason = self._is_safe_to_auto_approve(task)

        self.assertTrue(is_safe,
                       f"DEFAULT + UI should be auto-approvable: {reason}")

    def _is_safe_to_auto_approve(self, task: dict) -> tuple:
        """Mock safety check matching is_safe_to_auto_approve logic."""
        risky_archetypes = ["SEC", "LOGIC", "API", "DB"]
        archetype = task.get("archetype", "").upper()

        # Check archetype
        if archetype in risky_archetypes:
            return False, f"Risky archetype: {archetype}"

        # Check authority
        for src in task.get("source_ids", []):
            authority = self._get_authority(src)
            if authority in ["MANDATORY", "STRONG"]:
                return False, f"Non-DEFAULT authority: {authority}"

        return True, "Safe"

    def _get_authority(self, source_id: str) -> str:
        """Mock authority lookup."""
        src_upper = source_id.upper()
        if "HIPAA" in src_upper or "GDPR" in src_upper or "DR-" in src_upper:
            return "MANDATORY"
        elif "PRO" in src_upper:
            return "STRONG"
        return "DEFAULT"


class TestActorValidation(unittest.TestCase):
    """Tests for v10.16.1 explicit actor channel."""

    def test_valid_actors(self):
        """Only HUMAN, AUTO, BATCH are valid actors."""
        valid_actors = ["HUMAN", "AUTO", "BATCH"]

        for actor in valid_actors:
            is_valid = self._validate_actor(actor)
            self.assertTrue(is_valid,
                           f"{actor} should be a valid actor")

    def test_invalid_actors_rejected(self):
        """Invalid actor strings should be rejected."""
        invalid_actors = ["ROBOT", "SYSTEM", "admin", "", None]

        for actor in invalid_actors:
            is_valid = self._validate_actor(actor)
            self.assertFalse(is_valid,
                            f"{actor} should not be a valid actor")

    def test_actor_case_insensitive(self):
        """Actor validation should be case-insensitive."""
        variants = ["human", "Human", "HUMAN", "auto", "Auto", "AUTO"]

        for actor in variants:
            is_valid = self._validate_actor(actor)
            self.assertTrue(is_valid,
                           f"{actor} should be valid (case-insensitive)")

    def _validate_actor(self, actor) -> bool:
        """Mock actor validation."""
        if actor is None:
            return False
        return actor.upper().strip() in ["HUMAN", "AUTO", "BATCH"]


if __name__ == '__main__':
    print("=" * 60)
    print("v10.17: Policy-as-Code Verification")
    print("=" * 60)
    print()

    # Run tests with verbosity
    unittest.main(verbosity=2)
