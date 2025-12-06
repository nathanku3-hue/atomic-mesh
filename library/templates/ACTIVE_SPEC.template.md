# ACTIVE SPECIFICATION: {{PROJECT_NAME}}

## Core Objective
<!-- One sentence describing the product value proposition -->
> Example: "Enable users to track investment opportunities with AI-powered insights."

---

## User Stories (Scope)

### MVP (v1.0)
- [ ] As a **user**, I can sign up/login via email
- [ ] As a **user**, I can view my dashboard
- [ ] As an **admin**, I can manage users

### Future (v2.0+)
- [ ] As a user, I can export data
- [ ] As a user, I can integrate with third-party services

---

## Non-Functional Requirements (Constraints)

| Requirement | Target | Notes |
|-------------|--------|-------|
| Response Time | < 200ms | P95 latency |
| Uptime | 99.9% | Production |
| Test Coverage | > 80% | Unit + Integration |

---

## Technical Constraints

- **Database:** {{DB_TYPE}} (e.g., PostgreSQL, SQLite)
- **Auth:** JWT-based, stateless
- **API Style:** REST with OpenAPI spec

---

## Out of Scope (v1.0)

> Explicitly list what we are NOT building to prevent scope creep.

- Mobile app (web-first)
- Real-time websockets (polling acceptable)
- Multi-tenancy

---

## Acceptance Criteria

A feature is "Done" when:

1. ✅ User story checkbox is checked
2. ✅ Unit tests written and passing
3. ✅ Code reviewed (Auditor approved)
4. ✅ No critical security issues
5. ✅ Matches TECH_STACK.md constraints

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | {{DATE}} | {{AUTHOR}} | Initial draft |
