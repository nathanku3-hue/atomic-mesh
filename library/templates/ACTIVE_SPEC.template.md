<!-- ATOMIC_MESH_TEMPLATE_STUB -->
# ACTIVE SPECIFICATION: {{PROJECT_NAME}}

> **Purpose:** Execution snapshot for the current batch.
> **Derived from:** PRD.md + SPEC.md (+ Decision Log if present).
> **Rule:** Workers follow ACTIVE_SPEC first. Planners follow SPEC first.
> **Updated:** {{DATE}}

---

## Current Batch Focus
- Mode: DELIVERY | HARDENING | REFACTOR
- Priority order: correctness > speed > elegance
- Non-negotiables:
  - Tests required (scaffold-first where applicable)
  - No silent scope creep (update PRD/SPEC + log decision)
  - Keep CLI stable (no breaking commands without explicit decision)

---

## Core Objective
<!-- One sentence that describes product value in plain language -->
- Objective: {{CORE_OBJECTIVE}}

---

## In Scope
### Goals (from PRD)
<!-- Hydrated list -->
- [ ] {{GOAL_1}}
- [ ] {{GOAL_2}}

### User Stories (from PRD)
<!-- Hydrated list -->
- [ ] {{STORY_1}}
- [ ] {{STORY_2}}

---

## Non-Functional Requirements
<!-- Hydrated summary from PRD/SPEC -->
| Requirement | Target | Notes |
|---|---:|---|
| Response Time | {{P95_LATENCY}} | P95 |
| Uptime | {{UPTIME}} | Production |
| Test Coverage | {{COVERAGE}} | Unit + Integration |

---

## Technical Constraints (from SPEC)
- Database: {{DB}}
- Auth: {{AUTH}}
- API Style: {{API_STYLE}}
- Deployment/Runtime: {{RUNTIME}}

---

## Interfaces (from SPEC)
### API Endpoints (if provided)
- {{ENDPOINT_1}}
- {{ENDPOINT_2}}

### Data Model (if provided)
- Entities:
  - {{ENTITY_1}}
  - {{ENTITY_2}}
- Relationships:
  - {{REL_1}}

---

## Out of Scope (from PRD)
- {{OUT_1}}
- {{OUT_2}}

---

## Acceptance Criteria (Execution Gate)
A task is "reviewable" when:
1. ✅ Tests exist + pass
2. ✅ Spec alignment checked (ACTIVE_SPEC)
3. ✅ `/simplify <task-id>` run OR waiver logged
4. ✅ No critical security issues introduced
5. ✅ Changes respect TECH_STACK / constraints

---

## Provenance
- Source: docs/PRD.md
- Source: docs/SPEC.md (or docs/ACTIVE_SPEC.md if SPEC missing)
- Source: docs/DECISION_LOG.md (optional)
- Hydration: deterministic (regex/structure), no LLM required

*Template version: 15.0*
