# Atomic Mesh Operations Manual (v12.2.0)

## Quick Start (Daily Routine)

1.  **Check Pulse:** `/ops` (Green preferred. Investigate any Red immediately.)
2.  **Input:** `/work <PREFIX>` (Ingest knowledge, stop at Policy review.)
3.  **Plan:** `/plan` (Generate tasks, stop at Architecture review.)
4.  **Build:** `/run` (Execute worker loop.)
5.  **Release:** `/ship` (Health + Drift + CI preflight -> Human sign-off.)

**Emergency Recovery**
1.  List Backups: `/snapshots`
2.  Stage Restore: `/restore <snapshot_name>.zip`
3.  **Confirm Restore:** `/restore_confirm <snapshot_name>.zip`

---

**Version:** v13.0.0 | **Last Updated:** 2025-12-09
**Role:** Operator Guide | **Scope:** Production & Maintenance

---

## 1. System Architecture (The Mental Model)
Atomic Mesh is a **Regulated Engineering System**. It prioritizes correctness over speed.
* **Source of Truth:** `docs/sources/` (Law/Book) & `docs/DOMAIN_RULES.md` (Policy).
* **State:** `control/state/tasks.json` (Current Reality).
* **Audit:** `control/state/release_ledger.jsonl` (Immutable History).
* **Safety:** `control/snapshots/` (Disaster Recovery).

### The Prime Directive
**"One Gavel Rule"**: `COMPLETE` status can *only* be set via `submit_review_decision` (The Gavel).
**WARNING:** Never manually edit `status` in JSON or DB. Doing so bypasses the audit trail and timestamps.

---

## 2. The Golden Path (Daily Workflow)

### Morning: Verification
1.  **Run `/ops`**: Check Health and Drift.
    * **Health:** Must be `OK` or `WARN`. If `FAIL`, stop and fix DB/Files. (WARN is normal during initial setup - missing ledger/registry is expected.)
    * **Drift:** If `WARN`, check stale reviews or old snapshots.
2.  **Run `/work <PREFIX>`**: Ingest/Curate new knowledge.
3.  **Run `/plan`**: Generate tasks from gaps.
4.  **Scaffold Tests** (for non-trivial tasks): Run `/scaffold-tests <TID>` to generate pytest scaffolds based on the spec.
5.  **Review Tests**: Inspect the generated TEST MATRIX in `tests/scaffold/test_<TID>.py`. If correct, proceed to implementation.

### Mid-Day: Execution
1.  **Run `/run`**: Triggers the worker loop (if external) or verify task progress.
2.  **Run `/status`**: Check for blockers or [CLARIFICATION] needed tags.

### v14.0: Pre-Review Checklist (Worker)

Before submitting work for review, verify:

- [ ] `/simplify <task-id>` was run, OR
- [ ] `OPTIMIZATION WAIVED: <reason>` is explicitly stated in review notes
- [ ] Captain has approved any waiver

**If the spec is unclear or unworkable**, use `/kickback <task-id> <reason>`:
- Returns the task to the Planner with status `blocked`
- Creates a **mandatory** audit entry in `DECISION_LOG.md`
- Signals spec quality issues for later analysis

### Evening: Release (`/ship`)
The `/ship` command is a **Fused Safety Interlock**. It runs:
1.  **Sentinel Checks:** `/health` + `/drift`. (Aborts on FAIL).
2.  **CI Gate:** `tests/run_ci.py` (Sandboxed Golden Thread).
3.  **Auto-Approve:** Clears plumbing tasks.
4.  **Docket:** Presents high-value reviews for human sign-off.


---

## 3. Incident Playbooks (When things go red)

### RED Scenario: Database Corruption / Bad State
**Symptoms:** `/health` shows DB FAIL, or data looks wrong.
**Action:**
1.  Stop the server/worker process.
2.  List backups: `/snapshots`.
3.  Restore: `/restore <snapshot_name>.zip`.
4.  Confirm: `/restore_confirm <snapshot_name>.zip`.
5.  **Restart Server** and run `/health`.

