<!-- ATOMIC_MESH_TEMPLATE_STUB -->
## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior software engineer/architect writing a technical specification. Be terse, concrete, and bias to testable bullets.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections; do not add new sections or prose before the title.
- Style: Bullet-first; include rationale where helpful; avoid marketing; tag `DECISION:`, `RISK:`, `OPEN QUESTION:` explicitly.
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
- Use measurable, acceptance-style bullets (Given/When/Then or checklist). Prefer tables for APIs, dependencies, and budgets.
- Capture architecture, interfaces, data, error handling, performance, security, and testing. Keep statements testable and scoped.
- LLM Output Contract: respond with markdown only; keep headings intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a section is empty, write `TODO:` to flag what is needed.
- Prefer concrete numbers/targets; include instrumentation/limits where possible.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`.

# Technical Specification: {{PROJECT_NAME}}

**Author**: Atomic Mesh | **Date**: {{DATE}} | **Status**: Draft

> **Role:** This file is the *technical constitution* (slow-changing).
> **Used by:** Planner + QA + governance gates.
> **Not used for:** daily task focus (that belongs in ACTIVE_SPEC.md).
> **Rule:** If ACTIVE_SPEC conflicts with SPEC, SPEC wins and the plan must be corrected.

---

## Hydration Contract (for ACTIVE_SPEC)
> Keep this section short and explicit so the system can "hydrate" the cockpit snapshot.

- Database: [Postgres | SQLite | etc.]
- Auth: [JWT | session | OAuth2 | etc.]
- API Style: [REST | GraphQL | RPC]
- Runtime/Deploy: [docker | serverless | bare metal | etc.]
- Conventions:
  - Error format: [e.g., RFC7807/problem+json]
  - Logging: [structured | plain]
  - Testing: [pytest | unittest | etc.]

---

## Architecture & Responsibilities
- [ ] System overview: {{1-3 bullet summary of architecture}}
- [ ] Components: {{component}} → {{primary responsibilities, lifecycle, ownership}}
- [ ] Data flows: {{origin → processing → sink}}
- [ ] Deployment topology: {{environments, scaling model, redundancy}}

---

## Interfaces
### API (external + internal)
- [ ] `GET /endpoint` — {{purpose, auth, idempotency}}
- [ ] `POST /endpoint` — {{purpose, auth, idempotency}}
- [ ] `PUT /endpoint` — {{purpose, auth, idempotency}}
- [ ] `DELETE /endpoint` — {{purpose, auth, idempotency}}

### Integrations / Messaging
- [ ] Publisher/Consumer: {{topic/queue}} — {{payload schema, ordering, retry policy}}
- [ ] Webhooks/Callbacks: {{event name}} — {{signature/verification}}
- [ ] Experiment assignment/flag service: {{service/lib}} — {{bucketing rules, exposure logging}}

---

## Data Model

**Core Entities** (include invariants + indexes):
- [ ] Entity 1: [Name, purpose, key fields, primary keys]
- [ ] Entity 2: [Name, purpose, key fields, primary keys]
- [ ] Entity 3: [Name, purpose, key fields, primary keys]

**Relationships**:
- [ ] Entity1 → Entity2: [1:N, N:M, etc.; ownership/cascade rules]
- [ ] Entity2 → Entity3: [1:N, N:M, etc.; ownership/cascade rules]
- [ ] Experiment events: [event name, required fields: user/session, variant, timestamp, exposure context]
- [ ] Feature flags: [flag keys, default, variants, owner, expiry]

---

## Error Handling & Observability
- [ ] Error contract: {{format, codes, retryable vs fatal}}
- [ ] Validation strategy: {{where validated, strictness}}
- [ ] Logging/Metrics/Tracing: {{what is logged, key metrics, trace coverage}}
- [ ] Alerting: {{thresholds, runbooks}}
- [ ] Experiment telemetry: {{exposure event schema, success metric events, sampling rules}}

---

## Performance & Capacity
- [ ] Throughput/latency budgets: {{targets (P95/P99), load assumptions}}
- [ ] Scaling plan: {{vertical/horizontal, autoscaling signals}}
- [ ] Capacity constraints: {{limits, quotas, backpressure strategy}}

---

## Security

**Threat Model**:
- [ ] Threat 1: [Description + mitigation]
- [ ] Threat 2: [Description + mitigation]
- [ ] Threat 3: [Description + mitigation]

**Controls**:
- [ ] Input validation: [Where, how]
- [ ] SQL injection prevention: [Parameterized queries, ORM]
- [ ] XSS prevention: [Escaping, CSP headers]
- [ ] CSRF protection: [Tokens, SameSite cookies]
- [ ] Secrets/keys: [Storage, rotation, access]

---

## Dependencies

**External Services**:
- [ ] Service 1: [Purpose, SLA requirements, failure plan]
- [ ] Service 2: [Purpose, SLA requirements, failure plan]

**Third-Party Libraries**:
- [ ] Library 1: [Purpose, version constraints, why approved]
- [ ] Library 2: [Purpose, version constraints, why approved]

---

## Testing & Quality
- [ ] Test strategy: {{unit/integration/e2e breakdown}}
- [ ] Test data: {{fixtures, seeding, anonymization}}
- [ ] Non-functional tests: {{perf, load, security scanning}}
- [ ] Exit criteria: {{definition of done for this spec}}
- [ ] Experiment validation: {{exposure event tests, bucketing tests, metric sanity (AA), alert thresholds}}

---

## Change Policy (to prevent SPEC drift)
- Changes here require a Decision Log entry (DECISION_LOG.md).
- Prefer adding constraints over rewriting sections.
- Keep this file stable across sprints; put "today's focus" in ACTIVE_SPEC.

*Template version: 16.0*
