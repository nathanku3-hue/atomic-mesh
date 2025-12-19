#!/usr/bin/env python
# Minimal, fast snapshot extractor for Atomic Mesh UI.
# Imports intentionally minimal for cold-start speed.
#
# GOLDEN NUANCE PATTERN: All external calls (Python, DB, Git) happen here, not PowerShell.
# Guarantees:
# - Micro-timing guard: if elapsed > 200ms, return defaults + "fail-open"
# - Cheap commands only: git status --porcelain (~10ms)
# - Fail-open defaults: safe defaults on any error or timeout

import json
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

# Micro-timing guard threshold (milliseconds)
TIMING_GUARD_MS = 200


def find_db(repo_root: Path) -> Path:
    candidates = [repo_root / "tasks.db", repo_root / "mesh.db"]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("No tasks.db or mesh.db found")


def load_counts(db_path: Path):
    conn = sqlite3.connect(f"file:{db_path}", uri=True)
    try:
        cur = conn.execute(
            "select lane, status, count(*) as c from tasks group by lane, status"
        )
        return [{"Lane": r[0] or "UNKNOWN", "Status": r[1] or "", "Count": int(r[2])} for r in cur.fetchall()]
    finally:
        conn.close()


def load_distinct_lane_counts(db_path: Path) -> dict:
    """
    GOLDEN TRANSPLANT: lines 904-911
    Returns distinct lane counts for pending and active statuses.
    Uses DISTINCT on LOWER(COALESCE(NULLIF(lane,''), type)) for unique lanes.
    """
    pending_statuses = ("pending", "next", "planned")
    active_statuses = ("in_progress", "running")

    conn = sqlite3.connect(f"file:{db_path}", uri=True)
    try:
        # Pending: distinct lanes with pending/next/planned status
        cur = conn.execute(
            """SELECT COUNT(DISTINCT LOWER(COALESCE(NULLIF(lane,''), 'default')))
               FROM tasks WHERE LOWER(status) IN (?, ?, ?)""",
            pending_statuses
        )
        pending = cur.fetchone()[0] or 0

        # Active: distinct lanes with in_progress/running status
        cur = conn.execute(
            """SELECT COUNT(DISTINCT LOWER(COALESCE(NULLIF(lane,''), 'default')))
               FROM tasks WHERE LOWER(status) IN (?, ?)""",
            active_statuses
        )
        active = cur.fetchone()[0] or 0

        return {"pending": pending, "active": active}
    except Exception:
        return {"pending": 0, "active": 0}
    finally:
        conn.close()


def check_git_clean(repo_root: Path) -> bool:
    """
    GOLDEN TRANSPLANT: lines 1267-1268 (Ship stage git clean check)
    Returns True if working directory is clean (no uncommitted changes).
    Fast operation: git status --porcelain (~10ms typically).
    """
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=1  # 1 second timeout for safety
        )
        # Empty output means clean
        return len(result.stdout.strip()) == 0
    except Exception:
        # Fail-open: assume clean if git check fails
        return True


def check_health_status(db_path: Path) -> str:
    """
    GOLDEN TRANSPLANT: lines 1137-1143, 1186-1194
    Returns health status: "OK", "WARN", or "FAIL"
    Based on task states and adapter connectivity.
    """
    try:
        conn = sqlite3.connect(f"file:{db_path}", uri=True)
        try:
            # Check for blocked or error tasks
            cur = conn.execute(
                """SELECT COUNT(*) FROM tasks
                   WHERE LOWER(status) IN ('blocked', 'error', 'failed')"""
            )
            error_count = cur.fetchone()[0] or 0

            if error_count > 0:
                return "WARN"

            return "OK"
        finally:
            conn.close()
    except Exception:
        return "FAIL"


def get_first_problem_tasks(db_path: Path) -> dict:
    """
    GOLDEN NUANCE: Task-specific hints (P1)
    Returns first blocked and first error task IDs for actionable hints.
    """
    result = {"first_blocked_id": None, "first_error_id": None, "high_risk_unverified": 0}
    try:
        conn = sqlite3.connect(f"file:{db_path}", uri=True)
        try:
            # First blocked task
            cur = conn.execute(
                """SELECT id FROM tasks WHERE LOWER(status) = 'blocked'
                   ORDER BY updated_at DESC LIMIT 1"""
            )
            row = cur.fetchone()
            if row:
                result["first_blocked_id"] = row[0]

            # First error task
            cur = conn.execute(
                """SELECT id FROM tasks WHERE LOWER(status) IN ('error', 'failed')
                   ORDER BY updated_at DESC LIMIT 1"""
            )
            row = cur.fetchone()
            if row:
                result["first_error_id"] = row[0]

            # HIGH risk unverified count (for /ship blocking)
            cur = conn.execute(
                """SELECT COUNT(*) FROM tasks
                   WHERE LOWER(risk) = 'high' AND verified = 0"""
            )
            result["high_risk_unverified"] = cur.fetchone()[0] or 0

            return result
        finally:
            conn.close()
    except Exception:
        return result


