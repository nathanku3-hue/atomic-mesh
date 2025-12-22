#!/usr/bin/env python
# Minimal, fast snapshot extractor for Atomic Mesh UI.
# Imports intentionally minimal for cold-start speed.
#
# GOLDEN NUANCE PATTERN: All external calls (Python, DB, Git) happen here, not PowerShell.
# Guarantees:
# - Micro-timing guard: if elapsed > 500ms, return defaults + "fail-open"
# - Cheap commands only: git status --porcelain (~10ms)
# - Fail-open defaults: safe defaults on any error or timeout

import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

# Micro-timing guard threshold (milliseconds)
# Must exceed Python startup (~150ms) + module load + readiness.py (~100ms)
# Measured ~450ms on Windows; use 500ms for typical execution
TIMING_GUARD_MS = 500


def _dict_from_row(row, keys):
    """Best-effort projection of sqlite row to dict using provided keys."""
    out = {}
    for k in keys:
        try:
            out[k] = row[k]
        except Exception:
            out[k] = None
    return out


def _has_column(conn: sqlite3.Connection, table: str, column: str) -> bool:
    try:
        cur = conn.execute(f"PRAGMA table_info({table})")
        return any(r[1] == column for r in cur.fetchall())
    except Exception:
        return False


def find_db(repo_root: Path) -> Path:
    """
    Find the database file. Priority:
    1. ATOMIC_MESH_DB environment variable (explicit override)
    2. mesh.db (matches mesh_server.py default)
    3. tasks.db (legacy fallback)

    This ensures snapshot.py reads from the same DB that mesh_server.py writes to.
    """
    # Check env var first (same as mesh_server.py)
    env_db = os.getenv("ATOMIC_MESH_DB")
    if env_db:
        env_path = Path(env_db)
        if env_path.exists():
            return env_path

    # Priority order: mesh.db first (matches mesh_server.py default), then tasks.db
    candidates = [repo_root / "mesh.db", repo_root / "tasks.db"]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("No mesh.db or tasks.db found")


def load_counts(db_path: Path):
    conn = sqlite3.connect(f"file:{db_path}", uri=True)
    try:
        cur = conn.execute(
            "select lane, status, count(*) as c from tasks group by lane, status"
        )
        return [{"Lane": r[0] or "UNKNOWN", "Status": r[1] or "", "Count": int(r[2])} for r in cur.fetchall()]
    finally:
        conn.close()


def load_history_data(db_path: Path) -> dict:
    """
    Fast history sampler for UI overlay.
    Returns active task (1), pending tasks (<=5), audit log (<=10), scheduler decision.
    """
    result = {
        "active_task": None,
        "pending_tasks": [],
        "history": [],
        "scheduler_last_decision": None,
    }

    try:
        conn = sqlite3.connect(f"file:{db_path}", uri=True)
        conn.row_factory = sqlite3.Row
        try:
            # Active task (now)
            has_progress = _has_column(conn, "tasks", "progress")
            active_sql = """SELECT id, type, lane, desc, 'in_progress' AS status, created_at{progress_col}
                            FROM tasks
                            WHERE status='in_progress'
                            ORDER BY created_at ASC
                            LIMIT 1"""
            progress_col = ", progress" if has_progress else ""
            cur = conn.execute(active_sql.format(progress_col=progress_col))
            row = cur.fetchone()
            if row:
                keys = ["id", "type", "lane", "desc", "status", "created_at"]
                if has_progress:
                    keys.append("progress")
                result["active_task"] = _dict_from_row(row, keys)

            # Pending tasks (next) - match scheduler sort
            cur = conn.execute(
                """SELECT id, type, lane, desc, 'pending' AS status, priority, created_at
                   FROM tasks
                   WHERE status='pending'
                   ORDER BY priority ASC, created_at ASC, id ASC
                   LIMIT 5"""
            )
            pending = [
                _dict_from_row(
                    r,
                    ("id", "type", "lane", "desc", "status", "priority", "created_at"),
                )
                for r in cur.fetchall()
            ]
            result["pending_tasks"] = pending

            # Audit history (past)
            cur = conn.execute(
                """SELECT task_id, action, reason AS desc, created_at
                   FROM audit_log
                   ORDER BY created_at DESC
                   LIMIT 10"""
            )
            history = [
                _dict_from_row(r, ("task_id", "action", "desc", "created_at"))
                for r in cur.fetchall()
            ]
            result["history"] = history

            # Scheduler last decision (observability)
            cur = conn.execute(
                "SELECT value FROM config WHERE key='scheduler_last_decision' LIMIT 1"
            )
            dec_row = cur.fetchone()
            if dec_row and dec_row["value"]:
                try:
                    result["scheduler_last_decision"] = json.loads(dec_row["value"])
                except Exception:
                    result["scheduler_last_decision"] = dec_row["value"]
        finally:
            conn.close()
    except Exception:
        # Fail-open: keep defaults
        pass

    return result


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


