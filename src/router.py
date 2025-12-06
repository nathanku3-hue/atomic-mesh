# C:\Tools\atomic-mesh\router.py
# SEMANTIC ROUTER - The Pre-Frontal Cortex of Atomic Mesh v7.4
# Features: Fast Path regex, Smart Path LLM with Timeout, Pronoun Resolution

import os
import re
import json
import sqlite3
import time
import logging
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout

# === CONFIGURATION ===

# Configurable timeout via environment variable (default 3.0s)
SMART_PATH_TIMEOUT = float(os.getenv("ROUTER_TIMEOUT", "3.0"))

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("SemanticRouter")

# Fast Path Patterns (No LLM needed - instant response)
# Format: (pattern, intent, action, param_extractor)
FAST_PATH_PATTERNS = [
    # EXECUTE - Trigger main loop
    (r"^(c|go|start|resume|continue|run)$", "EXECUTE", "resume", None),
    
    # HOTKEYS - Single character commands
    (r"^1$", "HOTKEY", "stream", {"target": "backend"}),
    (r"^2$", "HOTKEY", "stream", {"target": "frontend"}),
    (r"^[aA]$", "HOTKEY", "audit", None),
    (r"^[lL]$", "HOTKEY", "librarian", None),
    (r"^[dD]$", "HOTKEY", "decisions", None),
    (r"^[sS]$", "HOTKEY", "spec", None),
    (r"^[rR]$", "HOTKEY", "refresh", None),
    (r"^[mM]$", "HOTKEY", "mode_toggle", None),
    (r"^[hH]$", "QUERY", "help", None),
    (r"^[qQ]$", "EXIT", "quit", None),
    
    # QUERY - Read-only operations
    (r"^(status|stat)$", "QUERY", "status", None),
    (r"^(plan|roadmap)$", "QUERY", "plan", None),
    (r"^tasks?$", "QUERY", "tasks", None),
    (r"^task\s+(\d+)$", "QUERY", "task_detail", lambda m: {"task_id": int(m.group(1))}),
    (r"^help$", "QUERY", "help", None),
    
    # QUEUE_OPS - Structured commands
    (r"^post\s+(backend|frontend)\s+(.+)$", "QUEUE_OPS", "add", 
     lambda m: {"type": m.group(1), "desc": m.group(2)}),
    (r"^skip\s+(\d+)$", "QUEUE_OPS", "skip", lambda m: {"task_id": int(m.group(1))}),
    (r"^reset\s+(\d+)$", "QUEUE_OPS", "reset", lambda m: {"task_id": int(m.group(1))}),
    (r"^drop\s+(\d+)$", "QUEUE_OPS", "drop", lambda m: {"task_id": int(m.group(1))}),
    
    # NUKE - Safety interlock (Refinement 1)
    (r"^nuke\s+--confirm$", "QUEUE_OPS", "nuke", None),
    (r"^nuke$", "SAFETY_WARN", "nuke_confirm_required", 
     {"message": "⚠️ Type 'nuke --confirm' to clear all pending tasks"}),
    
    # CONFIG_SET - System settings
    (r"^mode\s+(backend|frontend|vibe)$", "CONFIG_SET", "mode", 
     lambda m: {"mode": m.group(1)}),
    (r"^mode$", "QUERY", "mode", None),
    (r"^set\s+(\w+)\s+(.+)$", "CONFIG_SET", "set", 
     lambda m: {"key": m.group(1), "value": m.group(2)}),
    (r"^milestone\s+(.+)$", "CONFIG_SET", "milestone", lambda m: {"date": m.group(1)}),
    
    # AGENT_DIRECT - Explicit agent calls
    (r"^lib(?:rarian)?\s+(scan|status|approve|execute|restore)(?:\s+(.*))?$", 
     "AGENT_DIRECT", "librarian", lambda m: {"action": m.group(1), "args": m.group(2)}),
    (r"^audit(?:or)?\s+(check|status|log)(?:\s+(.*))?$", 
     "AGENT_DIRECT", "auditor", lambda m: {"action": m.group(1), "args": m.group(2)}),
    
    # CONTEXT_SET - Quick decision/note
    (r"^decide\s+(\d+)\s+(.+)$", "CONTEXT_SET", "decide", 
     lambda m: {"decision_id": int(m.group(1)), "answer": m.group(2)}),
    (r"^decision:\s*(.+)$", "CONTEXT_SET", "add_decision", lambda m: {"content": m.group(1)}),
    (r"^blocker:\s*(.+)$", "CONTEXT_SET", "add_blocker", lambda m: {"content": m.group(1)}),
    (r"^note:\s*(.+)$", "CONTEXT_SET", "add_note", lambda m: {"content": m.group(1)}),
    
    # v8.5 HOT SWAP - User corrections that should interrupt the Worker
    # "No, use Blue instead" → Cancel current task, update spec, restart
    (r"^no,\s+(.+)$", "AGENT_DIRECT", "hot_swap", lambda m: {"instruction": m.group(0)}),
    (r"^wrong,?\s+(.+)$", "AGENT_DIRECT", "hot_swap", lambda m: {"instruction": m.group(0)}),
    (r"^actually[,\s]+(.+)$", "AGENT_DIRECT", "hot_swap", lambda m: {"instruction": m.group(0)}),
    (r"^instead[,\s]+(.+)$", "AGENT_DIRECT", "hot_swap", lambda m: {"instruction": m.group(0)}),
    (r"^change it[,\s]+(.+)$", "AGENT_DIRECT", "hot_swap", lambda m: {"instruction": m.group(0)}),
]

