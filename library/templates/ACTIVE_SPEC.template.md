<!-- ATOMIC_MESH_TEMPLATE_STUB -->
## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior software engineer executing the current batch. Be concise, concrete, and test-first.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections/checklists; do not add new sections or prose before the title.
- Style: Bullet-first; ensure current plan, tasks, risks, and definition of done are explicit; tag `DECISION:`, `RISK:`, `OPEN QUESTION:` where relevant.
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
- Keep tasks actionable and testable; tie them to objectives. Include next steps and owners/dates when possible.
- LLM Output Contract: respond with markdown only; keep headings intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a section is empty, write `TODO:` to flag what is needed.
- Prefer concrete acceptance checks; note any blockers explicitly.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`.

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

## Plan & Tasks
- Current plan summary: {{1-2 bullets}}
- Tasks (ordered, testable):
  - [ ] {{task}} — Owner: {{name}} | Due: {{date}} | Acceptance: {{criteria}}
  - [ ] {{task}} — Owner: {{name}} | Due: {{date}} | Acceptance: {{criteria}}
- Next step after completion: {{handoff/launch/QA}}

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
6. ✅ (If experimenting) Exposure logging + primary/guardrail metrics wired, validated (AA or smoke), and dashboard link recorded

---

## Current Risks & Mitigations
- [ ] RISK: {{risk}} | Mitigation: {{mitigation}} | Owner: {{name}}
- [ ] RISK: {{risk}} | Mitigation: {{mitigation}} | Owner: {{name}}

---

## Experiments (live or planned)
| ID | Hypothesis | Variant keys | Primary metric | Guardrails | Owner | Start/End | Status |
|----|------------|--------------|----------------|------------|-------|-----------|--------|
| EXP-001 | {{If we do X, Y improves}} | {{A/B}} | {{metric}} | {{metrics}} | {{name}} | {{dates}} | {{Planned/Running/Complete}} |

---

## Provenance
- Source: docs/PRD.md
- Source: docs/SPEC.md (or docs/ACTIVE_SPEC.md if SPEC missing)
- Source: docs/DECISION_LOG.md (optional)
- Hydration: deterministic (regex/structure), no LLM required

*Template version: 16.0*