def _get_fallback_thresholds() -> dict:
    """
    Get thresholds with fallback chain:
    1. Import from readiness.py (single source of truth)
    2. Hardcoded last-resort if import fails
    """
    try:
        from readiness import THRESHOLDS
        return THRESHOLDS.copy()
    except ImportError:
        # Last resort - only if readiness.py can't be imported at all
        return {"PRD": 90, "SPEC": 90, "DECISION_LOG": 60}


def get_readiness_data(repo_root: Path) -> dict:
    """
    GOLDEN NUANCE: /draft-plan BLOCKED + blocking files (P5) + rated doc scores (P8)
    Calls readiness.py subprocess to get full readiness data including per-doc scores.
    Returns dict with blocking_files, per-doc scores, and thresholds.

    Fallback chain for thresholds:
    1. Subprocess call to readiness.py (primary - includes scoring)
    2. Import THRESHOLDS from readiness.py (if subprocess fails)
    3. Hardcoded last-resort (if even import fails)
    """
    # Get fallback thresholds (import or hardcoded last-resort)
    fallback_thresholds = _get_fallback_thresholds()

    def _make_default_result(thresholds: dict) -> dict:
        return {
            "blocking_files": [],
            "doc_scores": {
                "PRD": {"score": 0, "exists": False, "threshold": thresholds["PRD"], "hint": ""},
                "SPEC": {"score": 0, "exists": False, "threshold": thresholds["SPEC"], "hint": ""},
                "DECISION_LOG": {"score": 0, "exists": False, "threshold": thresholds["DECISION_LOG"], "hint": ""},
            },
            "docs_all_passed": False,
        }

    try:
        # readiness.py is in the same directory as snapshot.py (module's tools/)
        # NOT in the project's tools/ directory
        readiness_script = Path(__file__).parent / "readiness.py"
        if not readiness_script.exists():
            return _make_default_result(fallback_thresholds)

        result = subprocess.run(
            ["python", str(readiness_script), str(repo_root)],
            capture_output=True,
            text=True,
            timeout=0.35,  # Keep under the 500ms snapshot budget (with overhead)
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)

            # Extract blocking files
            blocking_files = data.get("overall", {}).get("blocking_files", [])

            # Extract per-doc scores with thresholds (from subprocess response)
            doc_scores = {}
            files_data = data.get("files", {})
            thresholds = data.get("thresholds", fallback_thresholds)

            for doc_name in ["PRD", "SPEC", "DECISION_LOG"]:
                file_data = files_data.get(doc_name, {})
                threshold = thresholds.get(doc_name, fallback_thresholds.get(doc_name, 80))
                doc_scores[doc_name] = {
                    "score": file_data.get("score", 0),
                    "exists": file_data.get("exists", False),
                    "threshold": threshold,
                    "hint": file_data.get("hint", ""),
                }

            # Check if all docs pass their thresholds
            docs_all_passed = all(
                doc_scores[d]["score"] >= doc_scores[d]["threshold"]
                for d in ["PRD", "SPEC", "DECISION_LOG"]
            )

            return {
                "blocking_files": blocking_files,
                "doc_scores": doc_scores,
                "docs_all_passed": docs_all_passed,
            }
    except Exception:
        pass
    # Subprocess failed - use fallback thresholds from import
    return _make_default_result(fallback_thresholds)


def get_blocking_files(repo_root: Path) -> list:
    """
    GOLDEN NUANCE: /draft-plan BLOCKED + blocking files (P5)
    Calls readiness.py to get blocking files for BOOTSTRAP mode.
    Returns list of file names that are blocking (below threshold).

    NOTE: This is a legacy wrapper. New code should use get_readiness_data().
    """
    return get_readiness_data(repo_root)["blocking_files"]