# Pronoun patterns for resolution
PRONOUN_PATTERNS = [
    r"\b(it|that|this)\b",
    r"\b(the task|current task)\b",
    r"\b(last one|previous)\b",
]


@dataclass
class RouteResult:
    """Result of routing an input."""
    intent: str
    action: str
    parameters: Optional[Dict[str, Any]]
    confidence: float
    source: str  # "fast_path", "smart_path", "timeout_fallback"
    raw_input: str
    
    def to_dict(self) -> Dict:
        return {
            "intent": self.intent,
            "action": self.action,
            "parameters": self.parameters,
            "confidence": self.confidence,
            "source": self.source
        }


class SemanticRouter:
    """
    The Pre-Frontal Cortex of Atomic Mesh v7.4.
    Routes user input to the correct system component.
    Features: timeout protection, log sanitization, resource cleanup.
    """
    
    # FIX #8: Patterns for log sanitization
    SENSITIVE_PATTERNS = [
        (r"(password|passwd|pwd)\s*[:=]\s*\S+", r"\1=***"),
        (r"(api[_-]?key|apikey)\s*[:=]\s*\S+", r"\1=***"),
        (r"(secret|token)\s*[:=]\s*\S+", r"\1=***"),
        (r"(sk-[a-zA-Z0-9]{20,})", "sk-***"),  # OpenAI keys
        (r"(ghp_[a-zA-Z0-9]{20,})", "ghp_***"),  # GitHub tokens
        (r"(AKIA[A-Z0-9]{16})", "AKIA***"),  # AWS keys
    ]
    
    def __init__(self, db_path: str, llm_client=None):
        self.db_path = db_path
        self.llm_client = llm_client  # Optional LLM for Smart Path
        self._executor = ThreadPoolExecutor(max_workers=1)  # For timeout handling
        self._init_session_tables()
    
    # FIX #5: Destructor to prevent zombie threads
    def __del__(self):
        """Cleanup ThreadPoolExecutor on shutdown to prevent resource leaks."""
        if hasattr(self, '_executor') and self._executor:
            try:
                self._executor.shutdown(wait=False)
                logger.debug("ThreadPoolExecutor shutdown complete")
            except Exception as e:
                logger.warning(f"Error during executor shutdown: {e}")
    
    # FIX #8: Log sanitization to prevent credential leaks
    def _sanitize_for_log(self, text: str) -> str:
        """Masks secrets in text before logging."""
        sanitized = text
        for pattern, replacement in self.SENSITIVE_PATTERNS:
            sanitized = re.sub(pattern, replacement, sanitized, flags=re.IGNORECASE)
        return sanitized
    
    def _init_session_tables(self):
        """Create session context and route log tables."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS session_context (
                key TEXT PRIMARY KEY,
                value TEXT,
                updated_at INTEGER
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS route_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                input TEXT,
                intent TEXT,
                action TEXT,
                parameters TEXT,
                confidence REAL,
                source TEXT,
                created_at INTEGER
            )
        """)
        
        conn.commit()
        conn.close()
    
    # === SESSION CONTEXT (Refinement 2) ===
    
    def set_context(self, key: str, value: Any):
        """Update session context (for pronoun resolution)."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("""
            INSERT OR REPLACE INTO session_context (key, value, updated_at)
            VALUES (?, ?, ?)
        """, (key, json.dumps(value), int(time.time())))
        conn.commit()
        conn.close()
    
    def get_context(self, key: str) -> Any:
        """Get value from session context."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM session_context WHERE key=?", (key,))
        row = cursor.fetchone()
        conn.close()
        if row:
            return json.loads(row[0])
        return None
    
    def update_last_shown_task(self, task_id: int):
        """Call this when displaying a task to user (Refinement 2)."""
        self.set_context("last_shown_task_id", task_id)
    
    def update_last_mentioned_task(self, task_id: int):
        """Call this when user explicitly mentions a task ID (Refinement 2)."""
        self.set_context("last_mentioned_task_id", task_id)
    
    def resolve_pronouns(self, text: str, params: Dict) -> Dict:
        """
        Replace pronouns with actual task IDs from context (Refinement 2).
        "Skip it" → "Skip 5" (if last_shown_task_id = 5)
        """
        resolved_params = params.copy() if params else {}
        
        # Check if input contains pronouns
        has_pronoun = any(re.search(p, text, re.IGNORECASE) for p in PRONOUN_PATTERNS)
        
        if has_pronoun and "task_id" not in resolved_params:
            # Try to resolve from context
            task_id = self.get_context("last_shown_task_id")
            if task_id is None:
                task_id = self.get_context("last_mentioned_task_id")
            
            if task_id:
                resolved_params["task_id"] = task_id
                resolved_params["_pronoun_resolved"] = True
        
        return resolved_params
    
    # === ROUTING LOGIC ===
    
    def route(self, user_input: str) -> RouteResult:
        """
        Main routing function with timeout protection.
        Returns: RouteResult with intent, action, and parameters.
        """
        text = user_input.strip()
        
        # FIX #8: Sanitize before logging to prevent credential leaks
        safe_log = self._sanitize_for_log(text)
        logger.info(f"Routing input: {safe_log[:100]}")  # Truncate for safety
        
        if not text:
            return RouteResult(
                intent="NOOP",
                action="empty",
                parameters=None,
                confidence=1.0,
                source="fast_path",
                raw_input=text
            )
        
        # 1. FAST PATH - Regex matching (instant)
        result = self._fast_path(text)
        if result:
            # Resolve pronouns if applicable
            result.parameters = self.resolve_pronouns(text, result.parameters)
            self._log_route(result)
            return result
        
        # 2. SMART PATH - LLM classification WITH TIMEOUT (Patch 3)
        if self.llm_client:
            result = self._smart_path_with_timeout(text)
            if result:
                result.parameters = self.resolve_pronouns(text, result.parameters)
                self._log_route(result)
                return result
        
        # 3. FALLBACK - Treat as chat
        result = RouteResult(
            intent="CHAT",
            action="respond",
            parameters={"text": text},
            confidence=0.5,
            source="fallback",
            raw_input=text
        )
        self._log_route(result)
        return result
    
    def _fast_path(self, text: str) -> Optional[RouteResult]:
        """Try to match input against Fast Path patterns."""
        text_lower = text.lower()
        
        for pattern, intent, action, param_extractor in FAST_PATH_PATTERNS:
            match = re.match(pattern, text_lower if intent != "CONTEXT_SET" else text, re.IGNORECASE)
            if match:
                params = None
                if param_extractor:
                    if callable(param_extractor):
                        params = param_extractor(match)
                    else:
                        params = param_extractor
                
                # Track task mentions (Refinement 2)
                if params and "task_id" in params:
                    self.update_last_mentioned_task(params["task_id"])
                
                return RouteResult(
                    intent=intent,
                    action=action,
                    parameters=params,
                    confidence=1.0,
                    source="fast_path",
                    raw_input=text
                )
        
        return None
    
    def _smart_path_with_timeout(self, text: str) -> Optional[RouteResult]:
        """
        Smart path with timeout protection (Patch 3: Ghost Router Fix).
        If LLM takes > timeout seconds, gracefully fallback.
        """
        if not self.llm_client:
            return None
        
        try:
            # Submit to thread pool with timeout
            future = self._executor.submit(self._smart_path_inner, text)
            result = future.result(timeout=SMART_PATH_TIMEOUT)
            return result
        
        except FuturesTimeout:
            logger.warning(f"Router timeout ({SMART_PATH_TIMEOUT}s) - Falling back to CHAT")
            return RouteResult(
                intent="CHAT",
                action="timeout_fallback",
                parameters={"text": text, "reason": "LLM timeout"},
                confidence=0.3,
                source="timeout_fallback",
                raw_input=text
            )
        
        except Exception as e:
            logger.error(f"Router error: {e}")
            return None
    
    def _smart_path_inner(self, text: str) -> Optional[RouteResult]:
        """Inner LLM call (runs in thread for timeout)."""
        try:
            response = self.llm_client.classify_intent(text)
            
            if response and response.get("intent"):
                return RouteResult(
                    intent=response["intent"],
                    action=response.get("action", "unknown"),
                    parameters=response.get("parameters"),
                    confidence=response.get("confidence", 0.8),
                    source="smart_path",
                    raw_input=text
                )
        except Exception as e:
            print(f"Smart path inner error: {e}")
        
        return None
    
    def _smart_path(self, text: str) -> Optional[RouteResult]:
        """Use LLM to classify complex natural language input (deprecated, use _smart_path_with_timeout)."""
        if not self.llm_client:
            return None
        
        try:
            response = self.llm_client.classify_intent(text)
            
            if response and response.get("intent"):
                return RouteResult(
                    intent=response["intent"],
                    action=response.get("action", "unknown"),
                    parameters=response.get("parameters"),
                    confidence=response.get("confidence", 0.8),
                    source="smart_path",
                    raw_input=text
                )
        except Exception as e:
            print(f"Smart path error: {e}")
        
        return None
    
    def _log_route(self, result: RouteResult):
        """Log routing decision for debugging."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO route_log (input, intent, action, parameters, confidence, source, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                result.raw_input,
                result.intent,
                result.action,
                json.dumps(result.parameters) if result.parameters else None,
                result.confidence,
                result.source,
                int(time.time())
            ))
            conn.commit()
            conn.close()
        except Exception:
            pass  # Don't fail on logging errors


class IntentExecutor:
    """
    The Switchboard - executes routed intents.
    """
    
    def __init__(self, db_path: str, router: SemanticRouter):
        self.db_path = db_path
        self.router = router
    
    def execute(self, route: RouteResult) -> Dict[str, Any]:
        """Execute a routed intent and return result."""
        intent = route.intent
        action = route.action
        params = route.parameters or {}
        
        executors = {
            "EXECUTE": self._execute_resume,
            "QUEUE_OPS": self._execute_queue_ops,
            "CONTEXT_SET": self._execute_context_set,
            "CONFIG_SET": self._execute_config_set,
            "AGENT_DIRECT": self._execute_agent_direct,
            "QUERY": self._execute_query,
            "HOTKEY": self._execute_hotkey,
            "SAFETY_WARN": self._execute_safety_warn,
            "EXIT": self._execute_exit,
            "CHAT": self._execute_chat,
            "NOOP": lambda a, p: {"status": "noop"}
        }
        
        executor = executors.get(intent, self._execute_unknown)
        return executor(action, params)
    
    def _execute_resume(self, action: str, params: Dict) -> Dict:
        """Trigger the main execution loop (on_command_C)."""
        return {"status": "execute", "action": "trigger_continue"}
    
    def _execute_queue_ops(self, action: str, params: Dict) -> Dict:
        """Modify the task queue."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        result = {"status": "success", "action": action}
        
        try:
            if action == "add":
                cursor.execute("""
                    INSERT INTO tasks (type, desc, status, priority, updated_at)
                    VALUES (?, ?, 'pending', 1, ?)
                """, (params["type"], params["desc"], int(time.time())))
                result["task_id"] = cursor.lastrowid
                result["message"] = f"Added task: {params['desc']}"
            
            elif action == "skip":
                cursor.execute(
                    "UPDATE tasks SET status='skipped' WHERE id=?",
                    (params["task_id"],)
                )
                result["message"] = f"Skipped task {params['task_id']}"
            
            elif action == "reset":
                cursor.execute("""
                    UPDATE tasks SET status='pending', retry_count=0, 
                    auditor_status='pending', auditor_feedback='[]'
                    WHERE id=?
                """, (params["task_id"],))
                result["message"] = f"Reset task {params['task_id']}"
            
            elif action == "drop":
                cursor.execute("DELETE FROM tasks WHERE id=?", (params["task_id"],))
                result["message"] = f"Dropped task {params['task_id']}"
            
            elif action == "nuke":
                cursor.execute("DELETE FROM tasks WHERE status='pending'")
                result["message"] = "Nuked all pending tasks"
            
            elif action == "reorder_top":
                # Move task matching keyword to top priority
                keyword = params.get("target_keyword", "")
                cursor.execute("""
                    UPDATE tasks SET priority = 99 
                    WHERE status='pending' AND desc LIKE ?
                """, (f"%{keyword}%",))
                result["message"] = f"Prioritized tasks matching '{keyword}'"
            
            conn.commit()
        except Exception as e:
            result = {"status": "error", "error": str(e)}
        finally:
            conn.close()
        
        return result
    
    def _execute_context_set(self, action: str, params: Dict) -> Dict:
        """Update context (decisions, notes, blockers)."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        result = {"status": "success", "action": action}
        
        try:
            if action == "decide":
                cursor.execute("""
                    UPDATE decisions SET status='resolved', answer=?
                    WHERE id=?
                """, (params["answer"], params["decision_id"]))
                result["message"] = f"Resolved decision {params['decision_id']}"
            
            elif action == "add_decision":
                cursor.execute("""
                    INSERT INTO decisions (priority, question, status, created_at)
                    VALUES ('yellow', ?, 'pending', ?)
                """, (params["content"], int(time.time())))
                result["message"] = f"Added decision: {params['content']}"
            
            elif action == "add_blocker":
                cursor.execute("""
                    INSERT INTO decisions (priority, question, status, created_at)
                    VALUES ('red', ?, 'pending', ?)
                """, (params["content"], int(time.time())))
                result["message"] = f"🔴 BLOCKER: {params['content']}"
            
            elif action == "add_note":
                # Store in config table
                cursor.execute("""
                    INSERT OR REPLACE INTO config (key, value)
                    VALUES ('last_note', ?)
                """, (params["content"],))
                result["message"] = f"Note saved: {params['content']}"
            
            conn.commit()
        except Exception as e:
            result = {"status": "error", "error": str(e)}
        finally:
            conn.close()
        
        return result
    
    def _execute_config_set(self, action: str, params: Dict) -> Dict:
        """Update system configuration."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        result = {"status": "success", "action": action}
        
        try:
            if action == "mode":
                cursor.execute(
                    "INSERT OR REPLACE INTO config (key, value) VALUES ('mode', ?)",
                    (params["mode"],)
                )
                result["message"] = f"Mode set to: {params['mode']}"
            
            elif action == "set":
                cursor.execute(
                    "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
                    (params["key"], params["value"])
                )
                result["message"] = f"Set {params['key']} = {params['value']}"
            
            elif action == "milestone":
                # Write to milestone file
                result["milestone"] = params["date"]
                result["message"] = f"Milestone set: {params['date']}"
            
            conn.commit()
        except Exception as e:
            result = {"status": "error", "error": str(e)}
        finally:
            conn.close()
        
        return result
    
    def _execute_agent_direct(self, action: str, params: Dict) -> Dict:
        """Direct call to a specific agent."""
        return {
            "status": "agent_call",
            "agent": action,
            "action": params.get("action") if params else None,
            "args": params.get("args") if params else None
        }
    
    def _execute_query(self, action: str, params: Dict) -> Dict:
        """Handle read-only queries."""
        return {"status": "query", "type": action, "params": params}
    
    def _execute_hotkey(self, action: str, params: Dict) -> Dict:
        """Handle hotkey presses."""
        return {"status": "hotkey", "key": action, "params": params}
    
    def _execute_safety_warn(self, action: str, params: Dict) -> Dict:
        """Return safety warning (Refinement 1)."""
        return {
            "status": "warning",
            "message": params.get("message", "Safety check required"),
            "requires_confirmation": True
        }
    
    def _execute_exit(self, action: str, params: Dict) -> Dict:
        """Handle exit request."""
        return {"status": "exit"}
    
    def _execute_chat(self, action: str, params: Dict) -> Dict:
        """Handle casual chat (no system change)."""
        return {"status": "chat", "text": params.get("text", "")}
    
    def _execute_unknown(self, action: str, params: Dict) -> Dict:
        """Handle unknown intent."""
        return {"status": "unknown", "action": action}