def get_optimize_status(db_path: Path) -> dict:
    """
    GOLDEN NUANCE: Optimize stage (P7)
    Checks for entropy proof markers in task notes.
    Returns first unoptimized task ID and whether current task has proof.

    Entropy markers (from golden lines 4731-4734):
    - "Entropy Check: Passed"
    - "OPTIMIZATION WAIVED"
    - "CAPTAIN_OVERRIDE: ENTROPY"
    """
    import re
    result = {
        "first_unoptimized_id": None,
        "has_any_optimized": False,
        "total_tasks": 0
    }

    entropy_patterns = [
        r"Entropy Check:\s*Passed",
        r"OPTIMIZATION WAIVED",
        r"CAPTAIN_OVERRIDE:\s*ENTROPY"
    ]

    try:
        conn = sqlite3.connect(f"file:{db_path}", uri=True)
        try:
            # Get all active tasks with notes
            cur = conn.execute(
                """SELECT id, notes FROM tasks
                   WHERE LOWER(status) IN ('pending', 'next', 'planned', 'running', 'in_progress')
                   ORDER BY updated_at DESC"""
            )
            rows = cur.fetchall()
            result["total_tasks"] = len(rows)

            for row in rows:
                task_id, notes = row[0], row[1] or ""
                has_proof = any(re.search(p, notes, re.IGNORECASE) for p in entropy_patterns)

                if has_proof:
                    result["has_any_optimized"] = True
                elif result["first_unoptimized_id"] is None:
                    result["first_unoptimized_id"] = task_id

            return result
        finally:
            conn.close()
    except Exception:
        return result


def get_blocking_files(repo_root: Path) -> list:
    """
    GOLDEN NUANCE: /draft-plan BLOCKED + blocking files (P5)
    Calls readiness.py to get blocking files for BOOTSTRAP mode.
    Returns list of file names that are blocking (below threshold).
    """
    try:
        readiness_script = repo_root / "tools" / "readiness.py"
        if not readiness_script.exists():
            return []

        result = subprocess.run(
            ["python", str(readiness_script), str(repo_root)],
            capture_output=True,
            text=True,
            timeout=1
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            return data.get("overall", {}).get("blocking_files", [])
    except Exception:
        pass
    return []


def main():
    start_time = time.monotonic()
    repo_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    repo_root = repo_root.resolve()

    # Initialize with fail-open defaults
    payload = {
        "ProjectName": repo_root.name,
        "GeneratedAtUtc": "",
        "LaneCounts": [],
        "Drift": {"HasDrift": False, "Reason": "drift-unimplemented"},
        # GOLDEN NUANCE fields (v4)
        "ReadinessMode": "live",  # "live" or "fail-open"
        "HealthStatus": "OK",     # "OK", "WARN", "FAIL"
        "DistinctLaneCounts": {"pending": 0, "active": 0},
        "GitClean": True,
        # P1+P4: Task-specific hints + HIGH risk blocking
        "FirstBlockedTaskId": None,
        "FirstErrorTaskId": None,
        "HighRiskUnverifiedCount": 0,
        # P5: Blocking files for /draft-plan feedback
        "BlockingFiles": [],
        # P7: Optimize stage (entropy proof detection)
        "FirstUnoptimizedTaskId": None,
        "HasAnyOptimized": False,
        "OptimizeTotalTasks": 0,
    }

    try:
        db_path = find_db(repo_root)
        lane_counts = load_counts(db_path)
        payload["LaneCounts"] = lane_counts
    except Exception as exc:  # noqa: BLE001
        # Fail fast and let caller surface an adapter error.
        sys.stderr.write(str(exc))
        sys.exit(1)

    # Micro-timing guard: check elapsed time
    elapsed_ms = (time.monotonic() - start_time) * 1000
    if elapsed_ms > TIMING_GUARD_MS:
        payload["ReadinessMode"] = "fail-open"
        sys.stdout.write(json.dumps(payload, separators=(",", ":")))
        return

    # Fast operations only from here (each must complete quickly)

    # Distinct lane counts (SQL query, ~5ms)
    try:
        payload["DistinctLaneCounts"] = load_distinct_lane_counts(db_path)
    except Exception:
        pass  # Keep default

    # Check timing again
    elapsed_ms = (time.monotonic() - start_time) * 1000
    if elapsed_ms > TIMING_GUARD_MS:
        payload["ReadinessMode"] = "fail-open"
        sys.stdout.write(json.dumps(payload, separators=(",", ":")))
        return

    # Git status (~10ms typically)
    try:
        payload["GitClean"] = check_git_clean(repo_root)
    except Exception:
        pass  # Keep default True

    # Health status (~5ms)
    try:
        payload["HealthStatus"] = check_health_status(db_path)
    except Exception:
        pass  # Keep default OK

    # P1+P4: First problem tasks + HIGH risk count (~5ms)
    try:
        problem_tasks = get_first_problem_tasks(db_path)
        payload["FirstBlockedTaskId"] = problem_tasks["first_blocked_id"]
        payload["FirstErrorTaskId"] = problem_tasks["first_error_id"]
        payload["HighRiskUnverifiedCount"] = problem_tasks["high_risk_unverified"]
    except Exception:
        pass  # Keep defaults

    # P7: Optimize stage - entropy proof detection (~5ms)
    try:
        optimize_status = get_optimize_status(db_path)
        payload["FirstUnoptimizedTaskId"] = optimize_status["first_unoptimized_id"]
        payload["HasAnyOptimized"] = optimize_status["has_any_optimized"]
        payload["OptimizeTotalTasks"] = optimize_status["total_tasks"]
    except Exception:
        pass  # Keep defaults

    # P5: Blocking files for /draft-plan feedback (~50ms subprocess)
    try:
        payload["BlockingFiles"] = get_blocking_files(repo_root)
    except Exception:
        pass  # Keep default empty list

    # Final timing check
    elapsed_ms = (time.monotonic() - start_time) * 1000
    if elapsed_ms > TIMING_GUARD_MS:
        payload["ReadinessMode"] = "fail-open"

    sys.stdout.write(json.dumps(payload, separators=(",", ":")))


if __name__ == "__main__":
    main()
