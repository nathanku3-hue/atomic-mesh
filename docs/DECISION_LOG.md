# Decision Log

**Project**: Atomic Mesh Control Panel | **Started**: 2025-12-01

---

## Purpose
This log records architectural and engineering decisions for the Atomic Mesh Control Panel project. Each decision includes context, rationale, and scope impact.

---

## Records

| ID | Date | Type | Decision | Rationale | Scope | Task | Status |
|----|------|------|----------|-----------|-------|------|--------|
| 001 | 2025-12-01 | INIT | Project initialized with TUI-first approach | Terminal workflows are primary use case for target users | ARCH | - | ACCEPTED |
| 002 | 2025-12-13 | ARCH | Pipeline status model with 6 stages | Context/Plan/Work/Optimize/Verify/Ship covers full development lifecycle | ARCH | v15.0 | ACCEPTED |
| 003 | 2025-12-14 | UX | Reason lines replace Critical section | Provides actionable context for non-green stages without clutter | UX | v16.0 | ACCEPTED |
| 004 | 2025-12-14 | OPS | Snapshot logging only for Yellow/Red states | Green states don't need debugging; reduces log volume | OPS | v16.0 | ACCEPTED |
| 005 | 2025-12-14 | ARCH | Hash+debounce dedupe for snapshots | Prevents spam during rapid redraws while capturing state changes | ARCH | v16.0 | ACCEPTED |

---

## Decision Types
- **INIT**: Project initialization
- **SCOPE**: Scope changes
- **ARCH**: Architecture decisions
- **API**: API design
- **DATA**: Data model changes
- **SECURITY**: Security decisions
- **UX**: User experience
- **PERF**: Performance
- **OPS**: Operations
- **TEST**: Testing strategy
- **RELEASE**: Release decisions

---

*Log version: 16.0*