# === LLM CLIENT INTERFACE ===

class LLMClassifier:
    """
    Interface for LLM-based intent classification.
    Implement this based on your LLM provider (OpenAI, Anthropic, etc.)
    """
    
    CLASSIFICATION_PROMPT = """
You are the Routing Layer for an Autonomous Dev System.
Classify the user input into ONE of these intents:

## Intents
1. QUEUE_OPS - Modify task queue (add, reorder, skip, drop)
2. CONTEXT_SET - Provide facts, decisions, blockers
3. CONFIG_SET - Change system settings
4. AGENT_DIRECT - Explicitly call Librarian, Auditor, or Worker
5. QUERY - Ask a question (read-only)
6. CHAT - Casual conversation

## Rules
- "prioritize", "first", "before" → QUEUE_OPS
- "decision:", "blocker:", "note:" → CONTEXT_SET
- Mentions "Librarian", "Auditor" → AGENT_DIRECT
- Questions starting with "what", "how", "show" → QUERY
- If unclear, prefer QUEUE_OPS over CHAT

## Output (JSON only)
{"intent": "QUEUE_OPS", "action": "reorder_top", "parameters": {"target_keyword": "auth"}, "confidence": 0.9}
"""
    
    def __init__(self, api_key: str = None, model: str = "gpt-4o-mini"):
        self.api_key = api_key
        self.model = model
    
    def classify_intent(self, text: str) -> Optional[Dict]:
        """
        Classify user input using LLM.
        Override this method for your specific LLM provider.
        """
        # Placeholder - implement based on your LLM
        # Example for OpenAI:
        # response = openai.ChatCompletion.create(
        #     model=self.model,
        #     messages=[
        #         {"role": "system", "content": self.CLASSIFICATION_PROMPT},
        #         {"role": "user", "content": text}
        #     ]
        # )
        # return json.loads(response.choices[0].message.content)
        
        return None  # Fallback to fast path only


