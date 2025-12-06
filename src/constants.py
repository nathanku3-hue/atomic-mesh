"""
Atomic Mesh v8.5.1 - Shared Constants
Single Source of Truth for cross-module constants.

This eliminates DRY violations where the same data was defined in:
- mesh_server.py
- guardrails.py
- qa_protocol.py
"""

# =============================================================================
# COMPLEXITY TRIGGERS (Used by: guardrails, qa_protocol, mesh_server)
# =============================================================================

# Low complexity: Quick fixes, minor changes
LOW_COMPLEXITY_TRIGGERS = [
    "fix typo", "rename", "update text", "change color",
    "adjust spacing", "minor change", "quick fix", "small change",
    "update label", "fix spacing", "correct", "tweak"
]

# High complexity: Major architectural work (triggers Opus model)
HIGH_COMPLEXITY_TRIGGERS = [
    "refactor", "rewrite", "migrate", "architecture",
    "redesign", "microservices", "overhaul", "rebuild",
    "from scratch", "entire system", "major change",
    "complete rewrite", "architectural change"
]

# Alias for backwards compatibility
COMPLEXITY_TRIGGERS = HIGH_COMPLEXITY_TRIGGERS


# =============================================================================
# QA CHECKS (Used by: qa_protocol)
# =============================================================================

QA1_CHECKS = [
    "Does the code compile/parse without syntax errors?",
    "Are there any undefined variables or imports?",
    "Does the logic match the task description?",
    "Are edge cases handled (null, empty, negative)?",
    "Is error handling present for I/O and network?",
    "Are async operations properly awaited?",
]

QA2_CHECKS = [
    # Style Quality
    "Is variable naming descriptive (not x, temp, data)?",
    "Is function length reasonable (< 50 lines)?",
    "Is code DRY (Don't Repeat Yourself)?",
    "Are nested loops < 3 levels deep (spaghetti detector)?",
    "Is code readable by a junior developer?",
    "Are magic numbers explained with constants?",
    "Are complex sections commented?",
    "Does the code 'smell' clean?",
    
    # YAGNI PROTOCOL (Minimum Necessity)
    "YAGNI: Is there speculative generality (code for 'future use cases' that don't exist)?",
    "YAGNI: Is there premature abstraction (helpers/services for logic used only once)?",
    "YAGNI: Are there over-typed complex Generics<T> where simple types work?",
    "YAGNI: Is there ghost code (commented out code, unused imports)?",
    "YAGNI: Were unnecessary files/directories created 'just in case'?",
]

QA2_FAIL_ON = [
    "Speculative generality - code written for imaginary future requirements",
    "Premature abstraction - extracted function/class used exactly once",
    "Helper file with single function that should be inlined",
    "Config for single value that should be a constant",
    "Ghost code - commented blocks or unused imports",
]


# =============================================================================
# SECURITY PATTERNS (Used by: mesh_server secret detection)
# =============================================================================

SECRET_PATTERNS = [
    r'api_key\s*=\s*["\'][^"\']{20,}["\']',
    r'sk-[a-zA-Z0-9]{20,}',
    r'password\s*=\s*["\'][^"\']+["\']',
    r'secret\s*=\s*["\'][^"\']+["\']',
    r'token\s*=\s*["\'][^"\']{20,}["\']',
    r'AWS_SECRET_ACCESS_KEY',
    r'PRIVATE_KEY',
]


# =============================================================================
# PRIORITY LEVELS (Used by: mesh_server arbiter)
# =============================================================================

class Priority:
    """Priority levels for resource contention."""
    CRITICAL = 3  # Auditor - blocks everything
    HIGH = 2      # Worker/Commander - normal ops
    MEDIUM = 1    # Background tasks
    LOW = 0       # Librarian - runs when idle
