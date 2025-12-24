<!-- ATOMIC_MESH_TEMPLATE_STUB -->
## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior product manager and software engineer writing a PRD. Be concise, concrete, and bias to testable bullets.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections/checklists; do not add new sections or prose before the title.
- Style: Prefer bullet lists; acceptance-criteria phrasing; avoid marketing language; cite `DECISION:`, `RISK:`, `OPEN QUESTION:` where relevant.
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
- Use measurable, acceptance-style bullets (Given/When/Then or checklist). Tables encouraged for metrics and comparisons.
- Keep statements testable and scoped; mark out-of-scope items explicitly.
- LLM Output Contract: respond with markdown only; keep headings intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a section is empty, write `TODO:` to flag what is needed.
- Prefer concrete numbers/targets; include instrumentation where possible.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`.

# Product Requirements Document: {{PROJECT_NAME}}

**Author**: {{AUTHOR}} | **Date**: {{DATE}} | **Status**: Draft

---

## One-liner
**What are we building? (value without hype)**
- [ ] {{ONE_SENTENCE_VALUE_PROPOSITION}}

## Goals
**Primary Objective (testable, acceptance style):**
- [ ] {{PRIMARY_OBJECTIVE}}

**Goals (measurable, success metric + instrumentation):**
- [ ] G1: {{GOAL}} | **Success:** {{METRIC_TARGET}} | **Measure:** {{INSTRUMENTATION}}
- [ ] G2: {{GOAL}} | **Success:** {{METRIC_TARGET}} | **Measure:** {{INSTRUMENTATION}}
- [ ] G3: {{GOAL}} | **Success:** {{METRIC_TARGET}} | **Measure:** {{INSTRUMENTATION}}

---

## Users & Context
**Primary personas (problem + motivation):**
- [ ] P1: {{PERSONA}} ({{WHY_THEY_CARE}})
- [ ] P2: {{PERSONA}} ({{WHY_THEY_CARE}})

**Usage context (where/when):**
- [ ] {{CONTEXT}}

---

## User Stories
### Must Have (MVP)
- [ ] US1: As a {{persona}}, I can {{action}} so that {{benefit}}
      **Acceptance:** {{Given/When/Then or bullet criteria}}
- [ ] US2: As a {{persona}}, I can {{action}} so that {{benefit}}
      **Acceptance:** {{criteria}}
- [ ] US3: As a {{persona}}, I can {{action}} so that {{benefit}}
      **Acceptance:** {{criteria}}

### Should Have (vNext)
- [ ] US4: As a {{persona}}, I can {{action}} so that {{benefit}}
- [ ] US5: As a {{persona}}, I can {{action}} so that {{benefit}}

### Nice to Have (Future)
- [ ] US6: As a {{persona}}, I can {{action}} so that {{benefit}}

---

## UX / Workflow
**Happy path (5–8 steps):**
1. [ ] {{step}}
2. [ ] {{step}}
3. [ ] {{step}}

**Edge cases (cover failure and recovery):**
- [ ] EC1: {{edge_case}} → expected behavior: {{expected}}
- [ ] EC2: {{edge_case}} → expected behavior: {{expected}}

---

## Success Metrics
**How will we know this is working?**
- [ ] Metric: {{name}} | Baseline: {{x}} | Target: {{y}} | Instrumentation: {{where}}
- [ ] Metric: {{name}} | Baseline: {{x}} | Target: {{y}} | Instrumentation: {{where}}

---

## Experiments (if applicable)
- [ ] Hypothesis: {{If we do X, metric Y improves for segment Z}}
- [ ] Primary metric: {{metric}} | Guardrails: {{metric list}} | MDE/sample target: {{value or TODO}}
- [ ] Assignment: {{random/feature flag logic}} | Variant IDs: {{A/B/C}}
- [ ] Exposure logging: {{event name, fields, location in code}}
- [ ] Stop rules: {{p-value/CI threshold or duration cap}} | Rollback: {{plan}}
- [ ] Validation: AA test or dry-run planned? {{yes/no}} | Instrumentation check: {{query or dashboard}}

---

## Constraints
**Hard constraints (non-negotiable):**
- [ ] Platform: {{windows/linux/mac/web}}
- [ ] Performance: {{latency/throughput limits}}
- [ ] Security/Privacy: {{auth, data handling, PII}}
- [ ] Compatibility: {{browsers/versions/apis}}

---

## Scope (MVP)
- [ ] In scope: {{deliverable}} | Why now: {{reason}}
- [ ] In scope: {{deliverable}} | Why now: {{reason}}

---

## Out of Scope (MVP)
> Explicitly excluded to prevent scope creep
- [ ] {{not_building}}
- [ ] {{not_building}}
- [ ] {{not_building}}

---

## Open Questions (Blockers)
> If any of these are non-empty, Planner should ask or create NEEDS_SPEC tasks
- [ ] OPEN QUESTION: {{question}}
- [ ] OPEN QUESTION: {{question}}
- [ ] OPEN QUESTION: {{question}}

---

## Risks
- [ ] RISK: {{risk}} | Mitigation: {{mitigation}}
- [ ] RISK: {{risk}} | Mitigation: {{mitigation}}

---

## Rollout & Launch
- [ ] Rollout plan: {{phased/full}} | Audience: {{beta/ga}} | Owner: {{name}}
- [ ] Monitoring/alerting ready: {{yes/no}} | DR/rollback: {{plan}}
- [ ] Comms: {{channels}} | Support playbook: {{link or TODO}}

---

## Milestones
- [ ] M0 (MVP): {{what ships}} | Deadline: {{date or "none"}} | Acceptance: {{criteria}}
- [ ] M1 (Next): {{what ships}} | Deadline: {{date or "none"}} | Acceptance: {{criteria}}

---

*Template version: 16.0 (prompt-ready PRD)*
