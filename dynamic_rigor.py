"""
Atomic Mesh v9.6 - Phase-Driven TDD with Safety Valve
The "Rigor Dial" - Automatically inherits from existing Mode system.

LOGIC:
  1. Explicit task tags ([L1], [L2], [L3]) - highest priority
  2. Risk escalation (Safety Valve) - high-risk forces IRONCLAD
  3. Mode inheritance (vibe/converge/ship) - time-based baseline
  
NO MANUAL KNOBS - Rigor is derived from project state.
"""

import os
import re
from typing import Tuple, Optional
from enum import Enum
from datetime import datetime

# =============================================================================
# RIGOR LEVELS
# =============================================================================

class RigorLevel(Enum):
    SPIKE = "L1_SPIKE"       # Zero tests, fast prototyping (VIBE mode)
    BUILD = "L2_BUILD"       # Happy path TDD (CONVERGE mode)
    IRONCLAD = "L3_IRONCLAD" # Strict TDD + edge cases (SHIP mode)

# Rigor descriptions for display
RIGOR_DESCRIPTIONS = {
    RigorLevel.SPIKE: "⚡ Fast prototyping - no tests (VIBE)",
    RigorLevel.BUILD: "🔨 Standard development - happy path TDD (CONVERGE)",
    RigorLevel.IRONCLAD: "🛡️ Strict TDD - full coverage + review (SHIP)"
}

# Worker personas per rigor level
RIGOR_PERSONAS = {
    RigorLevel.SPIKE: """You are a Hacker. Move fast, break things if needed.
Priority: Get pixels on screen. Ignore conventions if they slow you down.
Validation: "It works" is enough. No tests required.""",

    RigorLevel.BUILD: """You are a Developer. Write solid, maintainable code.
Priority: Working feature with reasonable safety.
Validation: Happy path test must pass. Basic error handling required.""",

    RigorLevel.IRONCLAD: """You are a Senior Engineer. Safety is paramount.
Priority: Zero regressions. Production-grade code.
Validation: ALL tests must pass including edge cases. Code review required."""
}

# =============================================================================
# RISK DETECTION (Safety Valve)
# =============================================================================

# High-risk file patterns - trigger IRONCLAD regardless of phase
HIGH_RISK_PATHS = [
    "core/", "auth", "payment", "schema", "security",
    "middleware", "session", "crypto", "database", "migration"
]

# High-risk keywords in task description
HIGH_RISK_KEYWORDS = [
    "refactor", "security", "delete", "rewrite", "migrate",
    "authentication", "authorization", "password", "token",
    "encrypt", "decrypt", "critical", "breaking"
]

# Low-risk patterns - safe for SPIKE even in CONVERGE
LOW_RISK_PATHS = [
    "docs/", ".md", ".css", ".txt", "readme",
    "test_", "_test", ".test.", ".spec.",
    "mock", "fixture", "example"
]


def detect_risk_level(task_desc: str, target_file: str = None) -> str:
    """
    Detects the risk level of a task.
    
    Returns:
        "HIGH" - Core/security, forces IRONCLAD
        "LOW" - Docs/CSS, allows SPIKE
        "MEDIUM" - Standard feature work
    """
    desc_lower = task_desc.lower()
    file_lower = (target_file or "").lower()
    
    # Check for HIGH risk indicators
    if any(p in file_lower for p in HIGH_RISK_PATHS):
        return "HIGH"
    if any(kw in desc_lower for kw in HIGH_RISK_KEYWORDS):
        return "HIGH"
    
    # Check for LOW risk indicators
    if any(p in file_lower for p in LOW_RISK_PATHS):
        return "LOW"
    if any(kw in desc_lower for kw in ["docs", "readme", "comment", "typo", "css", "style"]):
        return "LOW"
    
    return "MEDIUM"


# =============================================================================
# PHASE-DRIVEN RIGOR DETERMINATION (v9.6)
# =============================================================================