# =============================================================================
# Librarian Feedback Cache (Optional, Out-of-Band)
# =============================================================================
# Librarian subagent writes feedback to a cache file. snapshot.py reads it
# (fast, ~1ms) and injects into payload. No LLM calls in this path.

LIBRARIAN_CACHE_PATH = "control/state/librarian_doc_feedback.json"
LIBRARIAN_STALE_SECONDS = 600  # 10 minutes


def get_librarian_feedback(project_path: Path) -> dict:
    """
    Read Librarian-generated doc feedback from cache file.

    Cache location: <ProjectPath>/control/state/librarian_doc_feedback.json

    Returns dict with:
        - docs: { PRD: {one_liner, paragraph}, SPEC: {...}, DECISION_LOG: {...} }
        - stale: True if file mtime > 10 minutes old
        - present: True if any Librarian data exists (quality/confidence/docs)
        - overall_quality: 0-5 scale (0 = not present)
        - confidence: 0-100 scale (0 = not present)
        - critical_risks_count: count of critical risks flagged

    Fail-open: returns empty defaults if file missing/invalid.
    """
    default_doc = {"one_liner": "", "paragraph": ""}
    default_result = {
        "docs": {
            "PRD": default_doc.copy(),
            "SPEC": default_doc.copy(),
            "DECISION_LOG": default_doc.copy(),
        },
        "stale": False,
        "present": False,
        # Tier 2 fields
        "overall_quality": 0,
        "confidence": 0,
        "critical_risks_count": 0,
    }

    cache_path = project_path / LIBRARIAN_CACHE_PATH
    if not cache_path.exists():
        return default_result

    try:
        # Check staleness via file mtime (no datetime parsing)
        mtime = cache_path.stat().st_mtime
        stale = (time.time() - mtime) > LIBRARIAN_STALE_SECONDS

        # Parse JSON
        content = cache_path.read_text(encoding="utf-8")
        data = json.loads(content)

        # Extract docs feedback
        docs_data = data.get("docs", {})
        result_docs = {}
        has_doc_entries = False
        for doc_name in ["PRD", "SPEC", "DECISION_LOG"]:
            doc_feedback = docs_data.get(doc_name, {})
            one_liner = doc_feedback.get("one_liner", "")
            paragraph = doc_feedback.get("paragraph", "")
            result_docs[doc_name] = {
                "one_liner": one_liner,
                "paragraph": paragraph,
            }
            if one_liner or paragraph:
                has_doc_entries = True

        # Extract Tier 2 fields with clamping
        raw_quality = data.get("overall_quality", 0)
        raw_confidence = data.get("confidence", 0)
        critical_risks = data.get("critical_risks", [])

        # Clamp to valid ranges
        overall_quality = max(0, min(5, int(raw_quality) if raw_quality else 0))
        confidence = max(0, min(100, int(raw_confidence) if raw_confidence else 0))
        critical_risks_count = len(critical_risks) if isinstance(critical_risks, list) else 0

        # present = any Librarian data exists (not just docs)
        present = has_doc_entries or overall_quality > 0 or confidence > 0

        return {
            "docs": result_docs,
            "stale": stale,
            "present": present,
            "overall_quality": overall_quality,
            "confidence": confidence,
            "critical_risks_count": critical_risks_count,
        }
    except Exception:
        # Fail-open: invalid JSON or read error → ignore
        return default_result


# =============================================================================
# Initialization Detection (Single Source of Truth)
# =============================================================================
# These constants define what "initialized" means. All other code should call
# check_initialized() rather than duplicating these rules.

INIT_MARKER_PATH = "control/state/.mesh_initialized"
INIT_GOLDEN_DOCS = ["docs/PRD.md", "docs/SPEC.md", "docs/DECISION_LOG.md"]
INIT_DOCS_THRESHOLD = 2  # Minimum docs required for initialization


def get_plan_status(repo_root: Path) -> dict:
    """
    Detect plan status by checking for draft files in docs/PLANS/.

    Returns dict with:
        - has_draft: True if any draft_*.md files exist
        - accepted: True if tasks exist in DB (plan was accepted)
        - status: "DRAFT" | "ACCEPTED" | "MISSING"
        - id: Latest draft filename (if exists)

    This enables the Next hint to show /accept-plan after /draft-plan.
    """
    result = {
        "has_draft": False,
        "accepted": False,
        "status": "MISSING",
        "id": None,
        "summary": ""
    }

    # Check for draft files in docs/PLANS/
    plans_dir = repo_root / "docs" / "PLANS"
    if plans_dir.exists():
        drafts = sorted(plans_dir.glob("draft_*.md"), reverse=True)
        if drafts:
            result["has_draft"] = True
            result["id"] = drafts[0].name
            result["status"] = "DRAFT"

    return result


