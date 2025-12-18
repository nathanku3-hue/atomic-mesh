# UI Flow: BOOTSTRAP → PLAN → GO

Three deterministic pages drive navigation. Page changes are explicit and centralized through `Set-Page($page)`; refreshes never change the page on their own.

## Pages
- **BOOTSTRAP**: Shown when the workspace is new or not ready to plan/run. Explains readiness status and offers a single prioritized Next.
- **PLAN**: For drafting, previewing, and accepting plans. Shows plan identity and the next planning action.
- **GO**: Execution dashboard and main loop. Always renders and surfaces execution fallbacks.

## Routing Rules
- `/go` → `Set-Page("GO")` then run execution.
- `/plan`, `/draft-plan` → `Set-Page("PLAN")`.
- `/accept-plan` → stays on the current page; on success triggers a refresh. Policy B: success suggests `/go`, no auto-switch.
- `/help`, `/ops`, `/status`, `/commands`, `/refresh`, `/clear`, `/workers`, `/explain` → no page change; `/refresh` re-renders the current page only.
- Legacy `/exec` is an alias for `/go` (kept for compatibility, hidden from `/commands`).
- Deterministic default landing: if not initialized, DB missing, or readiness != `EXECUTION`, default page is **BOOTSTRAP**; otherwise **PLAN**.

## Fallbacks and Next Actions
- **BOOTSTRAP**
  - Default when not initialized, DB missing, or readiness is BOOTSTRAP/PRE_INIT.
  - Next precedence: no draft → `/draft-plan`; draft not accepted → `/accept-plan`; accepted plan but no workers → start workers then `/go`; accepted plan + workers → `/go`.
  - Escape hatch: `Go to planning: /plan`.
- **PLAN**
  - Shows plan identity: no draft / draft exists / accepted plan (with filename if known).
  - Next precedence: no draft → `/draft-plan`; draft not accepted → `/accept-plan`; accepted plan → `/go`.
  - If `read_only_mode` is on and plan is not accepted, shows a short warning.
  - Navigation hint: `Run work: /go`.
- **GO**
  - Always renders, even when not ready.
  - Banners + Next are derived from shared pipeline state:
    - No accepted plan → banner + Next `/accept-plan` + hint `Go to planning: /plan`.
    - Accepted plan but zero tasks → banner + Next `/accept-plan` or `/refresh-plan` (based on plan identity).
    - Accepted plan with pending tasks but zero workers → banner + Next `start workers then /go`.
    - All tasks complete → banner `NO_WORK` + suggested `/plan`, `/draft-plan`, `/refresh-plan`.
    - Snapshot failure → banner `Snapshot error: …` plus minimal cached view.
  - Next suggestions never contradict plan/task state; worker counts come from `worker_heartbeats` to avoid phantom activity.

## Deprecation / Alias Policy
- `/exec` kept as an alias to `/go` for backward compatibility but omitted from discovery lists.
- Existing command aliases remain; routing is enforced by the centralized `Set-Page` helper.