def determine_workflow(task_desc: str, target_file: str = None, get_mode_func=None) -> tuple:
    """
    v9.6: Determines rigor based on Phase x Risk matrix.
    
    Priority Order:
    1. Explicit Tags ([L1], [SPIKE], etc.) - user override
    2. Risk Escalation (Safety Valve) - high-risk forces IRONCLAD
    3. Mode Inheritance (vibe/converge/ship) - time-based baseline
    
    Args:
        task_desc: The task description
        target_file: Optional file path being modified
        get_mode_func: Function to get current mode (injected for testability)
        
    Returns:
        Tuple of (RigorLevel, reason_string)
    """
    desc_upper = task_desc.upper()
    file_display = target_file or "(no file)"
    
    # --- 1. EXPLICIT OVERRIDES (Highest Priority) ---
    if "[L1]" in desc_upper or "[SPIKE]" in desc_upper:
        return RigorLevel.SPIKE, "Explicit [L1]/[SPIKE] tag in task"
    if "[L2]" in desc_upper or "[BUILD]" in desc_upper:
        return RigorLevel.BUILD, "Explicit [L2]/[BUILD] tag in task"
    if "[L3]" in desc_upper or "[IRONCLAD]" in desc_upper:
        return RigorLevel.IRONCLAD, "Explicit [L3]/[IRONCLAD] tag in task"
    
    # --- 2. RISK ESCALATION (Safety Valve) ---
    risk = detect_risk_level(task_desc, target_file)
    if risk == "HIGH":
        # Find which high-risk pattern triggered
        trigger = "critical keywords"
        for p in HIGH_RISK_PATHS:
            if p in (target_file or "").lower():
                trigger = f"'{target_file}' matches '{p}'"
                break
        for kw in HIGH_RISK_KEYWORDS:
            if kw in task_desc.lower():
                trigger = f"'{kw}' keyword detected"
                break
        return RigorLevel.IRONCLAD, f"Safety Valve: {trigger}"
    
    # --- 3. MODE INHERITANCE (Existing 3-Tier System) ---
    mode = "vibe"
    if get_mode_func:
        try:
            mode = get_mode_func()
        except Exception:
            pass
    
    # Map existing Mode to Rigor with reason
    if mode == "ship":
        return RigorLevel.IRONCLAD, "Ship mode (≤2 days to milestone)"
    elif mode == "converge":
        if risk == "LOW":
            return RigorLevel.SPIKE, f"Converge mode + LOW risk ({file_display})"
        return RigorLevel.BUILD, f"Converge mode (2-7 days to milestone)"
    else:  # vibe
        return RigorLevel.SPIKE, "Vibe mode (>7 days to milestone)"


def get_rigor_from_mode(mode: str, risk: str = "MEDIUM") -> RigorLevel:
    """
    Returns rigor level based on mode and risk combination.
    
    The Phase x Risk Matrix:
    
    Mode/Risk    | LOW     | MEDIUM  | HIGH
    -------------|---------|---------|----------
    VIBE         | SPIKE   | SPIKE   | IRONCLAD
    CONVERGE     | SPIKE   | BUILD   | IRONCLAD
    SHIP         | BUILD   | IRONCLAD| IRONCLAD
    """
    matrix = {
        "vibe": {"LOW": RigorLevel.SPIKE, "MEDIUM": RigorLevel.SPIKE, "HIGH": RigorLevel.IRONCLAD},
        "converge": {"LOW": RigorLevel.SPIKE, "MEDIUM": RigorLevel.BUILD, "HIGH": RigorLevel.IRONCLAD},
        "ship": {"LOW": RigorLevel.BUILD, "MEDIUM": RigorLevel.IRONCLAD, "HIGH": RigorLevel.IRONCLAD},
    }
    
    mode_lower = mode.lower()
    if mode_lower not in matrix:
        mode_lower = "converge"  # Default
    
    return matrix[mode_lower].get(risk, RigorLevel.BUILD)


# =============================================================================
# SPIKE MODE HYGIENE (Refinement 3)
# =============================================================================

def check_spike_hygiene(task_desc: str, target_file: str = None) -> Optional[str]:
    """
    Checks if running SPIKE mode might break existing tests.
    
    Returns warning message if existing tests found, None otherwise.
    """
    if not target_file:
        # Try to extract target file from task description
        file_match = re.search(r'(?:src/|lib/)?(\w+(?:/\w+)*)\.py', task_desc)
        if file_match:
            target_file = file_match.group(1)
    
    if not target_file:
        return None
    
    # Check for existing test file
    test_patterns = [
        f"tests/test_{os.path.basename(target_file)}.py",
        f"tests/{os.path.basename(target_file)}_test.py",
        f"test_{os.path.basename(target_file)}.py"
    ]
    
    for pattern in test_patterns:
        if os.path.exists(pattern):
            return f"⚠️ [SPIKE WARNING] '{pattern}' exists. This spike may break it."
    
    return None


# =============================================================================
# SIGNATURE CONTRACT (Refinement 1)
# =============================================================================

def extract_signature_contract(test_content: str) -> dict:
    """
    Extracts the [SIGNATURE] block from generated test content.
    
    Expected format in test file:
    # [SIGNATURE]
    # def login_user(email: str, password: str) -> dict
    # def validate_session(token: str) -> bool
    # [/SIGNATURE]
    
    Returns:
        {"functions": ["login_user(email: str, password: str) -> dict", ...]}
    """
    signature_match = re.search(
        r'\[SIGNATURE\](.*?)\[/SIGNATURE\]', 
        test_content, 
        re.DOTALL | re.IGNORECASE
    )
    
    if not signature_match:
        return {"functions": [], "warning": "No [SIGNATURE] block found in tests"}
    
    signature_block = signature_match.group(1)
    
    # Extract function signatures
    func_pattern = r'#?\s*(def \w+\([^)]*\)\s*(?:->\s*\w+)?)'
    functions = re.findall(func_pattern, signature_block)
    
    return {
        "functions": functions,
        "raw": signature_block.strip()
    }


