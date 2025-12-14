<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# Decision Log: {{PROJECT_NAME}}

**Owner**: {{AUTHOR}} | **Date**: {{DATE}} | **Status**: Active
**Rule:** This file is append-only. Never delete rows. Supersede instead.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | {{DATE}} | INIT | Project initialized | Bootstrap via /init | repo | — | ✅ |

<!-- ATOMIC_MESH_APPEND_DECISIONS_BELOW -->

---

**Status Legend:** ✅ Active | 🔄 Superseded | ❌ Reverted
**Type Examples:** INIT, SCOPE, ARCH, API, DATA, SECURITY, UX, PERF, OPS, TEST, RELEASE

## Notes (Optional, Human)
- Prefer short rationale in the table. If long, add a link to a decision packet in `docs/DECISIONS/`.
- When superseding: add a new row with `Type=...` and set the old row to 🔄 (do not delete).
