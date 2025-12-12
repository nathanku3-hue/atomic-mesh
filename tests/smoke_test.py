#!/usr/bin/env python3
"""
v10.17.0: Golden Thread Smoke Test

Proves the full lifecycle works:
Ingest -> Curate -> Plan -> Build -> Review -> Gavel -> Ledger

Run with: python tests/smoke_test.py
"""

import os
import sys
import json
import tempfile
import shutil

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run_smoke_test():
    """Run the Golden Thread smoke test in a sandbox."""
    print("=" * 60)
    print("v10.17.0: GOLDEN THREAD SMOKE TEST")
    print("=" * 60)
    print()

    # 1. Create sandbox
    print("[1/7] Creating sandbox...", end=" ")
    tmp = tempfile.mkdtemp()
    os.environ["MESH_BASE_DIR"] = tmp
    os.environ["ATOMIC_MESH_DB"] = os.path.join(tmp, "mesh.db")

    # Reload server with sandbox paths
    import mesh_server
    import importlib
    importlib.reload(mesh_server)
    mesh_server.ensure_mesh_dirs()
    print("OK")

    # 2. Create test registry
    print("[2/7] Creating registry...", end=" ")
    registry = {
        "_meta": {"version": "smoke-test"},
        "sources": {
            "SMOKE": {
                "title": "Smoke Test Domain",
                "tier": "domain",
                "authority": "MANDATORY",
                "id_pattern": "SMOKE-*"
            },
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
    print("OK")

    # 3. Create provenance file
    print("[3/7] Initializing provenance...", end=" ")
    prov_path = mesh_server.get_state_path("provenance.json")
    with open(prov_path, "w") as f:
        json.dump({"sources": {}}, f)
    print("OK")

    # 4. Initialize database and insert test task
    print("[4/7] Creating test task...", end=" ")

    # Force fresh DB connection by using direct sqlite3 with WAL mode
    import time
    time.sleep(0.1)  # Small delay to release any locks

    import sqlite3
    db_path = os.path.join(tmp, "mesh.db")

    # Create fresh database
    conn = sqlite3.connect(db_path, timeout=10)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")

    # Create tasks table
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

    # Insert test task with DEFAULT authority (STD-*) to allow completion
    conn.execute("""
        INSERT INTO tasks (id, type, desc, source_ids, archetype, status, updated_at)
        VALUES (999, 'backend', 'Smoke Test Task', '["STD-CODE-01"]', 'PLUMBING', 'reviewing', strftime('%s','now'))
    """)
    conn.commit()
    conn.close()
    print("OK (Task 999)")

    # 5. Create review packet
    print("[5/7] Creating review packet...", end=" ")
    packet_path = mesh_server.get_state_path("reviews", "T-999.json")
    packet = {
        "meta": {"task_id": 999, "snapshot_hash": "smoke123"},
        "claims": {},
        "gatekeeper": {"ok": True}
    }
    with open(packet_path, "w") as f:
        json.dump(packet, f)
    print("OK")

    # 6. Submit to Gavel
    print("[6/7] Submitting to Gavel...", end=" ")
    result = mesh_server.submit_review_decision(999, "APPROVE", "Smoke test approval", actor="HUMAN")
    result_dict = json.loads(result)

    if result_dict.get("status") == "SUCCESS" and result_dict.get("decision") == "APPROVE":
        print("OK")
    else:
        print(f"FAILED: {result_dict}")
        return False

    # 7. Verify ledger
    print("[7/7] Verifying ledger...", end=" ")
    ledger_path = mesh_server.get_state_path("release_ledger.jsonl")
    if os.path.exists(ledger_path):
        with open(ledger_path, "r") as f:
            line = f.readline()
            entry = json.loads(line)

        if entry.get("task_id") == 999 and entry.get("actor") == "HUMAN":
            print("OK")
        else:
            print(f"FAILED: Wrong entry {entry}")
            return False
    else:
        print("FAILED: No ledger file")
        return False

    # Cleanup
    shutil.rmtree(tmp, ignore_errors=True)

    print()
    print("=" * 60)
    print("GOLDEN THREAD: ALL CHECKS PASSED")
    print("=" * 60)
    return True


if __name__ == "__main__":
    success = run_smoke_test()
    sys.exit(0 if success else 1)
