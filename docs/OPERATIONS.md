# Atomic Mesh Operations Manual (v12.2.0)

## Quick Start (Daily Routine)

1.  **Check Pulse:** `/ops` (Green preferred. Investigate any Red immediately.)
2.  **Input:** `/work <PREFIX>` (Ingest knowledge, stop at Policy review.)
3.  **Plan:** `/plan` (Generate tasks, stop at Architecture review.)
4.  **Build:** `/run` (Execute worker loop.)
5.  **Release:** `/ship` (Health + Drift + CI preflight -> Human sign-off.)

**Auto-Flight Note (v15.0):**
After `/refresh-plan`, `docs/ACTIVE_SPEC.md` is automatically regenerated from `PRD.md` + `SPEC.md`.
Workers follow ACTIVE_SPEC first (execution snapshot). Planners follow SPEC first (governance).

**INBOX (v15.1):**
`docs/INBOX.md` is an ephemeral scratchpad for capturing clarifications and notes on-the-fly.
- **Usage**: Write notes directly in INBOX.md → run `/ingest` → notes are merged and INBOX is cleared.
- **Dashboard**: Shows `INBOX: ✓ empty` or `INBOX: ✎ pending (N)` indicator.
- **Warning**: INBOX does NOT affect the readiness gate. It's a scratchpad only, not a golden doc.

**Auto-Ingest (v15.2):**
Auto-ingest watches for doc saves and runs `/ingest` automatically (debounced).
- **Trigger**: On next terminal interaction after a doc save (v1 behavior).
- **Watched files**: `PRD.md`, `SPEC.md`, `DECISION_LOG.md`, `ACTIVE_SPEC.md`, `INBOX.md`
- **Dashboard**: Shows `Auto-ingest: armed | pending | OK (time) | ERROR`
- **Disable**: Set environment variable `MESH_AUTO_INGEST=0` before running the panel.

**Emergency Recovery**
1.  List Backups: `/snapshots`
2.  Stage Restore: `/restore <snapshot_name>.zip`
3.  **Confirm Restore:** `/restore_confirm <snapshot_name>.zip`

---

**Version:** v14.1.0 | **Last Updated:** 2025-12-13
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

### v14.1: Pre-Review Checklist (Captain/Reviewer)

Before approving MEDIUM/HIGH risk tasks, verify:

- [ ] **DONE-DONE PACKET** present in task/review notes
- [ ] **Verify score** meets threshold:
  - MEDIUM risk: ≥ 90/100, OR `CAPTAIN_OVERRIDE: CONFIDENCE` present
  - HIGH risk: ≥ 95/100, OR `CAPTAIN_OVERRIDE: CONFIDENCE` present
- [ ] **Entropy proof** present (`Entropy Check: Passed`) OR waiver documented
- [ ] **Tests** named and PASS

**Note:** LOW risk tasks require only Tests + Entropy. Confidence verification is optional.

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

---

## Librarian v15.0: Snippet Search & Duplicate Detection

**Purpose**: Clipboard manager for common code patterns. Advisory only - no auto-insert.

### Usage

**Search snippets by keyword or tag:**
```python
# Via MCP tool (if using programmatically)
snippet_search(query="retry", lang="python")
snippet_search(query="", tags="http,resilience", lang="any")
```

**Check for duplicates before writing new helpers:**
```python
# Via MCP tool (if using programmatically)
snippet_duplicate_check(file_path="src/new_helper.py", lang="auto")
```

**Important**: Both tools are **advisory only**. They never:
- Block builds or CI
- Auto-insert code
- Modify files

Warnings from `snippet_duplicate_check` suggest you may want to reuse an existing snippet from `library/snippets/` instead of writing a new one.

**Snippet location**: `library/snippets/{python,powershell,markdown}/`

**Decision**: See `docs/DECISIONS/ENG-LIBRARIAN-SNIPPETS-001.md`
