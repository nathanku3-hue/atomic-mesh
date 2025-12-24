# Vibe Coding System V1.2 - Release Notes

**Release Date:** 2024-12-24  
**Status:** Platinum Master 🚀

---

## 💎 What's New in V1.2

### 1. **Blocked Task Management**
The system now proactively manages tasks that get "stuck" in a blocked state.

**Problem:** Workers sometimes block tasks ("Missing Info") and they sit ignored forever.
**Solution:** `sweeper_blocked_tasks` runs in the main loop.

**Logic:**
- If Blocked > 24 Hours (`BLOCKED_TIMEOUT_SEC`):
  - **Reassign:** Reset task to `pending` with `attempt_count + 1`. This brings in a "fresh pair of eyes" (new worker).
  - **Escalate:** If reassigned 3 times (`MAX_RETRIES`), it sends a **CRITICAL** alert to the human.

---

### 2. **Agent Tools Interface**
New `agent_tools.py` library for workers.

- `ask_clarification(task_id, question)`:
  - Sets status to `blocked`
  - Logs question to `task_messages`
  - Stores blocker reason in `metadata['blocker_msg']`
  - Releases lease immediately

- `claim_task(lane, worker_id)`:
  - Atomic claim with lease management
  - Returns task context

---

### 3. **Smart Notifications**
Console notifications now classify issues for faster triage.

- **[Missing Dependency]**: "Make sure to install numpy..."
- **[Risk Gate]**: "High Risk Task submitted..."
- **[Ambiguity]**: "Goal is unclear..."
- **[Blocked Task]**: "Task #1 blocked > 24h"

---

## 🔄 Migration Guide (V1.1 → V1.2)

1. **Replace Files:**
   - `vibe_controller.py` (V1.2 version)
   - `agent_tools.py` (New file)

2. **Configuration:**
   - Optional: Set `BLOCKED_TIMEOUT_SEC` env var (defaults to 86400 / 24h).

3. **Restart Controller:**
   - `python vibe_controller.py`

---

## 🧪 Testing V1.2

```bash
# Run the blocked task simulation
python tests/test_vibe_controller_v12.py
```

**Expected Output:**
```
🧪 Test: Blocked Task Workflow
   Worker actions: ask_clarification()
   ✅ Status -> blocked
   Simulating 24h wait (backdating)...
   Controller actions: sweep_blocked_tasks()
⚠️ [BlockWatch] Task #1 blocked > 24h.
⚠️ [17:24:52] Task #1 [Blocked Task]: Blocked too long (0h). Reassigning...
   ✅ Task reassigned (pending, attempt += 1)
```

---

_Vibe Coding System V1.2 - Platinum Master Release_
