# Tech Stack: {{PROJECT_NAME}}
<!-- ATOMIC_MESH_TEMPLATE_STUB -->

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

| Component | Choice | Version | Notes |
|-----------|--------|---------|-------|
| Language | Python | 3.11+ | Type hints required |
| Framework | FastAPI | 0.100+ | Async preferred |
| Database | PostgreSQL | 15+ | SQLite for dev |
| ORM | SQLAlchemy | 2.0+ | Async sessions |
| Migrations | Alembic | Latest | Auto-generate |

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

| Component | Choice | Version | Notes |
|-----------|--------|---------|-------|
| Framework | Next.js | 14+ | App Router |
| Language | TypeScript | 5.x | Strict mode |
| Styling | Tailwind CSS | 3.x | No CSS-in-JS |
| State | Zustand | Latest | For global state |
| Data Fetching | React Query | v5 | For server state |

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

| Component | Choice | Notes |
|-----------|--------|-------|
| Hosting | Vercel / Railway | |
| Database | Supabase / Railway | Managed Postgres |
| CI/CD | GitHub Actions | |
| Secrets | Environment Variables | Never commit! |

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