def check_initialized(repo_root: Path) -> bool:
    """
    Check if project is initialized.

    Contract:
        Returns True if EITHER:
        - Marker file exists: {repo_root}/control/state/.mesh_initialized
        - At least 2 of 3 golden docs exist: PRD.md, SPEC.md, DECISION_LOG.md

        Returns False otherwise (empty dir, only 1 doc, etc.)

        This is INDEPENDENT of database presence - a project can be initialized
        (have docs/marker) but not yet have a tasks.db.

    Single Source of Truth:
        This function defines the initialization rules. The PowerShell version
        (src/AtomicMesh.UI/Private/Helpers/InitHelpers.ps1::Test-RepoInitialized)
        mirrors this logic for local guards. Keep both in sync - this Python
        version is authoritative for snapshot generation.

    Args:
        repo_root: Path to the project root directory

    Returns:
        True if initialized, False otherwise
    """
    # Tier A: Check for marker file (created by /init command)
    marker_path = repo_root / INIT_MARKER_PATH
    if marker_path.exists():
        return True

    # Tier B: Check golden docs (2 of 3 required)
    found = sum(1 for doc in INIT_GOLDEN_DOCS if (repo_root / doc).exists())
    if found >= INIT_DOCS_THRESHOLD:
        return True

    return False


