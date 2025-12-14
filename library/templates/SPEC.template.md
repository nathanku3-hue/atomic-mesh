<!-- ATOMIC_MESH_TEMPLATE_STUB -->
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

## Data Model

**Core Entities**:
- [ ] Entity 1: [Name, purpose, key fields]
- [ ] Entity 2: [Name, purpose, key fields]
- [ ] Entity 3: [Name, purpose, key fields]

**Relationships**:
- [ ] Entity1 → Entity2: [1:N, N:M, etc.]
- [ ] Entity2 → Entity3: [1:N, N:M, etc.]

---

## API

**Endpoints**:
- [ ] `GET /endpoint` - [Description]
- [ ] `POST /endpoint` - [Description]
- [ ] `PUT /endpoint` - [Description]
- [ ] `DELETE /endpoint` - [Description]

**Authentication**:
- [ ] Method: [JWT, OAuth2, API Key, etc.]
- [ ] Token storage: [localStorage, httpOnly cookie, etc.]

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

---

## Dependencies

**External Services**:
- [ ] Service 1: [Purpose, SLA requirements]
- [ ] Service 2: [Purpose, SLA requirements]

**Third-Party Libraries**:
- [ ] Library 1: [Purpose, version constraints]
- [ ] Library 2: [Purpose, version constraints]

---

## Change Policy (to prevent SPEC drift)
- Changes here require a Decision Log entry (DECISION_LOG.md).
- Prefer adding constraints over rewriting sections.
- Keep this file stable across sprints; put "today's focus" in ACTIVE_SPEC.

*Template version: 15.0*