# === MAIN ENTRY POINTS ===

def create_router(db_path: str, llm_api_key: str = None) -> Tuple[SemanticRouter, IntentExecutor]:
    """Create router and executor instances."""
    llm_client = LLMClassifier(llm_api_key) if llm_api_key else None
    router = SemanticRouter(db_path, llm_client)
    executor = IntentExecutor(db_path, router)
    return router, executor


def route_and_execute(db_path: str, user_input: str) -> Dict[str, Any]:
    """One-shot route and execute for simple integration."""
    router, executor = create_router(db_path)
    route = router.route(user_input)
    result = executor.execute(route)
    result["route"] = route.to_dict()
    return result


if __name__ == "__main__":
    # Test the router
    import sys
    
    if len(sys.argv) > 2:
        db_path = sys.argv[1]
        test_input = " ".join(sys.argv[2:])
        result = route_and_execute(db_path, test_input)
        print(json.dumps(result, indent=2))
    else:
        print("Usage: python router.py <db_path> <user_input>")
        print("\nTest patterns:")
        test_cases = [
            "c", "go", "status", "1", "L",
            "post backend fix auth bug",
            "skip 5", "reset 3", "nuke", "nuke --confirm",
            "decision: use JWT", "blocker: API is down",
            "lib scan", "auditor check",
            "prioritize the auth API",
            "skip it", "do that first"
        ]
        for tc in test_cases:
            print(f"  '{tc}'")
