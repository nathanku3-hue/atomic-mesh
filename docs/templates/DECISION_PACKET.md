# Decision Packet: [TITLE]

**Packet ID:** DP-[YYYYMMDD]-[SEQ]
**Created:** [DATE]
**Status:** DRAFT | UNDER_REVIEW | APPROVED | REJECTED
**Author:** [Role/Agent]

---

## 1. Context

| Field | Value |
|-------|-------|
| **Trigger** | [What prompted this decision? Task ID, incident, feature request] |
| **Archetype Impact** | PLUMBING / FEATURE / REFACTOR / SECURITY / ARCHITECTURE |
| **Blast Radius** | LOW (1-2 files) / MEDIUM (1 module) / HIGH (cross-cutting) |
| **Sources Consulted** | [List SOURCE_REGISTRY IDs, e.g., STD-ENG-01, RFC-AUTH-03] |

### Problem Statement
[1-3 sentences describing the problem to be solved]

---

## 2. Options Analysis

### Option A: [Name]
| Aspect | Details |
|--------|---------|
| **Approach** | [Brief description] |
| **Pros** | [List benefits] |
| **Cons** | [List drawbacks] |
| **Risk** | LOW / MEDIUM / HIGH - [explanation] |
| **Cost** | [Complexity: trivial/moderate/significant] |

### Option B: [Name]
| Aspect | Details |
|--------|---------|
| **Approach** | [Brief description] |
| **Pros** | [List benefits] |
| **Cons** | [List drawbacks] |
| **Risk** | LOW / MEDIUM / HIGH - [explanation] |
| **Cost** | [Complexity: trivial/moderate/significant] |

### Option C: [Name] (if applicable)
| Aspect | Details |
|--------|---------|
| **Approach** | [Brief description] |
| **Pros** | [List benefits] |
| **Cons** | [List drawbacks] |
| **Risk** | LOW / MEDIUM / HIGH - [explanation] |
| **Cost** | [Complexity: trivial/moderate/significant] |

---

## 3. Recommendation

**Selected Option:** [A/B/C]

**Justification:**
[Why this option was chosen over alternatives. Reference sources if applicable.]

---

## 4. Test Plan

| Layer | Test | Coverage |
|-------|------|----------|
| **Unit** | [ ] [Specific unit tests to add/modify] | |
| **Integration** | [ ] [Integration scenarios to verify] | |
| **E2E** | [ ] [End-to-end workflows to validate] | |
| **Static Safety** | [ ] Passes `tests/static_safety_check.py` | |
| **Sentinel Validation** | [ ] `/health` returns OK/WARN | |
| | [ ] `/drift` returns OK/WARN | |

---

## 5. Rollback Plan

**Trigger Conditions:** [When would we roll back?]

**Rollback Steps:**
1. [ ] [Step 1]
2. [ ] [Step 2]
3. [ ] Run `/restore <snapshot>` if state corrupted

**Recovery Verification:**
- [ ] `/health` returns OK
- [ ] CI passes (`tests/run_ci.py`)

---

## 6. Governance Checklist

### Policy Alignment
- [ ] Reviewed `docs/DOMAIN_RULES.md` for relevant constraints
- [ ] Sources listed in `docs/sources/SOURCE_REGISTRY.json`
- [ ] No tier violations (e.g., referencing unregistered sources)

### Architecture Review (if Blast Radius = HIGH)
- [ ] **ARCH:** Structural changes reviewed
- [ ] **SEC:** Security implications assessed
- [ ] **DB:** Schema changes documented
- [ ] **API:** Contract changes versioned

### Single-Writer Discipline
- [ ] All status mutations use `update_task_state()`
- [ ] No direct `["status"] =` assignments outside emitter
- [ ] No raw `UPDATE tasks SET status` SQL

---

## 7. Sign-Off

| Role | Name/ID | Decision | Date |
|------|---------|----------|------|
| **Librarian** | | APPROVE / REJECT / ABSTAIN | |
| **QA / Audit** | | APPROVE / REJECT / ABSTAIN | |
| **Human Gavel** | | APPROVE / REJECT | |

### Notes
[Any conditions, caveats, or follow-up actions required]

---

*Template Version: 13.0.0*
