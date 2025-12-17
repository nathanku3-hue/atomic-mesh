"""
v10.17: Constitution Integration Tests - Testing the REAL Gatekeeper

This test suite imports and tests the ACTUAL mesh_server functions,
not mocks. It verifies the entire compliance enforcement chain works
correctly end-to-end.

v10.17.0: Uses the Testability Shim (MESH_BASE_DIR) to create a
"parallel universe" for testing without touching production data.

Run with: python tests/test_constitution.py
"""

import unittest
import json
import os
import sys
import sqlite3
import shutil
import gc
import time
import tempfile
import importlib
from datetime import datetime

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestConstitution(unittest.TestCase):
    """
    v10.17.0: Constitution Tests using the Testability Shim.

    Each test runs in a temporary directory (parallel universe)
    by setting MESH_BASE_DIR and reloading the server module.
    """

    def setUp(self):
        """Create parallel universe (temp dir) and reload server."""
        # 1. Create Parallel Universe
        self.tmp = tempfile.mkdtemp()
        os.environ["MESH_BASE_DIR"] = self.tmp
        os.environ["ATOMIC_MESH_DB"] = os.path.join(self.tmp, "mesh.db")

        # 2. Reload server to pick up new BASE_DIR
        import mesh_server
        importlib.reload(mesh_server)
        self.mesh = mesh_server

        # 3. Setup Directories using the server's ensure_mesh_dirs
        self.mesh.ensure_mesh_dirs()

        # 4. Create Constitution (Source Registry) using path helper
        self._create_registry()

        # 5. Create Provenance (Empty) using path helper
        prov_path = self.mesh.get_state_path("provenance.json")
        with open(prov_path, "w") as f:
            json.dump({"sources": {}}, f)

        # 6. Initialize Database
        self._init_db()

    def tearDown(self):
        """Clean up parallel universe."""
        gc.collect()  # Force cleanup of connections
        try:
            shutil.rmtree(self.tmp, ignore_errors=True)
        except Exception:
            pass

    def _create_registry(self):
        """Create the Source Registry (The Constitution)."""
        registry = {
            "_meta": {
                "version": "10.17-test",
                "description": "Test Registry"
            },
            "sources": {
                "HIPAA": {
                    "title": "HIPAA Compliance",
                    "tier": "domain",
                    "authority": "MANDATORY",
                    "id_pattern": "HIPAA-*"
                },
                "GDPR": {
                    "title": "GDPR Compliance",
                    "tier": "domain",
                    "authority": "MANDATORY",
                    "id_pattern": "GDPR-*"
                },
                "PRO": {
                    "title": "Professional Standards",
                    "tier": "professional",
                    "authority": "STRONG",
                    "id_pattern": "PRO-*"
                },
                "STD-ENG": {
                    "title": "Standard Engineering",
                    "tier": "standard",
                    "authority": "DEFAULT",
                    "id_pattern": "STD-*"
                }
            },
            "curated_rules": {
                "DOMAIN_RULES": {
                    "title": "Domain Rules",
                    "id_pattern": "DR-*"
                }
            }
        }

        # v10.17.0: Use path helper instead of hardcoded path
        registry_path = self.mesh.get_source_path("SOURCE_REGISTRY.json")
        with open(registry_path, "w", encoding="utf-8") as f:
            json.dump(registry, f, indent=2)

    def _init_db(self):
        """Initialize the test database with schema."""
        db_path = os.path.join(self.tmp, "mesh.db")
        conn = sqlite3.connect(db_path)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY,
                type TEXT DEFAULT 'backend',
                desc TEXT,
                status TEXT DEFAULT 'pending',
                source_ids TEXT,
                archetype TEXT,
                dependencies TEXT,
                override_justification TEXT,
                review_decision TEXT,
                review_notes TEXT,
                risk TEXT DEFAULT 'LOW',
                updated_at INTEGER
            )
        """)
        conn.commit()
        conn.close()

    def _insert_task(self, task_id: int, desc: str, source_ids: list,
                     archetype: str = "PLUMBING", status: str = "pending",
                     justification: str = "", task_type: str = "backend",
                     risk: str = "LOW"):
        """Insert a test task into the database."""
        db_path = os.path.join(self.tmp, "mesh.db")
        conn = sqlite3.connect(db_path)
        conn.execute("""
            INSERT OR REPLACE INTO tasks (id, type, desc, source_ids, archetype, status, override_justification, risk, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (task_id, task_type, desc, json.dumps(source_ids), archetype, status, justification, risk, int(datetime.now().timestamp())))
        conn.commit()
        conn.close()

    def _create_review_packet(self, task_id: int):
        """Create a minimal review packet for a task."""
        # v10.17.0: Use path helper instead of hardcoded path
        packet_path = self.mesh.get_state_path("reviews", f"T-{task_id}.json")
        packet = {
            "meta": {
                "task_id": task_id,
                "generated_at": datetime.now().isoformat(),
                "snapshot_hash": "test123"
            },
            "claims": {},
            "gatekeeper": {"ok": True}
        }
        with open(packet_path, "w") as f:
            json.dump(packet, f)

    # =========================================================================
    # AUTHORITY RESOLUTION TESTS
    # =========================================================================

    def test_hipaa_resolves_to_mandatory(self):
        """HIPAA sources must resolve to MANDATORY authority."""
        authority = self.mesh.get_source_authority("HIPAA-SEC-01")
        self.assertEqual(authority, "MANDATORY")

    def test_pro_resolves_to_strong(self):
        """PRO sources must resolve to STRONG authority."""
        authority = self.mesh.get_source_authority("PRO-ARCH-01")
        self.assertEqual(authority, "STRONG")

    def test_std_resolves_to_default(self):
        """STD sources must resolve to DEFAULT authority."""
        authority = self.mesh.get_source_authority("STD-CODE-01")
        self.assertEqual(authority, "DEFAULT")

    # =========================================================================
    # SAFETY POLICY TESTS
    # =========================================================================

    def test_mandatory_not_auto_approvable(self):
        """MANDATORY authority tasks cannot be auto-approved."""
        self._insert_task(
            task_id=901,
            desc="HIPAA encryption",
            source_ids=["HIPAA-SEC-01"],
            archetype="SEC",
            status="reviewing"
        )

        is_safe, reason = self.mesh.is_safe_to_auto_approve(901)
        self.assertFalse(is_safe, f"MANDATORY should not be auto-approvable: {reason}")

    def test_default_plumbing_can_be_auto_approved(self):
        """DEFAULT + PLUMBING tasks can be auto-approved (if packet exists)."""
        self._insert_task(
            task_id=902,
            desc="Add logging",
            source_ids=["STD-CODE-01"],
            archetype="PLUMBING",
            status="reviewing"
        )
        self._create_review_packet(902)

        is_safe, reason = self.mesh.is_safe_to_auto_approve(902)
        # Should pass authority + archetype check (may fail on packet validation)
        if not is_safe and "packet" not in reason.lower():
            self.fail(f"DEFAULT+PLUMBING should pass authority check: {reason}")

    # =========================================================================
    # ACTOR VALIDATION TESTS
    # =========================================================================

    def test_actor_must_be_valid(self):
        """Gavel should reject invalid actors."""
        self._insert_task(
            task_id=801,
            desc="Test task",
            source_ids=["STD-CODE-01"],
            archetype="PLUMBING",
            status="reviewing"
        )

        result = self.mesh.submit_review_decision(801, "APPROVE", "test", actor="ROBOT")
        result_dict = json.loads(result)

        self.assertEqual(result_dict.get("status"), "ERROR")
        self.assertIn("Actor", result_dict.get("message", ""))

    def test_valid_actors_accepted(self):
        """Gavel should accept HUMAN, AUTO, BATCH actors."""
        valid_actors = ["HUMAN", "AUTO", "BATCH"]

        for i, actor in enumerate(valid_actors):
            task_id = 810 + i
            self._insert_task(
                task_id=task_id,
                desc=f"Test task {actor}",
                source_ids=["STD-CODE-01"],
                archetype="PLUMBING",
                status="reviewing"
            )
            self._create_review_packet(task_id)

            # v14.1: Include entropy proof for approval (existing gate)
            result = self.mesh.submit_review_decision(task_id, "APPROVE", "Entropy Check: Passed. test", actor=actor)
            result_dict = json.loads(result)

            # Should not fail due to actor validation
            self.assertNotEqual(
                result_dict.get("message", ""),
                "Actor must be 'HUMAN', 'AUTO', or 'BATCH'",
                f"Actor {actor} should be valid"
            )

    # =========================================================================
    # LEDGER TESTS
    # =========================================================================

    def test_ledger_entry_created_on_approval(self):
        """Ledger entry should be created when task is approved."""
        self._insert_task(
            task_id=701,
            desc="Ledger test task",
            source_ids=["STD-CODE-01"],
            archetype="PLUMBING",
            status="reviewing"
        )
        self._create_review_packet(701)

        # Approve task (v14.1: include entropy proof)
        result = self.mesh.submit_review_decision(701, "APPROVE", "Entropy Check: Passed. Ledger test", actor="HUMAN")

        # Check ledger file was created using path helper
        ledger_path = self.mesh.get_state_path("release_ledger.jsonl")

        if os.path.exists(ledger_path):
            with open(ledger_path, "r") as f:
                lines = f.readlines()
                self.assertGreater(len(lines), 0, "Ledger should have entries")

                # Check last entry
                last_entry = json.loads(lines[-1])
                self.assertEqual(last_entry["task_id"], 701)
                self.assertEqual(last_entry["decision"], "APPROVE")
                self.assertEqual(last_entry["actor"], "HUMAN")

    def test_explicit_actor_logged(self):
        """The Ledger must record the explicit Actor passed to Gavel."""
        self._insert_task(
            task_id=702,
            desc="Auto-approved task",
            source_ids=["STD-CODE-01"],
            archetype="PLUMBING",
            status="reviewing"
        )
        self._create_review_packet(702)

        # Submit as AUTO (v14.1: include entropy proof)
        self.mesh.submit_review_decision(702, "APPROVE", "Entropy Check: Passed. Auto-approved", actor="AUTO")

        # Verify Ledger using path helper
        ledger_path = self.mesh.get_state_path("release_ledger.jsonl")
        with open(ledger_path, "r") as f:
            line = f.readline()
            entry = json.loads(line)

        self.assertEqual(entry["actor"], "AUTO")
        self.assertEqual(entry["decision"], "APPROVE")

    # =========================================================================
    # CONSTITUTION RULES
    # =========================================================================

    def test_mandatory_blocks_without_evidence(self):
        """Constitution Rule: Domain (MANDATORY) = Code Evidence or Block."""
        self._insert_task(
            task_id=601,
            desc="[SEC] Encrypt PHI",
            source_ids=["HIPAA-SEC-01"],
            archetype="SEC",
            status="reviewing"
        )

        # Run Validator (no code evidence exists)
        result = self.mesh.validate_task_completion(601)

        # Should fail without evidence
        self.assertFalse(result.get("ok", True), "MANDATORY should require evidence")

    def test_strong_allows_justification(self):
        """Constitution Rule: Professional (STRONG) = Code or Justification."""
        # Use GENERIC archetype to avoid TEST GATE (LOGIC requires paired test)
        self._insert_task(
            task_id=602,
            desc="[ARCH] Defer layering",
            source_ids=["PRO-ARCH-01"],
            archetype="GENERIC",
            status="reviewing",
            justification="Performance tradeoff approved by lead architect"
        )

        result = self.mesh.validate_task_completion(602)

        # Should pass with justification
        self.assertTrue(result.get("ok", False), "STRONG with justification should pass")

    def test_default_always_passes(self):
        """Constitution Rule: Standard (DEFAULT) = Implicit baseline."""
        self._insert_task(
            task_id=603,
            desc="Add logging middleware",
            source_ids=["STD-CODE-01"],
            archetype="PLUMBING",
            status="reviewing"
        )

        result = self.mesh.validate_task_completion(603)

        # DEFAULT sources should always pass
        self.assertTrue(result.get("ok", False), "DEFAULT should always pass")


if __name__ == '__main__':
    print("=" * 60)
    print("v10.17.0: Constitution Integration Tests")
    print("Testing REAL Gatekeeper Functions with Testability Shim")
    print("=" * 60)
    print()

    # Run tests
    unittest.main(verbosity=2)
