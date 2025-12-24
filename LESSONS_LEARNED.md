# Lessons Learned (Anti-Regression)

> This file is automatically updated when tasks fail QA or encounter issues.
> Workers MUST check relevant lessons before starting work.

---

## Auth & Security
- **[2025-12-24]** Never commit `.env` files. Always use `.env.example`.
- **[2025-12-24]** JWT secrets must be >= 32 characters.

## UI/Frontend
- **[2025-12-24]** Sidebar component requires fixed width on mobile to prevent layout shift.
- **[2025-12-24]** Always test at 375px viewport for mobile.

## Backend
- **[2025-12-24]** SQLite `Row` objects don't support `.get()` - use `row['key']` instead.

## Testing
- **[2025-12-24]** Reset module-level state in test teardown to prevent cross-test pollution.

---

*Last updated: 2025-12-24*