def main():
    start_time = time.monotonic()
    repo_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    repo_root = repo_root.resolve()

    # Get fallback thresholds (single source of truth from readiness.py)
    _thresholds = _get_fallback_thresholds()

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
        # P8: Doc readiness with per-doc scores for rated display
        # Thresholds from _get_fallback_thresholds() (single source of truth)
        "DocScores": {
            "PRD": {"score": 0, "exists": False, "threshold": _thresholds["PRD"], "hint": ""},
            "SPEC": {"score": 0, "exists": False, "threshold": _thresholds["SPEC"], "hint": ""},
            "DECISION_LOG": {"score": 0, "exists": False, "threshold": _thresholds["DECISION_LOG"], "hint": ""},
        },
        "DocsAllPassed": False,
        # Legacy fields (kept for backward compat, derived from DocScores)
        "DocsReadiness": {"PRD": False, "SPEC": False, "DECISION_LOG": False},
        "DocsReadyCount": 0,
        "DocsTotalCount": 3,
        # Librarian feedback (optional, from out-of-band cache)
        "LibrarianDocFeedback": {
            "PRD": {"one_liner": "", "paragraph": ""},
            "SPEC": {"one_liner": "", "paragraph": ""},
            "DECISION_LOG": {"one_liner": "", "paragraph": ""},
        },
        "LibrarianDocFeedbackStale": False,
        "LibrarianDocFeedbackPresent": False,
        # Tier 2: Librarian quality metrics (0 = not present)
        "LibrarianOverallQuality": 0,      # 0-5 scale
        "LibrarianConfidence": 0,          # 0-100 scale
        "LibrarianCriticalRisksCount": 0,  # count of critical risks
        # Initialization status (separate from DB presence)
        "IsInitialized": False,
        # Plan status (for Next hint: /draft-plan vs /accept-plan)
        "plan": {
            "has_draft": False,
            "accepted": False,
            "status": "MISSING",
            "id": None,
            "summary": ""
        },
        # History data for overlays (fast, limited)
        "active_task": None,
        "pending_tasks": [],
        "history": [],
        "scheduler_last_decision": None,
        # Debug: paths tried (for diagnosing "backend unavailable")
        "DbPathTried": None,
        "ProjectRoot": str(repo_root),
    }

    # Database is optional - new projects may not have one yet
    db_path = None
    db_present = False
    db_candidates = [repo_root / "tasks.db", repo_root / "mesh.db"]
    payload["DbPathTried"] = str(db_candidates[0])  # Primary candidate for debug
    try:
        db_path = find_db(repo_root)
        db_present = True
        payload["DbPathTried"] = str(db_path)  # Actual path found
        lane_counts = load_counts(db_path)
        payload["LaneCounts"] = lane_counts
    except FileNotFoundError:
        # No database = new/uninitialized project, continue with defaults
        payload["ReadinessMode"] = "no-db"  # Explicit degraded mode
        payload["DbPresent"] = False
        pass
    except Exception as exc:  # noqa: BLE001
        # DB errors (missing table, corruption, lock, etc.) = treat as no-db
        # "no such table: tasks" is common when DB file exists but schema not created
        exc_str = str(exc).lower()
        if "no such table" in exc_str or "unable to open" in exc_str:
            payload["ReadinessMode"] = "no-db"
            payload["DbPresent"] = False
            db_present = False  # Prevent further DB queries
        else:
            # Unexpected error - log and fail
            sys.stderr.write(str(exc))
            sys.exit(1)

    if db_present:
        payload["DbPresent"] = True

    # Check initialization status (fast file check, ~1ms)
    try:
        payload["IsInitialized"] = check_initialized(repo_root)
    except Exception:
        payload["IsInitialized"] = False  # Fail-open: assume not initialized

    # Plan status detection (fast file check, ~1ms)
    try:
        plan_status = get_plan_status(repo_root)
        # Also check if tasks exist in DB (means plan was accepted)
        if db_present and payload.get("LaneCounts"):
            total_tasks = sum(lc.get("Count", 0) for lc in payload["LaneCounts"])
            if total_tasks > 0:
                plan_status["accepted"] = True
                plan_status["status"] = "ACCEPTED"
        payload["plan"] = plan_status
    except Exception:
        pass  # Keep defaults

    # Librarian feedback cache (optional, fast file read ~1ms)
    try:
        librarian_data = get_librarian_feedback(repo_root)
        payload["LibrarianDocFeedback"] = librarian_data["docs"]
        payload["LibrarianDocFeedbackStale"] = librarian_data["stale"]
        payload["LibrarianDocFeedbackPresent"] = librarian_data["present"]
        # Tier 2 fields
        payload["LibrarianOverallQuality"] = librarian_data["overall_quality"]
        payload["LibrarianConfidence"] = librarian_data["confidence"]
        payload["LibrarianCriticalRisksCount"] = librarian_data["critical_risks_count"]
    except Exception:
        pass  # Fail-open: keep defaults

    # Micro-timing guard: check elapsed time
    elapsed_ms = (time.monotonic() - start_time) * 1000
    if elapsed_ms > TIMING_GUARD_MS:
        payload["ReadinessMode"] = "fail-open"
        sys.stdout.write(json.dumps(payload, separators=(",", ":")))
        return

    # Fast operations only from here (each must complete quickly)

    # DB-dependent operations (skip if no database)
    if db_path:
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

        # History sampler (active/pending/audit) - tight limits for overlay
        try:
            history_data = load_history_data(db_path)
            payload["active_task"] = history_data.get("active_task")
            payload["pending_tasks"] = history_data.get("pending_tasks", [])
            payload["history"] = history_data.get("history", [])
            payload["scheduler_last_decision"] = history_data.get("scheduler_last_decision")
        except Exception:
            pass  # Keep defaults

    # Git status (~10ms typically) - works without DB
    try:
        payload["GitClean"] = check_git_clean(repo_root)
    except Exception:
        pass  # Keep default True

    # P5+P8: Readiness data with per-doc scores (subprocess capped at 350ms)
    try:
        readiness_data = get_readiness_data(repo_root)
        payload["BlockingFiles"] = readiness_data["blocking_files"]
        payload["DocScores"] = readiness_data["doc_scores"]
        payload["DocsAllPassed"] = readiness_data["docs_all_passed"]

        # Legacy fields (derived from DocScores for backward compat)
        doc_keys = ["PRD", "SPEC", "DECISION_LOG"]
        blocking = readiness_data["blocking_files"]
        docs_ready = {k: k not in blocking for k in doc_keys}
        payload["DocsReadiness"] = docs_ready
        payload["DocsReadyCount"] = sum(1 for k in doc_keys if docs_ready[k])
    except Exception:
        pass  # Keep defaults (empty bars, not misleading)

    # Final timing check
    elapsed_ms = (time.monotonic() - start_time) * 1000
    if elapsed_ms > TIMING_GUARD_MS:
        payload["ReadinessMode"] = "fail-open"

    sys.stdout.write(json.dumps(payload, separators=(",", ":")))


if __name__ == "__main__":
    main()
