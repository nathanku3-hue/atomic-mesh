#!/usr/bin/env python3
"""
v13.0.1: Static Safety Check - The Governance Enforcer

Strict by default - exceptions require explicit SAFETY-ALLOW override.
Only update_task_state() is authorized to modify task status.

Run with: python tests/static_safety_check.py
Exit Code: 0 = Pass, 1 = Fail
"""

import os
import re
import sys

# Rules: Patterns that indicate unsafe state mutation
# Note: Only catches TASK status values (pending/in_progress/reviewing/completed/blocked)
# API response dicts like {"status": "OK"} are NOT violations
FORBIDDEN_PATTERNS = [
    (r'\["status"\]\s*=', 'Direct dict assignment to status'),
    (r"\.status\s*=", 'Direct object attribute assignment to status'),
    (r"UPDATE tasks SET status", 'Raw SQL status update (use update_task_state)'),
    # Only flag dict literals with actual task status values
    (r"['\"]status['\"]\s*:\s*['\"](?:pending|in_progress|reviewing|completed)['\"]", 'Dict literal task status (use update_task_state)'),
]

# Magic string to bypass check on a specific line (e.g. for tests)
ALLOW_INLINE = "SAFETY-ALLOW: status-write"


def scan_file(path: str):
    violations = []
    in_emitter = False

    try:
        with open(path, "r", encoding="utf-8") as f:
            for i, line in enumerate(f, start=1):
                stripped = line.strip()

                # 1. Scope Detection (Robust & Simple & Async-ready)
                # Reset scope on ANY function definition.
                # Only enable if it is the authorized emitter.
                # Group 2 captures the function name regardless of async prefix
                m = re.match(r"(async\s+)?def\s+(\w+)\s*\(", stripped)
                if m:
                    func_name = m.group(2)
                    in_emitter = (func_name == "update_task_state")

                # 2. Skip comments and explicit allows
                if stripped.startswith("#") or ALLOW_INLINE in line:
                    continue

                # 3. Check patterns
                for pattern, desc in FORBIDDEN_PATTERNS:
                    if re.search(pattern, line):
                        # Exception: Inside the authorized emitter
                        if in_emitter:
                            continue

                        violations.append(f"{path}:{i} -> {desc}\n   Line: {stripped}")

    except Exception as e:
        print(f"Warning: Could not read {path}: {e}")

    return violations


def scan_codebase():
    root = os.getcwd()
    violations = []

    for dirpath, _, filenames in os.walk(root):
        # Skip standard ignore folders
        if any(x in dirpath for x in ("venv", ".git", "__pycache__", "node_modules", ".pytest_cache", ".venv")):
            continue

        # Skip tests directory - test fixtures legitimately use response dict literals
        # Production enforcement is what matters; tests mock responses
        if os.path.basename(dirpath) == "tests" or "\\tests\\" in dirpath or "/tests/" in dirpath:
            continue

        for fname in filenames:
            if not fname.endswith(".py"):
                continue

            # Skip the check script itself to avoid false positive on the regex strings
            if fname == "static_safety_check.py":
                continue

            fpath = os.path.join(dirpath, fname)
            violations.extend(scan_file(fpath))

    if violations:
        print("=" * 60)
        print("STATIC SAFETY CHECK FAILED")
        print("=" * 60)
        print("Found direct status mutations. Use 'update_task_state' or add '# SAFETY-ALLOW: status-write'.")
        print("TIP: Use SAFETY-ALLOW only for test fixtures; never for production paths.")
        print("-" * 60)
        for v in violations:
            print(v)
        print("-" * 60)
        print(f"Total violations: {len(violations)}")
        sys.exit(1)

    print("=" * 60)
    print("STATIC SAFETY CHECK PASSED")
    print("=" * 60)
    print("No unsafe state mutations found.")
    sys.exit(0)


if __name__ == "__main__":
    scan_codebase()