def build_signature_constraint(signatures: dict) -> str:
    """
    Builds a constraint block for the Code Worker based on test signatures.
    """
    if not signatures.get("functions"):
        return ""
    
    constraint = """
[SIGNATURE CONTRACT - YOU MUST IMPLEMENT EXACTLY THESE FUNCTIONS]
The test file expects these exact function signatures. Do not rename or change parameters.

"""
    for func in signatures["functions"]:
        constraint += f"  • {func}\n"
    
    constraint += """
CRITICAL: If you use different names, the tests WILL FAIL.
"""
    return constraint


# =============================================================================
# TEST GENERATION PROMPTS
# =============================================================================

TEST_GEN_PROMPT_HAPPY_PATH = """
ROLE: Test Engineer (L2 BUILD Mode)
TASK: Write a happy-path test for this User Story.

USER STORY: {task_description}

REQUIREMENTS:
1. Create a pytest test file
2. Include [SIGNATURE] block at the top with function signatures
3. Write 1-2 tests for the main success path
4. Tests MUST fail when run (no implementation yet)
5. Use clear assertion messages

FORMAT:
```python
# [SIGNATURE]
# def function_name(param: type) -> return_type
# [/SIGNATURE]

import pytest

def test_happy_path():
    # Test the main success case
    ...
```
"""

TEST_GEN_PROMPT_COMPREHENSIVE = """
ROLE: Senior Test Engineer (L3 IRONCLAD Mode)
TASK: Write comprehensive tests for this User Story.

USER STORY: {task_description}

REQUIREMENTS:
1. Create a pytest test file
2. Include [SIGNATURE] block at the top with ALL function signatures
3. Cover:
   - Happy path (main success case)
   - Edge cases (empty inputs, boundaries)
   - Error cases (invalid inputs, failures)
4. Tests MUST fail when run (no implementation yet)
5. Use clear assertion messages

FORMAT:
```python
# [SIGNATURE]
# def function_name(param: type) -> return_type
# [/SIGNATURE]

import pytest

class TestFeatureName:
    def test_success_case(self):
        '''Test the main success path'''
        ...
    
    def test_edge_case_empty(self):
        '''Test with empty/null input'''
        ...
    
    def test_error_invalid_input(self):
        '''Test error handling for invalid input'''
        ...
```
"""


# =============================================================================
# CODE GENERATION PROMPT TEMPLATE
# =============================================================================

CODE_GEN_PROMPT = """
ROLE: {persona}
TASK: Write code that makes these tests pass.

{signature_constraint}

TESTS TO SATISFY:
```python
{test_content}
```

PROJECT CONTEXT:
- Follow conventions in TECH_STACK.md
- {additional_constraints}

REQUIREMENTS:
1. Implement EXACTLY the functions in [SIGNATURE]
2. Write ONLY enough code to pass the tests
3. Include proper error handling
4. No over-engineering

OUTPUT: Complete implementation code.
"""


# =============================================================================
# LOGGING HELPER
# =============================================================================

def log_rigor_action(level: RigorLevel, action: str, details: str = ""):
    """Logs rigor-related actions to mesh.log for dashboard telemetry."""
    try:
        log_dir = os.path.join(os.getcwd(), "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "mesh.log")
        
        icon = {"L1_SPIKE": "⚡", "L2_BUILD": "🔨", "L3_IRONCLAD": "🛡️"}.get(level.value, "")
        
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"[THOUGHT] {icon} [{level.value}] {action}: {details[:60]}\n")
    except Exception:
        pass


# =============================================================================
# v9.7 CORE/EDGE LOCK (Hard Guardrail)
# =============================================================================
# Makes core paths physically unwritable unless explicitly unlocked.
# Defense in Depth: Safety Valve (soft) + Core Lock (hard)

import time as _time

# Protected directory patterns (path segments)
CORE_LOCKED_PATHS = [
    "core",           # Any /core/ directory
    "auth",           # Authentication-related
    "security",       # Security modules
    "migrations",     # Database migrations
    "secrets",        # Secret storage
]

# Protected file patterns (exact filenames)
CORE_LOCKED_FILES = [
    ".env",
    ".env.production",
    "secrets.json",
    "credentials.json",
    "private.key",
]

# Lock state (global singleton)
CORE_LOCK_STATE = {
    "locked": True,           # Default: locked
    "unlock_scope": None,     # "next_task" or "session"
    "unlocked_by": None,      # Who unlocked
    "unlocked_at": None,      # Timestamp
}


def check_core_lock(file_path: str) -> tuple:
    """
    v9.7: Checks if file is in a locked core area.
    Uses path-aware matching to prevent false positives.
    
    Args:
        file_path: The file path to check
        
    Returns:
        Tuple of (allowed: bool, reason: str)
    """
    if not file_path:
        return True, "No file path provided"
    
    # Normalize path separators (handle Windows/Linux)
    norm_path = os.path.normpath(file_path.lower())
    parts = norm_path.split(os.sep)  # Split into ['src', 'core', 'auth.py']
    filename = parts[-1] if parts else ""
    
    # 1. Check protected files (exact match)
    for protected_file in CORE_LOCKED_FILES:
        if filename == protected_file.lower():
            if not CORE_LOCK_STATE["locked"]:
                return True, f"Core unlocked - allowing '{filename}'"
            return False, f"❌ BLOCKED: Protected file '{filename}'. Use /unlock core first."
    
    # 2. Check protected directories (segment match)
    for pattern in CORE_LOCKED_PATHS:
        clean_pattern = pattern.strip("/\\").lower()
        
        # Check if pattern matches a directory segment exactly
        if clean_pattern in parts:
            if not CORE_LOCK_STATE["locked"]:
                return True, f"Core unlocked - allowing '{clean_pattern}/' directory"
            return False, f"❌ BLOCKED: Protected directory '{clean_pattern}/'. Use /unlock core first."
    
    return True, "Path is not protected"


