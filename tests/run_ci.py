#!/usr/bin/env python3
"""
v11.0: Atomic Mesh CI Runner - The CI Judge

Consolidates Constitution Tests, Registry Check, and Golden Thread
into a single Pass/Fail gate.

Run with: python tests/run_ci.py
Exit Code: 0 = Pass, 1 = Fail

Features:
- Uses testability shim for isolated sandbox testing
- Unique timestamp-based task IDs prevent collisions
- Full Gavel pathway verification
"""

import unittest
import sys
import os
import tempfile
import shutil
import json
import importlib
import sqlite3
import time
import traceback

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run_constitution_tests():
    """Run the Constitution integration tests."""
    print("\n" + "=" * 50)
    print("⚖️  RUNNING CONSTITUTION TESTS...")
    print("=" * 50)

    loader = unittest.TestLoader()
    suite = loader.discover('tests', pattern='test_constitution.py')
    runner = unittest.TextTestRunner(verbosity=1)
    result = runner.run(suite)
    return result.wasSuccessful()


def run_registry_check():
    """Check registry alignment."""
    print("\n" + "=" * 50)
    print("🧭 CHECKING REGISTRY ALIGNMENT...")
    print("=" * 50)

    try:
        # Clear any sandbox environment from previous tests
        if "MESH_BASE_DIR" in os.environ:
            del os.environ["MESH_BASE_DIR"]
        if "ATOMIC_MESH_DB" in os.environ:
            del os.environ["ATOMIC_MESH_DB"]
        
        import mesh_server
        importlib.reload(mesh_server)  # Reload with clean environment
        
        reg_path = mesh_server.get_source_path("SOURCE_REGISTRY.json")
        
        res = mesh_server.validate_registry_alignment()
        print(res)
        # Parse JSON response and check status field
        res_dict = json.loads(res)
        return res_dict.get("status") in ["OK", "WARNING"]
    except Exception as e:
        print(f"❌ Registry check failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def run_golden_thread_smoke():
    """
    Run a fast smoke test of the critical path.
    Uses testability shim for isolation.
    """
    print("\n" + "=" * 50)
    print("🔥 RUNNING GOLDEN THREAD SMOKE TEST...")
    print("=" * 50)

    # Create isolated sandbox
    tmp = tempfile.mkdtemp()
    os.environ["MESH_BASE_DIR"] = tmp
    os.environ["ATOMIC_MESH_DB"] = os.path.join(tmp, "mesh.db")

    try:
        # Reload mesh_server with sandbox paths
        import mesh_server
        importlib.reload(mesh_server)
        mesh_server.ensure_mesh_dirs()

        # Create minimal registry
        registry = {
            "_meta": {"version": "ci-test"},
            "sources": {
                "STD-ENG": {
                    "title": "Standard Engineering",
                    "tier": "standard",
                    "authority": "DEFAULT",
                    "id_pattern": "STD-*"
                }
            }
        }
        reg_path = mesh_server.get_source_path("SOURCE_REGISTRY.json")
        with open(reg_path, "w") as f:
            json.dump(registry, f)

        # Create provenance
        prov_path = mesh_server.get_state_path("provenance.json")
        with open(prov_path, "w") as f:
            json.dump({"sources": {}}, f)

        # Initialize DB with task - use unique timestamp-based ID
        task_id = int(time.time()) % 100000  # Unique ID based on timestamp

        db_path = os.path.join(tmp, "mesh.db")
        conn = sqlite3.connect(db_path, timeout=10)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY,
                type TEXT DEFAULT 'backend',
                desc TEXT,
                status TEXT DEFAULT 'pending',
                source_ids TEXT,
                archetype TEXT,
                override_justification TEXT,
                review_decision TEXT,
                review_notes TEXT,
                updated_at INTEGER
            )
        """)
        conn.execute(f"""
            INSERT INTO tasks (id, type, desc, source_ids, archetype, status, updated_at)
            VALUES ({task_id}, 'backend', 'CI Smoke Task {task_id}', '["STD-CI-01"]', 'PLUMBING', 'reviewing', strftime('%s','now'))
        """)
        conn.commit()
        conn.close()

        # Create review packet
        packet_path = mesh_server.get_state_path("reviews", f"T-{task_id}.json")
        packet = {
            "meta": {"task_id": task_id, "snapshot_hash": f"ci{task_id}"},
            "claims": {},
            "gatekeeper": {"ok": True}
        }
        with open(packet_path, "w") as f:
            json.dump(packet, f)

        # THE CRITICAL TEST: Submit through Gavel
        result = mesh_server.submit_review_decision(task_id, "APPROVE", "CI Auto", actor="AUTO")
        result_dict = json.loads(result)

        if result_dict.get("status") == "SUCCESS":
            print("✅ Golden Thread Passed - Gavel approved task through proper channel")
            return True
        else:
            print(f"❌ Golden Thread Failed: {result_dict}")
            return False

    except Exception as e:
        print(f"❌ Exception in Smoke Test: {e}")
        traceback.print_exc()
        return False
    finally:
        # Cleanup sandbox
        shutil.rmtree(tmp, ignore_errors=True)
        # Reset environment
        if "MESH_BASE_DIR" in os.environ:
            del os.environ["MESH_BASE_DIR"]
        if "ATOMIC_MESH_DB" in os.environ:
            del os.environ["ATOMIC_MESH_DB"]


def run_static_safety():
    """Run the static safety check for Single-Writer discipline."""
    print("\n" + "=" * 50)
    print("🔍 RUNNING STATIC SAFETY CHECK...")
    print("=" * 50)

    try:
        # Run as subprocess to capture exit code properly
        import subprocess
        result = subprocess.run(
            [sys.executable, "tests/static_safety_check.py"],
            capture_output=True,
            text=True
        )
        print(result.stdout)
        if result.stderr:
            print(result.stderr)
        return result.returncode == 0
    except Exception as e:
        print(f"❌ Static safety check failed: {e}")
        return False


def main():
    print("\n" + "=" * 50)
    print("🛡️  ATOMIC MESH CI v13.0 - STARTING")
    print("=" * 50)

    checks = [
        ("Constitution", run_constitution_tests),
        ("Registry", run_registry_check),
        ("StaticSafety", run_static_safety),
        ("Golden Thread", run_golden_thread_smoke)
    ]

    failed = []
    for name, func in checks:
        try:
            if not func():
                failed.append(name)
        except Exception as e:
            print(f"❌ {name} crashed: {e}")
            failed.append(name)

    print("\n" + "=" * 50)
    if failed:
        print(f"❌ CI FAILED. Broken Gates: {', '.join(failed)}")
        print("=" * 50)
        return 1
    else:
        print("✅ CI PASSED. System is compliant.")
        print("=" * 50)
        return 0


if __name__ == "__main__":
    sys.exit(main())
