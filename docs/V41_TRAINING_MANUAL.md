# V4.1 Vibe Coding Training Manual

## Introduction
Welcome to V4.1 Uranium Master. This update bridges the gap between our "Prompt Compiler" architecture and daily operations. It introduces strict "Pre-Flight" checks and automated safety logging to prevent "Skill Drift" and security incidents.

---

## 🛑 The "Pre-Flight" Protocol (Worker)
**Why?** Most task failures occur because the worker started with a dirty environment or missing context.

**The Check:**
Before you type `search_code` or open a file, you MUST verify:
1.  **Dependencies:** Is the feature I'm building on actually finished?
    *   *How to check:* Read the Task Goal carefully. Check `git_log` for recent related commits.
2.  **Environment:** Is my workspace clean?
    *   *How to check:* Run `git_status`. If it's not empty, STOP.
3.  **Skill Pack:** Do I have the right instructions?
    *   *How to check:* Look for the `--- [LANE] SKILLS ---` section in your prompt. If it's missing, ASK WHY.

**Rule of Thumb:** "If the cockpit isn't ready, don't take off."

---

## 🛡️ The Safety Health Check (Architect)
**Why?** We cannot rely on workers to catch every security nuance. The Architect must flag high-risk tasks *before* assignment.

**The Check:**
1.  **Fetch Wisdom:** Call `get_relevant_lessons(keywords=["security", "auth", ...])`.
2.  **Evaluate:** Did the system warn you about past security failures?
3.  **Action:** If YES, you MUST add `Constraint: Security Audit Required` to the task instructions.

---

## 📉 Tool-Assisted Compilation & Fallback
**The Problem:** Sometimes we add a new lane (e.g., `mobile`) but forget to create `skills/mobile.md`.
**The Solution:**
- The Compiler now auto-logs these misses to `LESSONS_LEARNED.md`.
- **Your Job:** If you see a "Fallback applied" warning in the logs, create the missing skill file immediately.

---

## 🤖 New Guardrails (Automatic)
The system now proactively blocks:
1.  **Prompt Injection:** "Ignore previous instructions..." -> `[FILTERED]`
2.  **Secrets:** API Keys, Passwords -> `[REDACTED]`
3.  **Malicious Code:** `DROP TABLE`, `<script>` -> `[BLOCKED]`

**Note:** If your valid code gets blocked (e.g., you are writing a SQL migration that *legitimately* drops a table), you must explicitely request an override via the admin channel (not fully automated yet).

---

## Summary for Success
1.  **Architects:** Check lessons first. Flag security risks.
2.  **Workers:** Pre-flight check every single time.
3.  **Everyone:** Trust the guardrails, but verify the output.
