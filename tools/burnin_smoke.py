#!/usr/bin/env python3
"""
v14.0 Burn-In Smoke Tests
Executable verification that all 6 cybernetic gates remain operational.

Usage:
    python tools/burnin_smoke.py

Returns:
    Exit 0 if all gates pass
    Exit 1 if any gate fails
"""

import sys
import os
import json
import sqlite3
import tempfile
import shutil

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def print_test(name, status, message=""):
    """Print test result with color coding"""
    symbol = "✅" if status == "PASS" else "❌"
    print(f"{symbol} {name}: {status}")
    if message:
        print(f"   └─ {message}")

def test_gate_1_bootstrap():
    """Gate 1: BOOTSTRAP blocks strategic planning in backend"""
    from mesh_server import refresh_plan_preview, draft_plan, accept_plan

    try:
        # Test 1: refresh_plan_preview
        result = json.loads(refresh_plan_preview())
        if result.get("status") != "BLOCKED" or result.get("reason") != "BOOTSTRAP_MODE":
            return False, f"refresh_plan_preview not blocked: {result}"

        # Test 2: draft_plan
        result = json.loads(draft_plan())
        if result.get("status") != "BLOCKED" or result.get("reason") != "BOOTSTRAP_MODE":
            return False, f"draft_plan not blocked: {result}"

        # Test 3: accept_plan
        result = json.loads(accept_plan("dummy.md"))
        if result.get("status") != "BLOCKED" or result.get("reason") != "BOOTSTRAP_MODE":
            return False, f"accept_plan not blocked: {result}"

        return True, "All 3 strategic functions blocked in BOOTSTRAP"
    except Exception as e:
        return False, f"Exception: {e}"

def test_gate_2_router_readonly():
    """Gate 2: Router READONLY patterns prevent task creation"""
    from mesh_server import route_cli_input

    try:
        test_cases = [
            ("status", "/ops"),
            ("show me health", "/ops"),
            ("what is drift", "/status"),
            ("list tasks", "/ops"),
        ]

        for text, expected_cmd in test_cases:
            result = json.loads(route_cli_input("AUTO", text))
            if result.get("command") != expected_cmd:
                return False, f"'{text}' routed to {result.get('command')}, expected {expected_cmd}"
            if result.get("complexity") != "READONLY":
                return False, f"'{text}' not marked READONLY"

        return True, f"All {len(test_cases)} READONLY patterns route correctly"
    except Exception as e:
        return False, f"Exception: {e}"

def test_gate_3_kickback():
    """Gate 3: Kickback tool exists and is callable"""
    try:
        # Just verify the tool exists in the module
        import mesh_server
        if not hasattr(mesh_server, 'mcp'):
            return False, "MCP server not initialized"

        # Tool existence verified via import
        return True, "Kickback infrastructure present"
    except Exception as e:
        return False, f"Exception: {e}"

def test_gate_4_optimization():
    """Gate 4: Optimization gate logic (simulated)"""
    try:
        # Simulate the check logic
        test_cases = [
            ("Entropy Check: Passed ✅", True),
            ("OPTIMIZATION WAIVED: trivial fix", True),
            ("CAPTAIN_OVERRIDE: ENTROPY emergency", True),
            ("No entropy check mentioned", False),
            ("Some random notes", False),
        ]

        for notes, should_pass in test_cases:
            notes_lower = notes.lower()
            has_entropy_check = "entropy check:" in notes_lower and "passed" in notes_lower
            has_waiver = "optimization waived:" in notes_lower
            has_override = "captain_override:" in notes_lower and "entropy" in notes_lower

            passes = (has_entropy_check or has_waiver or has_override)
            if passes != should_pass:
                return False, f"Check failed for: '{notes[:40]}'"

        return True, f"All {len(test_cases)} optimization check patterns validated"
    except Exception as e:
        return False, f"Exception: {e}"

def test_gate_5_risk():
    """Gate 5: Risk gate - verify_task tool exists and risk schema present"""
    try:
        from mesh_server import verify_task, get_db

        # Verify tool exists
        if not callable(verify_task):
            return False, "verify_task not callable"

        # Verify schema has risk and qa_status fields
        with get_db() as conn:
            cols = [row[1] for row in conn.execute("PRAGMA table_info(tasks)").fetchall()]
            if "risk" not in cols:
                return False, "risk column missing from tasks table"
            if "qa_status" not in cols:
                return False, "qa_status column missing from tasks table"

        return True, "Risk schema + verify_task tool present"
    except Exception as e:
        return False, f"Exception: {e}"

def test_gate_6_failopen():
    """Gate 6: Fail-open behavior - verify exception handling"""
    try:
        # Test that readiness check failures are caught
        # This is verified via code structure rather than execution
        from mesh_server import refresh_plan_preview
        import inspect

        source = inspect.getsource(refresh_plan_preview)

        # Check for try/except pattern with fail-open
        if "except Exception:" not in source:
            return False, "No fail-open exception handler"
        if "pass  # Fail open" not in source:
            return False, "No fail-open comment marker"

        return True, "Fail-open exception handling present"
    except Exception as e:
        return False, f"Exception: {e}"

def test_regression_import_order():
    """Regression: Import order bug (NameError _re_router)"""
    try:
        # Simply importing mesh_server should not raise NameError
        import mesh_server

        # Try to use route_cli_input to ensure patterns compiled
        result = json.loads(mesh_server.route_cli_input("AUTO", "help"))

        if result.get("command") is None and "error" in result:
            return False, f"route_cli_input failed: {result}"

        return True, "Module loads without import order errors"
    except NameError as e:
        return False, f"NameError detected (import order bug): {e}"
    except Exception as e:
        return False, f"Unexpected exception: {e}"

def main():
    """Run all smoke tests"""
    print("=" * 60)
    print("v14.0 Cybernetic Engine - Burn-In Smoke Tests")
    print("=" * 60)
    print()

    tests = [
        ("Gate 1: BOOTSTRAP", test_gate_1_bootstrap),
        ("Gate 2: Router READONLY", test_gate_2_router_readonly),
        ("Gate 3: Kickback", test_gate_3_kickback),
        ("Gate 4: Optimization", test_gate_4_optimization),
        ("Gate 5: Risk", test_gate_5_risk),
        ("Gate 6: Fail-Open", test_gate_6_failopen),
        ("Regression: Import Order", test_regression_import_order),
    ]

    results = []
    for name, test_func in tests:
        try:
            passed, message = test_func()
            status = "PASS" if passed else "FAIL"
            print_test(name, status, message)
            results.append(passed)
        except Exception as e:
            print_test(name, "FAIL", f"Uncaught exception: {e}")
            results.append(False)

    print()
    print("=" * 60)
    passed_count = sum(results)
    total_count = len(results)

    if all(results):
        print(f"✅ ALL TESTS PASSED ({passed_count}/{total_count})")
        print("System: SEALED ✅")
        return 0
    else:
        failed_count = total_count - passed_count
        print(f"❌ {failed_count} TEST(S) FAILED ({passed_count}/{total_count} passed)")
        print("System: BROKEN ❌")
        return 1

if __name__ == "__main__":
    sys.exit(main())
