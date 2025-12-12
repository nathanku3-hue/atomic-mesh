"""
Atomic Mesh v8.1 - Enterprise Guardrails
Dynamic context windowing and safety prompts for robust operation.

Features:
- Tiered context limits based on task complexity
- Context7 version guardrail (style, not syntax)
- Dynamic efficiency rule (adaptive peek limits)
- Smart truncation with Head+Tail strategy
"""

import os
import json
from typing import Dict, Optional

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

def get_config_path() -> str:
    """Get the path to context_limits.json."""
    # Try multiple locations
    paths = [
        os.path.join(os.path.dirname(__file__), "..", "config", "context_limits.json"),
        os.path.join(os.getcwd(), "atomic-mesh", "config", "context_limits.json"),
        os.path.join(os.getcwd(), "config", "context_limits.json"),
    ]
    
    for path in paths:
        if os.path.exists(path):
            return path
    
    return paths[0]  # Default

def load_config() -> Dict:
    """Load context limits configuration."""
    config_path = get_config_path()
    
    if os.path.exists(config_path):
        with open(config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    # Fallback defaults
    return {
        "tiers": {
            "low": {"max_spec_chars": 2000, "max_standard_chars": 2000, "max_peeks": 1},
            "normal": {"max_spec_chars": 15000, "max_standard_chars": 10000, "max_peeks": 3},
            "high": {"max_spec_chars": 50000, "max_standard_chars": 30000, "max_peeks": 8}
        }
    }

# =============================================================================
# COMPLEXITY DETECTION
# =============================================================================

LOW_COMPLEXITY_TRIGGERS = [
    "fix typo", "rename", "update text", "change color",
    "adjust spacing", "minor change", "quick fix", "small change",
    "update label", "fix spacing", "correct", "tweak"
]

HIGH_COMPLEXITY_TRIGGERS = [
    "refactor", "rewrite", "migrate", "architecture",
    "redesign", "microservices", "overhaul", "rebuild",
    "from scratch", "entire system", "major change",
    "complete rewrite", "architectural change"
]

def analyze_task_complexity(task_prompt: str) -> str:
    """
    Determines task complexity for dynamic guardrail selection.
    
    Returns: 'low', 'normal', or 'high'
    """
    prompt_lower = task_prompt.lower()
    
    # Check for low complexity triggers
    for trigger in LOW_COMPLEXITY_TRIGGERS:
        if trigger in prompt_lower:
            return "low"
    
    # Check for high complexity triggers
    for trigger in HIGH_COMPLEXITY_TRIGGERS:
        if trigger in prompt_lower:
            return "high"
    
    # Word count heuristic
    word_count = len(task_prompt.split())
    if word_count < 10:
        return "low"
    if word_count > 100:
        return "high"
    
    # Multiple file extensions mentioned
    file_mentions = sum(1 for ext in [".py", ".ts", ".tsx", ".js", ".jsx", ".sql"] 
                       if ext in prompt_lower)
    if file_mentions >= 3:
        return "high"
    
    return "normal"

# =============================================================================
# DYNAMIC LIMITS
# =============================================================================

def get_dynamic_limits(task_prompt: str) -> Dict:
    """
    Returns context limits scaled to task complexity.
    
    Args:
        task_prompt: The task description
    
    Returns:
        Dict with max_spec_chars, max_standard_chars, max_peeks, etc.
    """
    config = load_config()
    complexity = analyze_task_complexity(task_prompt)
    
    print(f"⚖️  Dynamic Guardrails: Tier = {complexity.upper()}")
    
    tier = config.get("tiers", {}).get(complexity)
    if not tier:
        tier = config.get("tiers", {}).get("normal", {})
    
    # Add complexity to the returned dict
    tier["complexity"] = complexity
    
    return tier

# =============================================================================
# CONTEXT TRUNCATION
# =============================================================================

def truncate_context(content: str, max_chars: int = 10000) -> str:
    """
    Safety valve to prevent Context Bombing.
    
    Uses Head+Tail strategy to keep most important parts.
    - Head: Usually has imports, class definitions, high-level structure
    - Tail: Usually has recent changes, conclusions, key details
    
    Args:
        content: The content to truncate
        max_chars: Maximum characters to keep
    
    Returns:
        Truncated content with [SNIPPED] marker if needed
    """
    if not content:
        return ""
    
    if len(content) <= max_chars:
        return content
    
    half = max_chars // 2
    
    # Find good break points (newlines)
    head = content[:half]
    tail = content[-half:]
    
    # Try to break at newlines for cleaner truncation
    head_break = head.rfind('\n')
    if head_break > half * 0.7:  # Don't truncate too much
        head = head[:head_break]
    
    tail_break = tail.find('\n')
    if tail_break > 0 and tail_break < half * 0.3:
        tail = tail[tail_break + 1:]
    
    snip_marker = f"\n\n... [SNIPPED {len(content) - max_chars:,} chars for focus] ...\n\n"
    
    return head + snip_marker + tail

def smart_truncate_for_role(content: str, role: str, limits: Dict) -> str:
    """
    Role-aware truncation using dynamic limits.
    """
    if role == "spec":
        max_chars = limits.get("max_spec_chars", 15000)
    elif role == "standard":
        max_chars = limits.get("max_standard_chars", 10000)
    elif role == "reference":
        max_chars = limits.get("max_reference_chars", 8000)
    else:
        max_chars = limits.get("max_total_context_chars", 50000)
    
    return truncate_context(content, max_chars)

# =============================================================================
# SAFETY PROMPTS
# =============================================================================

CONTEXT7_GUARDRAIL = """
[REFERENCE PROTOCOL - CONTEXT7]
You have access to 'Context7' (Great Projects) for reference.

RULES:
1. ✅ USE for: Naming conventions, folder structure, architectural patterns
2. ⚠️ ADAPT for: Import syntax, method signatures, API calls (CHECK VERSIONS)
3. ❌ NEVER blindly copy if it conflicts with TECH_STACK.md

CRITICAL VERSION CHECK:
- Before using any reference code, verify library versions match your project
- If Reference uses Pydantic v1 but TECH_STACK says v2 → ADAPT syntax to v2
- If Reference uses axios but TECH_STACK says httpx → TRANSLATE the pattern
- If Reference uses class components but project uses hooks → CONVERT

WHEN IN DOUBT: 
Check docs/TECH_STACK.md first, then adapt reference patterns to match.
"""

def get_efficiency_rule(max_peeks: int) -> str:
    """
    Returns the efficiency rule prompt with dynamic peek limit.
    """
    return f"""
[EFFICIENCY RULE - DYNAMIC {max_peeks}-PEEK LIMIT]
You are limited to {max_peeks} reference lookup(s) for this task:

Recommended allocation:
{"- 1x for the specific pattern you need" if max_peeks >= 1 else ""}
{"- 1x for architecture reference (if needed)" if max_peeks >= 2 else ""}
{"- 1x for Context7 external reference (if needed)" if max_peeks >= 3 else ""}
{"- Additional peeks available for complex exploration" if max_peeks > 3 else ""}

After {max_peeks} peek(s), you MUST start building. 
Pattern: PLAN → PEEK (max {max_peeks}) → BUILD → VALIDATE

Choose your references wisely, then EXECUTE.
"""


# =============================================================================
# v8.4.1 YAGNI PROTOCOL (Minimum Necessity)
# =============================================================================
# This guardrail penalizes over-engineering and speculative coding.
# "You Ain't Gonna Need It" - only build what's explicitly required.

SIMPLEX_RULE = """
[MINIMUM NECESSITY PROTOCOL - YAGNI]
You Ain't Gonna Need It. Write the simplest code that works.

STRICT RULES:
1. ❌ NO "just in case" code: Don't create files, classes, or functions for "future use"
2. ❌ NO premature abstraction: If logic is used ONCE, inline it. Don't extract to a helper.
3. ❌ NO over-typing: Use simple types. Avoid complex Generics<T> unless truly needed.
4. ❌ NO ghost code: No commented-out code. No unused imports.

SIMPLICITY CHECKS:
- If a function is < 5 lines and used once → INLINE IT
- If a class has only one method → MAKE IT A FUNCTION  
- If a helper file has one function → PUT IT IN THE CALLER
- If a config has one value → JUST USE A CONSTANT

PHILOSOPHY:
- "Boring code" is GOOD code. Clever code is a liability.
- Complexity is a bug, not a feature.
- The user asked for X. Build X. Nothing more.

WHEN IN DOUBT:
Ask: "Does the ACTIVE_SPEC.md explicitly require this?" 
If NO → Don't build it.
"""


# =============================================================================
# v8.6 TDD 2.0 PROTOCOL (Vibe Coding Norm)
# =============================================================================
# Enforces Test-Driven Development: Tests FIRST, Code SECOND
# This ensures quality isn't an afterthought.

TDD_PROTOCOL = """
[TDD 2.0 PROTOCOL - MANDATORY]
You MUST follow this sequence for every logic task:

1. **THINK:** Design the Unit Tests first (consider edge cases)
2. **WRITE:** Create test file FIRST: tests/test_<feature>.py
3. **WRITE:** Create implementation: src/<feature>.py
4. **VERIFY:** Run tests to confirm implementation works

TEST REQUIREMENTS:
- Cover happy path + at least 2 edge cases
- Include error cases (invalid input, missing data)
- Mock external dependencies (API calls, DB)

NEVER write implementation without a corresponding test file.
If the task is "Add login" → First write tests/test_login.py

Exception: Pure UI/styling tasks don't require unit tests.
"""


# =============================================================================
# v8.6.1 SENIOR ENGINEER TONE
# =============================================================================
# The system should feel like a Senior Engineer, not a Chatbot.
# Terse. Professional. Action-oriented.

SENIOR_ENGINEER_TONE = """
[TONE: SENIOR ENGINEER]
Communication style guidelines:

DO:
- Be terse and direct
- State actions and results only
- Use bullet points for multiple items
- Report status: "✅ Done" / "❌ Failed: [reason]"

DON'T:
- Apologize or use filler phrases
- Explain standard procedures
- Ask permission for obvious next steps
- Use chatty language ("I noticed...", "I think...", "Let me...")

Example BAD: "I noticed some formatting issues, so I ran the linter. I also added a test file for you."
Example GOOD: "Linting: fixed. Tests: created tests/test_feature.py. Ready for review."
"""


# =============================================================================
# v9.0 CITATION PROTOCOL (Compliance Engineering)
# =============================================================================
# Every core function MUST cite its source from CODE_BOOK.md

CITATION_PROTOCOL = """
[CITATION PROTOCOL - MANDATORY FOR COMPLIANCE]
Every core logic function MUST include a citation in its docstring.

REQUIRED FORMAT:
```python
def calculate_penalty(days_late: int) -> float:
    '''
    @citation 4.2.3
    
    Implements: Section 4.2.3 - Late Payment Penalties
    Logic: 1.5% per day, capped at 15% maximum
    '''
    ...
```

THE SYSTEM WILL:
1. Parse all @citation tags
2. Verify cited sections exist in docs/CODE_BOOK.md
3. REJECT code missing citations or citing non-existent sections

This enables full traceability for audits.
"""


# =============================================================================
# v9.0 CLOSED WORLD RULE (Compliance Engineering)
# =============================================================================
# Prohibits use of external knowledge not in project docs

CLOSED_WORLD_RULE = """
[CLOSED WORLD ASSUMPTION - STRICT]
You are PROHIBITED from using knowledge not found in these documents:
- docs/CODE_BOOK.md (The Law)
- docs/DOMAIN_RULES.md (The Constitution)
- docs/TECH_STACK.md (Approved Technologies)

WHEN KNOWLEDGE IS MISSING:
- DO NOT improvise or use "common sense"
- DO NOT infer from similar patterns
- MUST raise: "Undefined Domain State: [description]"
- MUST flag for human review

FORBIDDEN:
- External knowledge from training data
- "Industry standard" patterns not in docs
- "Best practices" not explicitly approved

THE LAW IS THE CODE BOOK. NOTHING ELSE.
"""


# =============================================================================
# COMBINED GUARDRAILS
# =============================================================================

def get_worker_guardrails(task_prompt: str = "", compliance_mode: bool = False) -> str:
    """
    Returns combined guardrails for Worker agents.
    
    v8.4.1: Includes SIMPLEX_RULE (YAGNI Protocol)
    v8.6: Includes TDD_PROTOCOL (Tests First)
    v8.6.1: Includes SENIOR_ENGINEER_TONE
    v9.0: Includes CITATION_PROTOCOL + CLOSED_WORLD_RULE (if compliance_mode)
    
    Args:
        task_prompt: Used to determine dynamic limits
        compliance_mode: If True, adds strict compliance rules
    
    Returns:
        Combined guardrail prompts
    """
    limits = get_dynamic_limits(task_prompt) if task_prompt else {"max_peeks": 3}
    
    base_guardrails = (
        CONTEXT7_GUARDRAIL + "\n\n" + 
        get_efficiency_rule(limits.get("max_peeks", 3)) + "\n\n" +
        SIMPLEX_RULE + "\n\n" +
        TDD_PROTOCOL + "\n\n" +
        SENIOR_ENGINEER_TONE
    )
    
    # v9.0: Add compliance rules if enabled
    if compliance_mode:
        base_guardrails += "\n\n" + CITATION_PROTOCOL + "\n\n" + CLOSED_WORLD_RULE
    
    return base_guardrails

def get_full_guardrails(task_prompt: str) -> Dict:
    """
    Returns all guardrails and limits for a task.
    
    Args:
        task_prompt: The task description
    
    Returns:
        Dict with limits, prompts, and complexity info
    """
    limits = get_dynamic_limits(task_prompt)
    
    return {
        "complexity": limits.get("complexity", "normal"),
        "limits": limits,
        "prompts": {
            "context7": CONTEXT7_GUARDRAIL,
            "efficiency": get_efficiency_rule(limits.get("max_peeks", 3)),
            "combined": get_worker_guardrails(task_prompt)
        },
        "truncation": {
            "spec": limits.get("max_spec_chars", 15000),
            "standard": limits.get("max_standard_chars", 10000),
            "reference": limits.get("max_reference_chars", 8000)
        }
    }
