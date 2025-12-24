<!-- ATOMIC_MESH_TEMPLATE_STUB -->
## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior product/engineering lead logging decisions. Be terse, factual, and bias to testable statements.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections/table columns; do not add new sections or prose before the title.
- Style: Bullet/table-first; capture context, options, decision, constraints, and rollback; tag `DECISION:`, `RISK:`, `OPEN QUESTION:` explicitly.
- Quick start: Copy from here to the end of the file into ChatGPT. Optionally paste recent notes into the Context Pack → Extra context.

### Context Pack
- Project: {{PROJECT_NAME}}
- Repo path: {{REPO_PATH}}
- Stage: INIT | DRAFT | ACCEPT | GO
- Constraints / non-negotiables: TODO:
- Snapshot signals / readiness: TODO:
- Extra context from user or links: TODO:

### Fill Rules (shared)
- Missing info → `TODO: <question>`; assumptions → `ASSUMPTION: <item>`; risks → `RISK: <item>`; decisions → `DECISION: <item>`; unknowns → `OPEN QUESTION: <item>`.
- Each record must include context, the options considered, the decision, constraints, and rollback/contingency.
- Use concise, testable phrases; if details are long, link to a packet. Preserve table formatting.
- LLM Output Contract: respond with markdown only; keep headings and table intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a field is unknown, enter `TODO:` instead of leaving blank.
- Prefer concrete numbers/owners/dates when available.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`.

# Decision Log: {{PROJECT_NAME}}

**Owner**: {{AUTHOR}} | **Date**: {{DATE}} | **Status**: Active  
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Context | Options Considered | Decision | Constraints | Rollback/Contingency | Scope | Owner | Status |
|----|------|---------|--------------------|----------|-------------|----------------------|-------|-------|--------|
| 001 | {{DATE}} | INIT (project bootstrap) | Keep repo empty; scaffold baseline | DECISION: Bootstrap via /init | Approved stack only | Roll back to clean repo snapshot | repo | {{AUTHOR}} | ✅ |
| SAMPLE-ARCH | {{DATE}} | Choose API style | REST; GraphQL; RPC | DECISION: REST + JSON (openapi-first) | Latency SLA; client compatibility | If fail: revert to existing API; maintain versioned endpoints | api | {{OWNER}} | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted  
**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE  
**Rollback guidance:** Always include how to unwind or mitigate if decision fails.

## Notes (Optional, Human)
- Prefer short rationale in the table. If long, add a link to a decision packet in `docs/DECISIONS/`.
- When superseding: add a new row with the new decision and set the old row to 🔄 (do not delete).
