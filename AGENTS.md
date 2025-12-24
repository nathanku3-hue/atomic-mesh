# Vibe Coding Global Constitution
## Version: 1.0

### 1. Prime Directive
We write **Production** code, not "Example" code.

### 2. Hygiene Protocol
- **Linting:** Run linter before submission
- **Sandbox:** All file operations stay in working directory
- **Atomic Commits:** 1 Task = 1 Commit (`feat(lane): description`)

### 3. Definition of Done
A task is ONLY complete when:
1. ✅ Code is implemented
2. ✅ Tests are passing
3. ✅ Linting is clean
4. ✅ No `console.log` or debug statements remain
5. ✅ Type safety enforced (no `any` unless justified)

### 4. Safety Rules
- **NEVER** commit `.env` files (use `.env.example`)
- **NEVER** hardcode secrets or API keys
- **ALWAYS** use parameterized queries for SQL
- **ALWAYS** validate user input

### 5. Communication Protocol
- Status updates: `📋 STATUS: [brief description]`
- Blockers: `🚧 BLOCKED: [reason]`
- Questions: `❓ QUESTION: [specific question]`
- Completion: `✅ DONE: [summary]`
