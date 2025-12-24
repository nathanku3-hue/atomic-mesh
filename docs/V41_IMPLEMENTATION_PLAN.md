# V4.1 Implementation Plan - Top 3 Refinements & Tier 2 MCP

**Status:** 📅 PLANNED

---

## 🚀 Tier 1: High-ROI Refinements (Immediate)

### 1. Worker Pre-Flight Context (SOP)
*   **Goal:** Prevent starting work in broken environments.
*   **Action:** Update `worker.md` with explicit checks.
*   **Detail:** "Check dependencies completed? Check Task ID exists?"

### 2. Safety/Health Check (SOP)
*   **Goal:** Escalate security risks immediately.
*   **Action:** Update `architect_sop.md`.
*   **Detail:** If `get_relevant_lessons` returns security warnings -> Mark task HIGH PRIORITY.

### 3. Log Fallback to Lessons (Code)
*   **Goal:** Detect "Skill Drift" (missing lane rules).
*   **Action:** Update `vibe_controller.py`.
*   **Detail:** If fallback to `_default.md` occurs, append warning to `LESSONS_LEARNED.md`.

---

## 🔌 Tier 2: MCP Integrations (Next Sprint)

### 4. SQLite MCP Inspector
*   **Goal:** Safe database introspection.
*   **Action:** Create `vibe_mcp/sqlite_server.py`.
*   **Tools:** `query_tasks(status)`, `get_table_schema()`.

### 5. Task-Level Constraints
*   **Goal:** Per-task overrides.
*   **Action:** Update compiler logic.
*   **Detail:** Allow Architect to inject custom constraints via JSON flag.

---

## Verification Plan
- [ ] Check `worker.md` has Pre-Flight section.
- [ ] Check `architect_sop.md` has Health Check.
- [ ] Verify fallback logging in `vibe_controller.py` via smoke test.
