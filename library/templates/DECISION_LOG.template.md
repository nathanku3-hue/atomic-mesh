# Decision Log: {{PROJECT_NAME}}

> This document captures all major technical and product decisions.
> The Router automatically appends here. Never delete entries.

---

## How to Use

1. **Router/Commander** appends decisions automatically via `append_decision()` MCP tool
2. **Workers** can reference past decisions to avoid re-litigation
3. **Auditor** uses this to verify consistency

---

## Decision Format

| ID | Date | Decision | Context | Status |
|----|------|----------|---------|--------|
| *Auto* | *YYYY-MM-DD* | *What was decided* | *Why it was decided* | ✅/🔄/❌ |

**Status Legend:**
- ✅ Active - Decision is in effect
- 🔄 Superseded - Replaced by newer decision
- ❌ Reverted - Decision was rolled back

---

## Decisions

| ID | Date | Decision | Context | Status |
|----|------|----------|---------|--------|
| 001 | {{DATE}} | Project initialized | Bootstrap via Atomic Mesh v7.7 | ✅ |

<!-- New decisions are appended below this line -->
