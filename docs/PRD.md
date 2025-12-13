# Product Requirements Document: Atomic Mesh Control Panel

**Author**: Engineering Team | **Date**: 2025-12-14 | **Status**: Active

---

## One-liner
**What are we building?**
A TUI-based control panel for managing Atomic Mesh development workflows with real-time pipeline status, task management, and automated verification gates.

## Goals
**Primary Objective (testable):**
Provide developers with a single-pane dashboard showing context readiness, task pipeline status, and actionable next steps without leaving the terminal.

**Goals (measurable):**
- G1: Pipeline visibility - show all 6 stages (Context/Plan/Work/Optimize/Verify/Ship) with color-coded status in under 100ms render time
- G2: Reduce context switching - operators should complete 80% of daily workflows without opening external tools
- G3: Prevent ship errors - block /ship when verification gates fail (HIGH risk unverified, dirty git)

---

## Users & Context
**Primary personas:**
- P1: Solo Developer - needs quick visibility into what to do next without reading logs
- P2: Team Lead - needs oversight of pipeline health and blocking issues across workstreams

**Usage context (where/when):**
- Terminal-first workflow during active development sessions
- CI/CD integration for automated status checks

---

## User Stories
### Must Have (MVP)
- US1: As a developer, I can see pipeline status at a glance so that I know which stage needs attention
      **Acceptance:** All 6 stages visible with GREEN/YELLOW/RED/GRAY coloring
- US2: As a developer, I can see reason lines for non-green stages so that I understand why something is blocked
      **Acceptance:** Up to 2 reason lines displayed, RED stages shown first
- US3: As a developer, I can trust that /ship is blocked when unsafe so that I don't accidentally release broken code
      **Acceptance:** Ship stage is RED when Verify has unverified HIGH risk tasks

### Should Have (vNext)
- US4: As a team lead, I can review pipeline snapshots to debug past issues
- US5: As a developer, I can customize which stages are most prominent

### Nice to Have (Future)
- US6: As a developer, I can integrate custom verification gates

---

## UX / Workflow
**Happy path (5-8 steps):**
1. Launch control panel - see dashboard with current pipeline status
2. Check CONTEXT stage - if YELLOW/RED, edit golden docs (PRD/SPEC/DECISION_LOG)
3. Check PLAN stage - if RED, run /draft-plan to generate tasks
4. Check WORK stage - if YELLOW, run /go to start execution
5. Check VERIFY stage - if RED, run /verify on HIGH risk tasks
6. Check SHIP stage - if GREEN, run /ship to release

**Edge cases (pick 2):**
- EC1: All docs missing (PRE_INIT) - show RED context with clear /init instruction
- EC2: Readiness check fails - fail-open to BOOTSTRAP mode with warning

---

## Success Metrics
**How will we know this is working?**
- Metric: Time to understand pipeline state | Baseline: 30s (reading logs) | Target: 2s (glance at dashboard) | Instrumentation: User feedback
- Metric: Ship failures due to missed verification | Baseline: unknown | Target: 0 | Instrumentation: Incident log

---

## Constraints
**Hard constraints (non-negotiable):**
- Platform: Windows PowerShell 5.1+ (primary), cross-platform future
- Performance: Dashboard render under 200ms, no UI flicker
- Security/Privacy: No secrets in logs, snapshot files contain only status metadata
- Compatibility: Works in standard Windows Terminal and ConEmu

---

## Out of Scope (MVP)
> Explicitly excluded to prevent scope creep
- Multi-repo dashboard aggregation
- Real-time collaboration features
- Mobile/web interface

---

## Risks
- R1: PowerShell rendering inconsistencies across terminal emulators | Mitigation: Test on Windows Terminal, ConEmu, VS Code
- R2: Large snapshot files over time | Mitigation: Dedupe + debounce, future log rotation

---

## Milestones
- M0 (MVP): Pipeline status with reason lines + snapshot logging | Deadline: v16.0
- M1 (Next): Log rotation and snapshot analytics | Deadline: v16.1

---

*Template version: 16.0 (deblackbox)*