def unlock_core(scope: str = "next_task", unlocked_by: str = "user") -> str:
    """
    v9.7: Temporarily unlocks core paths.
    
    Args:
        scope: "next_task" (auto-locks after task) or "session" (stays unlocked)
        unlocked_by: Identifier for audit trail
        
    Returns:
        Status message
    """
    global CORE_LOCK_STATE
    
    CORE_LOCK_STATE["locked"] = False
    CORE_LOCK_STATE["unlock_scope"] = scope
    CORE_LOCK_STATE["unlocked_by"] = unlocked_by
    CORE_LOCK_STATE["unlocked_at"] = _time.time()
    
    # Log the unlock action
    try:
        log_dir = os.path.join(os.getcwd(), "logs")
        os.makedirs(log_dir, exist_ok=True)
        log_path = os.path.join(log_dir, "mesh.log")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"[THOUGHT] 🔓 [CORE_UNLOCK] Scope={scope} By={unlocked_by}\n")
    except Exception:
        pass
    
    if scope == "next_task":
        return "🔓 Core UNLOCKED for next task only. Auto-locks after completion."
    else:
        return "⚠️ Core UNLOCKED for entire session. Use /lock to re-lock."


def lock_core() -> str:
    """
    v9.7: Immediately locks core paths.
    
    Returns:
        Status message
    """
    global CORE_LOCK_STATE
    
    was_unlocked = not CORE_LOCK_STATE["locked"]
    
    CORE_LOCK_STATE["locked"] = True
    CORE_LOCK_STATE["unlock_scope"] = None
    CORE_LOCK_STATE["unlocked_by"] = None
    CORE_LOCK_STATE["unlocked_at"] = None
    
    if was_unlocked:
        # Log the lock action
        try:
            log_dir = os.path.join(os.getcwd(), "logs")
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, "mesh.log")
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(f"[THOUGHT] 🔒 [CORE_LOCK] Core paths re-locked\n")
        except Exception:
            pass
    
    return "🔒 Core paths LOCKED"


def get_lock_status() -> dict:
    """
    v9.7: Returns current lock status for dashboard/API.
    """
    status = {
        "locked": CORE_LOCK_STATE["locked"],
        "icon": "🔒" if CORE_LOCK_STATE["locked"] else "🔓",
        "status": "LOCKED" if CORE_LOCK_STATE["locked"] else "UNLOCKED",  # SAFETY-ALLOW: status-write
        "unlock_scope": CORE_LOCK_STATE["unlock_scope"],
        "protected_paths": CORE_LOCKED_PATHS,
        "protected_files": CORE_LOCKED_FILES,
    }
    
    if not CORE_LOCK_STATE["locked"] and CORE_LOCK_STATE["unlocked_at"]:
        elapsed = int(_time.time() - CORE_LOCK_STATE["unlocked_at"])
        status["unlocked_for_seconds"] = elapsed
        status["unlocked_by"] = CORE_LOCK_STATE["unlocked_by"]
    
    return status


def auto_lock_if_needed() -> bool:
    """
    v9.7: Auto-locks if unlock scope was "next_task".
    Call this in finally block after task execution.
    
    Returns:
        True if auto-locked, False otherwise
    """
    if CORE_LOCK_STATE["unlock_scope"] == "next_task":
        lock_core()
        return True
    return False


# =============================================================================
# v9.8 DYNAMIC CLARIFICATION (Pre-Flight Interrogation)
# =============================================================================
# Forces agents to ask questions before coding, based on rigor level.
# Uses machine-parsable metadata for reliable parsing.

import json

# Clarification round limits by rigor level
CLARIFICATION_LIMITS = {
    RigorLevel.SPIKE: 0,      # No pre-flight, ask only if stuck
    RigorLevel.BUILD: 1,      # One round: "Do I have inputs/outputs?"
    RigorLevel.IRONCLAD: 3    # Three rounds: Requirements → Edge Cases → Architecture
}

# Round focus prompts
ROUND_FOCUS = {
    1: "Identify missing requirements and ambiguous terms.",
    2: "Analyze edge cases, security risks, and error states.",
    3: "Critique the proposed architecture. What will break?"
}

# Tools allowed during clarification phase (READ-ONLY + ask)
CLARIFICATION_SAFE_TOOLS = [
    "read_file", "list_files", "view_file", "grep_search",
    "ask_question", "get_open_questions", "dashboard"
]

