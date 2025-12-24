<!-- ATOMIC_MESH_TEMPLATE_STUB -->

## LLM Prompt (copy/paste into ChatGPT)
- Role: You are a senior software engineer maintaining the tech stack contract. Be terse, concrete, and justify choices with constraints.
- Input: Use only info in this chat/session and the Context Pack. If data is missing, add `TODO: <question>` and add `ASSUMPTION: <item>` if you must proceed.
- Output: Return markdown only; preserve all headings/sections/tables; do not add new sections or prose before the title.
- Style: Bullet/table-first; list choices with rationale, constraints, tooling, CI, and observability; tag `DECISION:`, `RISK:`, `OPEN QUESTION:` explicitly.
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
- For every tool choice, include rationale + constraints (versions, licensing, support). Note CI, tooling, and observability defaults.
- Use tables for stacks and policies. Keep statements testable and enforceable.
- LLM Output Contract: respond with markdown only; keep headings intact; no additional sections.

### Template Quick Rules (shared)
- Keep bullets short; no fluff.
- If a field is unknown, enter `TODO:` instead of leaving blank.
- Prefer concrete versions and guardrails; note forbidden/approval rules clearly.
- Use consistent tokens: `TODO:`, `ASSUMPTION:`, `DECISION:`, `RISK:`, `OPEN QUESTION:`.

# Tech Stack: {{PROJECT_NAME}}

> This document is the **contract** for what tools/libraries Workers can use.
> If it's not listed here, Workers should ASK before importing.

---

## Auto-Flight Contract (Machine Hints)

- Stack ID: STACK_WEB_FASTAPI_NEXT
- Primary Backend: Python + FastAPI
- Primary Frontend: Next.js + TypeScript
- Default Test Tools: pytest, Playwright
- Default Lint/Format: Ruff/Black, ESLint/Prettier

### Codegen Targets (where files go)
- Backend root: backend/
- Backend app entry: backend/app/main.py
- Backend tests: backend/tests/
- Frontend root: frontend/
- Frontend app: frontend/app/
- Frontend tests: frontend/tests/
- E2E tests: e2e/

### Dependency Policy (Enforcement)
- If a dependency is **not listed** as Approved, Worker must:
  1) Ask (preferred), or
  2) Use `CAPTAIN_OVERRIDE: STACK` in the review notes with justification.

---

## Backend

| Component | Choice | Version | Rationale / Constraints |
|-----------|--------|---------|-------------------------|
| Language | Python | 3.11+ | Type hints required |
| Framework | FastAPI | 0.100+ | Async preferred |
| Database | PostgreSQL | 15+ | SQLite for dev |
| ORM | SQLAlchemy | 2.0+ | Async sessions |
| Migrations | Alembic | Latest | Auto-generate |
| Experiment SDK | {{flag SDK e.g., LaunchDarkly}} | {{version}} | Required for variant assignment + exposure logging |

### Python Dependencies (Approved)
```
fastapi
uvicorn[standard]
sqlalchemy[asyncio]
pydantic
python-jose[cryptography]
passlib[bcrypt]
httpx
pytest
pytest-asyncio
```

---

## Frontend

| Component | Choice | Version | Rationale / Constraints |
|-----------|--------|---------|-------------------------|
| Framework | Next.js | 14+ | App Router |
| Language | TypeScript | 5.x | Strict mode |
| Styling | Tailwind CSS | 3.x | No CSS-in-JS |
| State | Zustand | Latest | For global state |
| Data Fetching | React Query | v5 | For server state |
| Experiment exposure hook | {{client SDK hook}} | {{version}} | Must log exposure before rendering variant UX |

### NPM Dependencies (Approved)
```
next
react
typescript
tailwindcss
@tanstack/react-query
zustand
zod
```

---

## Testing

| Type | Tool | Coverage Target |
|------|------|-----------------|
| Unit | Pytest / Vitest | 80% |
| Integration | Pytest / Vitest | Key flows |
| E2E | Playwright | Critical paths |

---

## Linting & Formatting

| Language | Linter | Formatter |
|----------|--------|-----------|
| Python | Ruff | Black |
| TypeScript | ESLint | Prettier |

---

## Infrastructure

| Component | Choice | Constraints / Notes |
|-----------|--------|---------------------|
| Hosting | Vercel / Railway | |
| Database | Supabase / Railway | Managed Postgres |
| CI/CD | GitHub Actions | Required checks defined below |
| Secrets | Environment Variables | Never commit! |

---

## CI/CD, Tooling, Observability

| Area | Standard | Constraints / Notes |
|------|----------|---------------------|
| CI Pipelines | Build + lint + test on PR | Block merge if failures |
| Security | SAST/dep scan {{tool or TODO}} | Gate releases; track CVEs |
| Code Quality | Pre-commit hooks (ruff/black/eslint/prettier) | Enforced locally + CI |
| Observability | Metrics + logs + traces | {{stack e.g., OpenTelemetry}}; dashboards required before GA |
| Alerts | {{tool}} | Thresholds defined in SPEC/ACTIVE_SPEC |
| Experimentation | {{flag/assignment service}} | Exposure logging + guardrails required; sampling rules documented; AA test capability; pre-launch experiment check in CI |

---

## FORBIDDEN Libraries ❌

> Workers MUST NOT use these without explicit approval:

| Library | Reason | Alternative |
|---------|--------|-------------|
| jQuery | Legacy, bloat | Native JS |
| Moment.js | Deprecated, large | date-fns |
| Lodash (full) | Tree-shaking issues | lodash-es or native |
| Any ORM not listed | Consistency | Use SQLAlchemy/Prisma |
| axios | httpx is standard | httpx (Python) / fetch (JS) |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | {{DATE}} | {{AUTHOR}} | Initial stack definition |