### YELLOW Scenario: Drift Warning (Stale Reviews)
**Symptoms:** `/drift` shows "Review Packets: FAIL (>72h)".
**Cause:** The Reviewer Agent isn't running, or tasks are stuck in REVIEWING without a packet.
**Action:**
1.  Check if the worker is running.
2.  Force packet regeneration (if tool available) or manually reject/approve the stuck task to clear the blockage.

---

## 4. Maintenance (Admin Only)
*Do not run these during normal operations.*

* `/snapshot <label>`: Manual backup before risky changes.
* `/migrate_timestamps`: **One-Time** v12.2 upgrade. (Locked by stamp file).
* `/sync_db`: Force-syncs SQLite status column to match JSON state.

---

## 5. File Locations
| Component | Path | Purpose |
| :--- | :--- | :--- |
| **Registry** | `docs/sources/SOURCE_REGISTRY.json` | The Constitution (Authority Tiers). |
| **Rules** | `docs/DOMAIN_RULES.md` | Human-curated policy logic. |
| **Ledger** | `control/state/release_ledger.jsonl` | The "Legal Record" of approvals. |
| **Snapshots** | `control/snapshots/` | Zip backups. |
| **Decision Packets** | `docs/templates/DECISION_PACKET.md` | Architecture proposal template. |

---

## 6. Role Contracts (Who Does What)

### Human (The Gavel)
**Symbol:** HUMAN
**Authority:** Final approval on all non-PLUMBING tasks.
**Responsibilities:**
- Review and sign off on FEATURE, REFACTOR, SECURITY, ARCHITECTURE archetypes
- Approve or reject Decision Packets
- Break ties when automated systems disagree
- Emergency restore authorization

**Boundaries:**
- MUST NOT directly edit `tasks.json` or `mesh.db`
- MUST NOT bypass the review workflow

---

### Delegator (The Architect)
**Symbol:** DELEGATOR
**Authority:** Task decomposition and assignment.
**Responsibilities:**
- Break down high-level requests into atomic tasks
- Assign archetypes and source requirements
- Route tasks to appropriate workers
- Escalate ambiguity to Human

**Boundaries:**
- MUST NOT approve own work
- MUST NOT set tasks to COMPLETE (only REVIEWING)

---

### Worker (The Builder)
**Symbol:** WORKER
**Authority:** Implementation within assigned scope.
**Responsibilities:**
- Execute tasks according to specifications
- Request clarification when blocked
- Submit work for review (status: REVIEWING)
- Maintain Single-Writer discipline

**Boundaries:**
- MUST NOT modify status outside `update_task_state()`
- MUST NOT approve own work
- MUST NOT access sources outside assigned tier

---

### Librarian (The Truth)
**Symbol:** LIBRARIAN
**Authority:** Knowledge curation and provenance.
**Responsibilities:**
- Maintain `SOURCE_REGISTRY.json` integrity
- Curate `docs/sources/` content
- Validate source citations in tasks
- Update `DOMAIN_RULES.md` with policy changes

**Boundaries:**
- MUST NOT execute implementation tasks
- MUST NOT approve without QA verification

---

### QA / Audit (The Referee)
**Symbol:** QA
**Authority:** Verification and compliance.
**Responsibilities:**
- Run CI gates (`tests/run_ci.py`)
- Verify test coverage claims
- Check governance compliance
- Validate rollback procedures

**Boundaries:**
- MUST NOT implement fixes (only report)
- MUST NOT override Human decisions

---

### Role Interaction Matrix

| Action | HUMAN | DELEGATOR | WORKER | LIBRARIAN | QA |
|--------|:-----:|:---------:|:------:|:---------:|:--:|
| Create Task | | X | | X | |
| Assign Task | | X | | | |
| Execute Task | | | X | | |
| Submit Review | | | X | X | |
| Run CI | | | | | X |
| Approve (PLUMBING) | | | | | X |
| Approve (FEATURE+) | X | | | | |
| Edit Sources | | | | X | |
| Emergency Restore | X | | | | |

---

### Compliance Note

**Static Safety Check:** Test fixtures or scripts that require literal status fields (e.g., `{"status": "REVIEWING"}`) must annotate the line with `# SAFETY-ALLOW: status-write` to pass the Static Safety Check. Treat linter failures as P0 incidents.