# Path to clarification queue
CLARIFICATION_QUEUE_PATH = "docs/CLARIFICATION_QUEUE.md"


def _get_queue_path():
    """Returns full path to clarification queue file."""
    return os.path.join(os.getcwd(), CLARIFICATION_QUEUE_PATH)


def _ensure_queue_exists():
    """Creates the clarification queue file if it doesn't exist."""
    queue_path = _get_queue_path()
    os.makedirs(os.path.dirname(queue_path), exist_ok=True)
    
    if not os.path.exists(queue_path):
        with open(queue_path, "w", encoding="utf-8") as f:
            f.write("# Clarification Queue\n\n")
            f.write("_Questions logged by agents. Answer with `/answer Qn \"your answer\"`_\n\n")


def get_next_question_id() -> str:
    """Gets the next question ID (Q1, Q2, etc.)."""
    _ensure_queue_exists()
    
    try:
        with open(_get_queue_path(), "r", encoding="utf-8") as f:
            content = f.read()
        
        # Find all existing question IDs using metadata
        import re
        matches = re.findall(r'"id":\s*"Q(\d+)"', content)
        if matches:
            max_id = max(int(m) for m in matches)
            return f"Q{max_id + 1}"
    except Exception:
        pass
    
    return "Q1"


def append_to_clarification_queue(
    qid: str,
    question: str,
    context: str,
    round_num: int = 1,
    task_id: int = None
) -> str:
    """
    v9.8: Appends a question to the clarification queue.
    Uses HTML comment metadata for machine-reliable parsing.
    
    Args:
        qid: Question ID (e.g., "Q1")
        question: The question text
        context: File or context being discussed
        round_num: Clarification round (1, 2, or 3)
        task_id: Optional task ID this question blocks
        
    Returns:
        Confirmation message
    """
    _ensure_queue_exists()
    
    # Machine-parsable metadata (JSON in HTML comment)
    metadata = json.dumps({
        "id": qid,
        "status": "OPEN",  # SAFETY-ALLOW: status-write
        "round": round_num,
        "task_id": task_id,
        "timestamp": _time.time()
    })
    
    entry = f"""
<!--QUESTION_META:{metadata}-->
## {qid} [OPEN]
**Round:** {round_num} ({ROUND_FOCUS.get(round_num, "General")})
**Context:** `{context}`
**Question:** {question}

---
"""
    
    with open(_get_queue_path(), "a", encoding="utf-8") as f:
        f.write(entry)
    
    # Log to mesh.log
    try:
        log_dir = os.path.join(os.getcwd(), "logs")
        os.makedirs(log_dir, exist_ok=True)
        with open(os.path.join(log_dir, "mesh.log"), "a", encoding="utf-8") as f:
            f.write(f"[THOUGHT] ❓ [CLARIFICATION] {qid}: {question[:50]}\n")
    except Exception:
        pass
    
    return f"⛔ Question {qid} logged. Waiting for user input via /answer"


def get_open_questions() -> list:
    """
    v9.8: Returns all open questions from the queue.
    Uses JSON metadata for reliable parsing.
    """
    _ensure_queue_exists()
    
    try:
        with open(_get_queue_path(), "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return []
    
    import re
    questions = []
    
    # Parse JSON metadata from HTML comments
    for match in re.finditer(r'<!--QUESTION_META:(\{[^}]+\})-->', content):
        try:
            data = json.loads(match.group(1))
            if data.get("status") == "OPEN":
                # Extract the question text
                qid = data.get("id", "?")
                q_match = re.search(
                    rf'## {qid} \[OPEN\].*?\*\*Question:\*\* (.+?)(?:\n|$)',
                    content, re.DOTALL
                )
                if q_match:
                    data["question"] = q_match.group(1).strip()
                questions.append(data)
        except json.JSONDecodeError:
            continue
    
    return questions


def count_open_questions() -> int:
    """Returns count of open questions."""
    return len(get_open_questions())


def mark_question_closed(qid: str, answer: str) -> bool:
    """
    v9.8: Marks a question as closed and records the answer.
    
    Args:
        qid: Question ID (e.g., "Q1")
        answer: The answer text
        
    Returns:
        True if question was found and closed
    """
    _ensure_queue_exists()
    
    try:
        with open(_get_queue_path(), "r", encoding="utf-8") as f:
            content = f.read()
    except Exception:
        return False
    
    import re
    
    # Update metadata status
    def update_meta(match):
        try:
            data = json.loads(match.group(1))
            if data.get("id") == qid:
                data["status"] = "CLOSED"  # SAFETY-ALLOW: status-write (question metadata, not task)
                data["answer"] = answer
                data["closed_at"] = _time.time()
                return f'<!--QUESTION_META:{json.dumps(data)}-->'
        except Exception:
            pass
        return match.group(0)
    
    content = re.sub(r'<!--QUESTION_META:(\{[^}]+\})-->', update_meta, content)
    
    # Update header
    content = content.replace(f'## {qid} [OPEN]', f'## {qid} [CLOSED]')
    
    # Add answer text
    answer_block = f"\n**Answer:** {answer}\n"
    content = re.sub(
        rf'(## {qid} \[CLOSED\].*?\*\*Question:\*\* .+?\n)',
        rf'\1{answer_block}',
        content, flags=re.DOTALL
    )
    
    with open(_get_queue_path(), "w", encoding="utf-8") as f:
        f.write(content)
    
    return True


def patch_active_spec(qid: str, answer: str) -> bool:
    """
    v9.8: Appends the clarification answer to ACTIVE_SPEC.md.
    This creates the "Single Source of Truth" for future agents.
    
    Args:
        qid: Question ID
        answer: The answer text
        
    Returns:
        True if spec was patched
    """
    spec_path = os.path.join(os.getcwd(), "docs", "ACTIVE_SPEC.md")
    
    try:
        # Read existing content
        if os.path.exists(spec_path):
            with open(spec_path, "r", encoding="utf-8") as f:
                content = f.read()
        else:
            content = "# Active Specification\n\n## Clarifications\n"
        
        # Add clarifications section if not exists
        if "## Clarifications" not in content:
            content += "\n\n## Clarifications\n"
        
        # Append the new clarification
        clarification = f"\n- **[{qid}]** {answer}\n"
        
        # Insert after Clarifications header
        import re
        content = re.sub(
            r'(## Clarifications\n)',
            rf'\1{clarification}',
            content
        )
        
        with open(spec_path, "w", encoding="utf-8") as f:
            f.write(content)
        
        return True
    except Exception:
        return False


def get_clarification_status() -> dict:
    """
    v9.8: Returns clarification queue status for dashboard.
    """
    open_qs = get_open_questions()
    
    return {
        "open_count": len(open_qs),
        "questions": open_qs,
        "status": "WAITING" if len(open_qs) > 0 else "READY",  # SAFETY-ALLOW: status-write
        "icon": "⚠️" if len(open_qs) > 0 else "✅"
    }


def get_software_lock_prompt(round_num: int, max_rounds: int) -> str:
    """
    v9.8: Generates the software lock prompt for clarification phase.
    This restricts the agent to READ-ONLY operations.
    """
    focus = ROUND_FOCUS.get(round_num, "General clarification")
    
    return f"""ROLE: Lead Auditor (Clarification Phase)
PHASE: Round {round_num}/{max_rounds}
FOCUS: {focus}

CONSTRAINTS:
- You have NO WRITE ACCESS to any files
- You MUST use ask_question for ANY ambiguity
- You can ONLY read files to understand context
- DO NOT attempt to implement or fix code

AVAILABLE TOOLS: {', '.join(CLARIFICATION_SAFE_TOOLS)}

If everything is clear, output: "READY - No questions needed."
Otherwise, use ask_question for each unclear item."""


# =============================================================================
# v9.8 TASK STATE MACHINE
# =============================================================================
# Links tasks to clarification questions. Prevents "Delegator Amnesia."

TASK_STATE_FILE = "control/state/tasks.json"

def _get_state_path():
    """Returns full path to task state file."""
    return os.path.join(os.getcwd(), TASK_STATE_FILE)


def load_task_state() -> dict:
    """
    v9.8: Loads the task state machine.
    
    Returns:
        State dict with active_task_id and tasks
    """
    try:
        with open(_get_state_path(), 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {"active_task_id": None, "tasks": {}}


def save_task_state(state: dict):
    """
    v9.8: Saves the task state machine.
    """
    try:
        state_path = _get_state_path()
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, 'w', encoding='utf-8') as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        print(f"⚠️ Failed to save task state: {e}")


def register_task(task_id: str, description: str, rigor: str, source_ids: list = None, target_file: str = None, dependencies: list = None, reasoning: str = None, archetype: str = None) -> dict:
    """
    v10.4: Registers a new task in the state machine with full traceability.

    Args:
        task_id: Unique task identifier
        description: Task description (should include [ARCHETYPE] prefix)
        rigor: Rigor level (L1_SPIKE, L2_BUILD, L3_IRONCLAD)
        source_ids: List of Source IDs from docs/sources/ (e.g. ["STD-SEC-01", "HIPAA-01"])
        target_file: Target file path for the task
        dependencies: List of task IDs this task depends on (e.g. ["T-001", "T-002"])
        reasoning: Why this task exists - traceability back to source text
        archetype: Task archetype (DB, API, LOGIC, UI, SEC, TEST, CLARIFICATION)

    Returns:
        The task state entry
    """
    state = load_task_state()

    # v10.3: Determine source tier based on ID prefixes
    sources = source_ids if source_ids else []
    source_tier = "standard"
    if sources:
        # Domain tier if any non-STD prefix (HIPAA, LAW, MED, etc.)
        if any(not s.startswith("STD-") for s in sources):
            source_tier = "domain"

    # v10.4: Extract archetype from description if not provided
    task_archetype = archetype
    if not task_archetype and description.startswith("[") and "]" in description:
        task_archetype = description.split("]")[0].strip("[").upper()
    task_archetype = task_archetype or "GENERIC"

    # v10.4: Determine if task is blocked by dependencies
    status = "PENDING"
    if task_archetype == "CLARIFICATION":
        status = "BLOCKING"  # Clarification tasks block the pipeline

    state["tasks"][str(task_id)] = {
        "description": description[:200],
        "status": status,  # SAFETY-ALLOW: status-write
        "rigor": rigor,
        "questions": [],
        "source_ids": sources,
        "source_tier": source_tier,
        "target_file": target_file,
        # v10.4 Fields
        "dependencies": dependencies or [],
        "reasoning": reasoning[:500] if reasoning else None,
        "archetype": task_archetype,
        "created_at": _time.time()
    }
    state["active_task_id"] = str(task_id)

    save_task_state(state)
    return state["tasks"][str(task_id)]


def update_task_status(task_id: str, status: str):
    """
    v9.8: Updates a task's status.
    
    Valid statuses: PENDING, CLARIFYING, WAITING, READY, IN_PROGRESS, TESTING, COMPLETE, FAILED
    """
    state = load_task_state()
    tid = str(task_id)
    
    if tid in state["tasks"]:
        state["tasks"][tid]["status"] = status  # SAFETY-ALLOW: status-write (dynamic_rigor state machine)
        state["tasks"][tid]["updated_at"] = _time.time()
        save_task_state(state)


def link_question_to_task(task_id: str, qid: str):
    """
    v9.8: Links a clarification question to a task.
    Sets task status to WAITING.
    """
    state = load_task_state()
    tid = str(task_id)
    
    if tid in state["tasks"]:
        if qid not in state["tasks"][tid]["questions"]:
            state["tasks"][tid]["questions"].append(qid)
        state["tasks"][tid]["status"] = "WAITING"  # SAFETY-ALLOW: status-write (dynamic_rigor state machine)
        save_task_state(state)


def unlink_question_from_task(qid: str) -> str:
    """
    v9.8: Removes a question from its linked task.
    If all questions answered, sets task to READY.
    
    Returns:
        Task ID if found, None otherwise
    """
    state = load_task_state()
    
    for tid, task in state["tasks"].items():
        if qid in task.get("questions", []):
            task["questions"].remove(qid)
            
            # Check if all questions resolved
            if len(task["questions"]) == 0 and task["status"] == "WAITING":  # SAFETY-ALLOW: status-write
                task["status"] = "READY"  # SAFETY-ALLOW: status-write (dynamic_rigor state, not mesh task)
            
            save_task_state(state)
            return tid
    
    return None


def get_active_task() -> dict:
    """
    v9.8: Gets the currently active task.
    
    Returns:
        Task dict or None
    """
    state = load_task_state()
    active_id = state.get("active_task_id")
    
    if active_id and active_id in state["tasks"]:
        task = state["tasks"][active_id]
        task["id"] = active_id
        return task
    
    return None


def get_task_status_display() -> dict:
    """
    v9.8: Gets task status for dashboard display.
    """
    task = get_active_task()
    
    if not task:
        return {
            "status": "IDLE",  # SAFETY-ALLOW: status-write
            "icon": "💤",
            "message": "No active task"
        }
    
    status = task.get("status", "UNKNOWN")
    questions = task.get("questions", [])
    
    if status == "WAITING":
        return {
            "status": "WAITING",  # SAFETY-ALLOW: status-write
            "icon": "⚠️",
            "message": f"WAITING ({len(questions)} questions: {', '.join(questions)})",
            "task_id": task["id"],
            "questions": questions
        }
    elif status == "IN_PROGRESS":
        return {
            "status": "IN_PROGRESS",  # SAFETY-ALLOW: status-write
            "icon": "▶️",
            "message": f"EXECUTING ({task.get('rigor', 'BUILD')})",
            "task_id": task["id"]
        }
    elif status == "READY":
        return {
            "status": "READY",  # SAFETY-ALLOW: status-write
            "icon": "✅",
            "message": "READY to execute",
            "task_id": task["id"]
        }
    elif status == "CLARIFYING":
        return {
            "status": "CLARIFYING",  # SAFETY-ALLOW: status-write
            "icon": "🔍",
            "message": "Pre-flight in progress",
            "task_id": task["id"]
        }
    elif status == "REVIEWING":
        return {
            "status": "REVIEWING",  # SAFETY-ALLOW: status-write
            "icon": "👁️",
            "message": "Under review",
            "task_id": task["id"]
        }
    elif status == "COMPLETE":
        return {
            "status": "COMPLETE",  # SAFETY-ALLOW: status-write
            "icon": "🏁",
            "message": "Complete (verified)",
            "task_id": task["id"]
        }
    elif status == "BLOCKED_REVIEW":
        return {
            "status": "BLOCKED_REVIEW",  # SAFETY-ALLOW: status-write
            "icon": "⛔",
            "message": "Start Infinite Loop Guard (Human Intervention Required)",
            "task_id": task["id"]
        }
    else:
        return {
            "status": status,  # SAFETY-ALLOW: status-write
            "icon": "📋",
            "message": status,
            "task_id": task.get("id")
        }


# =============================================================================
# v9.9 REVIEWER SYSTEM (The Gatekeeper)
# =============================================================================
# Final verification before marking task COMPLETE.
# Ensures code matches Spec and follows Domain Rules.

REVIEWER_PROMPT_PATH = "library/prompts/reviewer.md"
DOMAIN_RULES_PATH = "docs/DOMAIN_RULES.md"
ACTIVE_SPEC_PATH = "docs/ACTIVE_SPEC.md"
REVIEWS_DIR = "docs/reviews"


def load_reviewer_prompt() -> str:
    """
    v9.9: Loads the reviewer persona prompt.
    """
    try:
        prompt_path = os.path.join(os.getcwd(), REVIEWER_PROMPT_PATH)
        with open(prompt_path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return """ROLE: Code Reviewer
Review the code against ACTIVE_SPEC.md and DOMAIN_RULES.md.
Output: Status: PASS or Status: FAIL with specific issues."""


def load_domain_rules() -> str:
    """
    v9.9: Loads the domain rules (The Law).
    """
    try:
        rules_path = os.path.join(os.getcwd(), DOMAIN_RULES_PATH)
        with open(rules_path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return "# Domain Rules\n\nNo domain rules defined."


def load_active_spec() -> str:
    """
    v9.9: Loads the active specification (The Truth).
    """
    try:
        spec_path = os.path.join(os.getcwd(), ACTIVE_SPEC_PATH)
        with open(spec_path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:
        return "# Active Specification\n\nNo specification defined."


def save_review_artifact(task_id: str, review_content: str) -> str:
    """
    v9.9: Saves the review output to docs/reviews/REVIEW-{task_id}.md
    
    Args:
        task_id: The task ID
        review_content: The review markdown content
        
    Returns:
        Path to the saved review file
    """
    try:
        reviews_dir = os.path.join(os.getcwd(), REVIEWS_DIR)
        os.makedirs(reviews_dir, exist_ok=True)
        
        review_path = os.path.join(reviews_dir, f"REVIEW-{task_id}.md")
        
        # Add metadata header
        header = f"""<!--REVIEW_META:{json.dumps({
            "task_id": task_id,
            "timestamp": _time.time(),
            "version": "9.9"
        })}-->

"""
        
        with open(review_path, 'w', encoding='utf-8') as f:
            f.write(header + review_content)
        
        return review_path
    except Exception as e:
        print(f"⚠️ Failed to save review: {e}")
        return None


def parse_review_result(review_content: str) -> dict:
    """
    v9.9: Parses the review output to extract status and issues.
    
    Args:
        review_content: The raw review markdown
        
    Returns:
        {
            "status": "PASS" or "FAIL",  # SAFETY-ALLOW: status-write
            "issues": list of issues,
            "raw": original content
        }
    """
    import re
    
    # Look for Status: PASS or Status: FAIL (case insensitive)
    status_match = re.search(r'Status:\s*(PASS|FAIL)', review_content, re.IGNORECASE)
    status = status_match.group(1).upper() if status_match else "UNKNOWN"
    
    # Extract issues (lines starting with ❌ or containing VIOLATION)
    issues = []
    for line in review_content.split('\n'):
        if '❌' in line or 'VIOLATION' in line.upper() or 'FAIL' in line.upper():
            issues.append(line.strip())
    
    return {
        "status": status,  # SAFETY-ALLOW: status-write
        "issues": issues,
        "raw": review_content
    }


def build_review_context(task_desc: str, code_files: list = None) -> str:
    """
    v9.9: Builds the context for the reviewer agent.
    
    Args:
        task_desc: The task description
        code_files: List of file paths to include
        
    Returns:
        Formatted context string for the reviewer
    """
    context = f"""# Review Context

## Task Description
{task_desc}

## Domain Rules
{load_domain_rules()}

## Active Specification
{load_active_spec()}

"""
    
    if code_files:
        context += "## Code Files to Review\n\n"
        for file_path in code_files:
            try:
                full_path = os.path.join(os.getcwd(), file_path)
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                context += f"### {file_path}\n```\n{content}\n```\n\n"
            except Exception:
                context += f"### {file_path}\n(Could not read file)\n\n"
    
    return context


def get_review_status(task_id: str) -> dict:
    """
    v9.9: Gets the review status for a task.
    
    Returns:
        {
            "reviewed": bool,
            "status": "PASS" | "FAIL" | None,  # SAFETY-ALLOW: status-write
            "path": review file path or None
        }
    """
    try:
        reviews_dir = os.path.join(os.getcwd(), REVIEWS_DIR)
        review_path = os.path.join(reviews_dir, f"REVIEW-{task_id}.md")
        
        if os.path.exists(review_path):
            with open(review_path, 'r', encoding='utf-8') as f:
                content = f.read()
            result = parse_review_result(content)
            return {
                "reviewed": True,
                "status": result["status"],  # SAFETY-ALLOW: status-write
                "path": review_path,
                "issues_count": len(result["issues"])
            }
    except Exception:
        pass
    
    return {
        "reviewed": False,
        "status": None,  # SAFETY-ALLOW: status-write
        "path": None
    }
