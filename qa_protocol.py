"""
Atomic Mesh v8.0 - Dual QA Protocol
The "Zero-Spaghetti" Code Quality System with Pre-Flight Tests

This module implements the Double-Blind QA Protocol:
  QA1 (The Compiler): Hard logic - security, types, architecture + INTENT CHECK
  QA2 (The Critic): Soft logic - readability, style, spaghetti detection

v8.0 ADDITIONS:
  - Pre-Flight Tests: Run local tests before QA approval
  - Intent Verification: QA checks if code fulfills ORIGINAL TASK (Patch 2)
  - Profile Injection: Explicit project profile context

Code is only APPROVED when:
  1. Pre-flight tests pass
  2. Both QA agents pass
  3. Code fulfills the original task intent
"""

import os
import json
import asyncio
import subprocess
import shutil
import shlex
from typing import Dict, List, Optional
from datetime import datetime

# v9.0: Compliance Suite Integration
try:
    from compliance_tools import (
        run_compliance_checks,
        verify_import_whitelist,
        verify_citations,
        log_compliance_incident,
        append_traceability
    )
    COMPLIANCE_ENABLED = True
except ImportError:
    COMPLIANCE_ENABLED = False


# =============================================================================
# CONFIGURATION
# =============================================================================

# Load pre-flight config
def load_preflight_config() -> Dict:
    """Load pre-flight test configuration."""
    config_path = os.path.join(os.path.dirname(__file__), "config", "preflight.json")
    
    # Try alternate paths
    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), "atomic-mesh", "config", "preflight.json")
    if not os.path.exists(config_path):
        return {"test_commands": {}, "timeout_seconds": 120}
    
    with open(config_path, 'r') as f:
        return json.load(f)

# =============================================================================
# QA CHECK DEFINITIONS
# =============================================================================

QA1_CHECKS = [
    "Does code compile/parse without errors?",
    "Are there Security Vulnerabilities (OWASP Top 10)?",
    "Is Type Safety enforced (type hints, schemas)?",
    "Are imports from approved TECH_STACK.md?",
    "Does it match the OpenAPI/API Spec?",
    "Is SQL injection prevented (parameterized queries)?",
    "Are authentication checks present on protected routes?",
    "Is error handling complete (no silent failures)?",
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
    
    # v8.4.1 YAGNI PROTOCOL (Minimum Necessity)
    "YAGNI: Is there speculative generality (code for 'future use cases' that don't exist)?",
    "YAGNI: Is there premature abstraction (helpers/services for logic used only once)?",
    "YAGNI: Are there over-typed complex Generics<T> where simple types work?",
    "YAGNI: Is there ghost code (commented out code, unused imports)?",
    "YAGNI: Were unnecessary files/directories created 'just in case'?",
    
    # v9.0 SCOPE COP (Gold Plating Detector)
    "SCOPE: Did the worker add helper functions not required by the strict spec?",
    "SCOPE: Did the worker handle edge cases that the spec defines as 'Impossible'?",
    "SCOPE: Is there 'extra' logic (retry mechanisms, auto-recovery) not in spec?",
    "SCOPE: Did the worker add 'nice to have' error messages not specified?",
]

QA2_FAIL_ON = [
    # YAGNI Violations
    "Speculative generality - code written for imaginary future requirements",
    "Premature abstraction - extracted function/class used exactly once",
    "Helper file with single function that should be inlined",
    "Config for single value that should be a constant",
    "Ghost code - commented blocks or unused imports",
    
    # v9.0 SCOPE COP Violations (Critical for Compliance)
    "Gold Plating - feature added that is not in ACTIVE_SPEC.md",
    "Scope Creep - handling edge case marked 'Impossible' in CODE_BOOK.md",
    "Unauthorized convenience feature - auto-retry, friendly errors not specified",
    "Logic Divergence - implementation differs from cited rule",
]


# =============================================================================
# PRE-FLIGHT TESTS (v8.0)
# =============================================================================

def detect_project_type() -> str:
    """Auto-detect project type based on files present."""
    cwd = os.getcwd()
    
    if os.path.exists(os.path.join(cwd, "next.config.js")) or \
       os.path.exists(os.path.join(cwd, "next.config.mjs")) or \
       os.path.exists(os.path.join(cwd, "next.config.ts")):
        return "typescript_next"
    
    if os.path.exists(os.path.join(cwd, "package.json")):
        return "typescript_node"
    
    if os.path.exists(os.path.join(cwd, "requirements.txt")) or \
       os.path.exists(os.path.join(cwd, "pyproject.toml")):
        return "python_backend"
    
    if os.path.exists(os.path.join(cwd, "main.tf")):
        return "infrastructure"
    
    return "general"

def run_preflight_tests(project_profile: str = None) -> Dict:
    """
    Runs local test suite based on project profile.
    
    v8.6: Now includes AUTO-FORMATTING before tests (Gap #2)
    
    Args:
        project_profile: The project profile (e.g., "python_backend")
    
    Returns:
        {"passed": bool, "message": str, "output": str}
    """
    if not project_profile:
        project_profile = detect_project_type()
    
    # =========================================================================
    # v8.6 GAP #2: AUTO-FORMATTING (Runs BEFORE tests)
    # =========================================================================
    # Cost: 0 tokens, <1 second
    # Saves: 500-1000 tokens on QA2 formatting complaints
    # =========================================================================
    print("🧹 Pre-Flight: Running Auto-Formatters...")

    def _run_cmd(cmd, *, timeout_s: int):
        """
        SECURITY: No shell=True. If a command needs shell operators, it must be
        modeled explicitly (argv list) instead of a single string.
        Returns subprocess.CompletedProcess.
        """
        if isinstance(cmd, (list, tuple)):
            return subprocess.run(
                list(cmd),
                shell=False,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                cwd=os.getcwd(),
            )

        cmd_str = str(cmd).strip()
        # If the config contains shell operators, refuse rather than falling back to shell=True.
        if any(op in cmd_str for op in ["|", "&", ";", ">", "<"]):
            raise ValueError(
                f"Refusing to run command containing shell operators: {cmd_str!r}. "
                "Use an argv list in config (no shell=True)."
            )

        argv = shlex.split(cmd_str, posix=(os.name != "nt"))
        return subprocess.run(argv, shell=False, capture_output=True, text=True, timeout=timeout_s, cwd=os.getcwd())

    try:
        if "python" in project_profile:
            # Ruff: Fast Python formatter + linter
            if shutil.which("ruff"):
                _run_cmd(["ruff", "format", ".", "--quiet"], timeout_s=30)
                _run_cmd(["ruff", "check", "--fix", "--quiet", "."], timeout_s=30)
                print("   ✅ Python formatted (ruff)")
            else:
                print("   ⚠️ ruff not installed (pip install ruff)")
                
        elif "typescript" in project_profile or "node" in project_profile:
            # Prettier: Standard TS/JS formatter
            if os.path.exists("package.json"):
                _run_cmd(["npx", "prettier", "--write", ".", "--log-level", "warn"], timeout_s=60)
                print("   ✅ TypeScript formatted (prettier)")
    except subprocess.TimeoutExpired:
        print("   ⚠️ Formatter timed out (continuing)")
    except Exception as e:
        print(f"   ⚠️ Formatter warning: {e}")
    # =========================================================================
    
    config = load_preflight_config()
    test_commands = config.get("test_commands", {})
    timeout = config.get("timeout_seconds", 120)
    
    profile_commands = test_commands.get(project_profile, {})
    
    # Skip if no tests configured or skip flag set
    if not profile_commands or profile_commands.get("skip"):
        return {"passed": True, "message": "No tests configured (skipped)", "output": ""}
    
    # Detect test command based on project files
    cmd = None
    
    # Try unit tests first
    if "unit" in profile_commands:
        # Check if test files exist
        if project_profile.startswith("python"):
            if os.path.exists("tests") or os.path.exists("pytest.ini") or os.path.exists("conftest.py"):
                cmd = profile_commands["unit"]
        elif project_profile.startswith("typescript"):
            if os.path.exists("package.json"):
                # Check if test script exists
                try:
                    with open("package.json", 'r') as f:
                        pkg = json.load(f)
                        if "test" in pkg.get("scripts", {}):
                            cmd = profile_commands["unit"]
                except Exception:
                    pass
    
    if not cmd:
        return {"passed": True, "message": "No test suite detected (skipped)", "output": ""}
    
    print(f"🧪 Pre-Flight: Running '{cmd}'...")
    
    try:
        result = _run_cmd(cmd, timeout_s=timeout)
        
        if result.returncode == 0:
            print("   ✅ Pre-Flight Tests Passed")
            return {
                "passed": True,
                "message": "Tests Passed",
                "output": result.stdout[:500] if result.stdout else ""
            }
        else:
            error_output = result.stderr[:500] if result.stderr else result.stdout[:500]
            print(f"   ❌ Pre-Flight Tests Failed")
            return {
                "passed": False,
                "message": "Tests Failed",
                "error": error_output,
                "exit_code": result.returncode
            }
            
    except subprocess.TimeoutExpired:
        print(f"   ❌ Pre-Flight Tests Timed Out ({timeout}s)")
        return {
            "passed": False,
            "message": f"Tests Timed Out ({timeout}s)",
            "error": "Test execution exceeded timeout"
        }
    except Exception as e:
        return {
            "passed": False,
            "message": f"Test execution error: {str(e)}",
            "error": str(e)
        }

async def run_preflight_tests_async(project_profile: str = None) -> Dict:
    """Async wrapper for run_preflight_tests."""
    return run_preflight_tests(project_profile)

# =============================================================================
# QA AGENT DEFINITIONS (v8.0 - with Intent Check)
# =============================================================================

def get_qa1_definition(model: str, original_task_desc: str = None) -> Dict:
    """
    QA1: The Compiler + Intent Checker
    
    v8.0: Now includes INTENT VERIFICATION (Patch 2)
    """
    intent_check = ""
    if original_task_desc:
        intent_check = f"""
CRITICAL FIRST CHECK - INTENT VERIFICATION:
Before checking code quality, verify the code satisfies this User Request:
"{original_task_desc}"

If the code does NOT fulfill the request, FAIL immediately with issue:
"Intent Mismatch: Code does not fulfill the original task."
"""
    
    return {
        "role": "QA1 (The Compiler)",
        "model": model,
        "personality": "Strict, unforgiving, security-focused. Like a compiler that rejects bad code.",
        "intent_check": intent_check,
        "checks": QA1_CHECKS,
        "fail_on": ["security vulnerability", "type error", "missing auth", "sql injection", "intent mismatch"]
    }

def get_qa2_definition(model: str) -> Dict:
    """
    QA2: The Critic
    Uses Claude Sonnet for nuanced style checks.
    """
    return {
        "role": "QA2 (The Critic)",
        "model": model,
        "personality": "Thoughtful, detail-oriented. Like a senior dev doing code review.",
        "checks": QA2_CHECKS,
        "fail_on": ["spaghetti code", "unreadable", "poor naming", "magic numbers"]
    }

# =============================================================================
# QA EXECUTION
# =============================================================================

async def run_qa_check(llm_client, prompt_def: Dict, code_content: str) -> Dict:
    """
    Executes a single QA pass using the specified model.
    """
    intent_section = prompt_def.get('intent_check', '')
    
    system_msg = f"""
You are {prompt_def['role']}.
{prompt_def.get('personality', '')}

{intent_section}

OBJECTIVE: Review the code below strictly against these criteria:
{json.dumps(prompt_def['checks'], indent=2)}

CRITICAL FAILURES (auto-fail if found):
{json.dumps(prompt_def.get('fail_on', []), indent=2)}

OUTPUT FORMAT (JSON ONLY, no markdown):
{{
    "status": "PASS" | "FAIL",  # SAFETY-ALLOW: status-write
    "score": 0-100,
    "issues": [
        {{"severity": "critical|warning|info", "description": "..."}},
        ...
    ],
    "summary": "One line summary of code quality"
}}

Be thorough but fair. PASS means production-ready. FAIL means needs work.
"""
    
    try:
        response = await llm_client.generate_json(
            model=prompt_def['model'],
            system=system_msg,
            user=f"CODE TO REVIEW:\n```\n{code_content}\n```"
        )
        return response
    except Exception as e:
        return {
            "status": "ERROR",  # SAFETY-ALLOW: status-write
            "issues": [{"severity": "critical", "description": f"QA check failed: {str(e)}"}],
            "score": 0,
            "summary": f"QA execution error: {e}"
        }

# =============================================================================
# MAIN DUAL QA FUNCTION (v8.0)
# =============================================================================

async def perform_dual_qa(
    llm_client,
    code_content: str,
    original_task_desc: str = None,  # v8.0: PATCH 2 - Intent injection
    project_profile: str = None,      # v8.0: PATCH 1 - Profile injection
    context: str = "",
    run_tests: bool = True,           # v8.0: Pre-flight control
    qa1_model: str = None,
    qa2_model: str = None
) -> Dict:
    """
    v8.0 Double-Blind QA Protocol with Pre-Flight Tests + Intent Verification.
    
    NEW in v8.0:
      - Pre-flight tests run before QA
      - Intent verification: QA checks if code fulfills original task
      - Explicit project profile for context
    
    Args:
        llm_client: LLM client with generate_json method
        code_content: The code to review
        original_task_desc: The ORIGINAL task description (for intent check)
        project_profile: Project profile (e.g., "python_backend")
        context: Additional context
        run_tests: Whether to run pre-flight tests
        qa1_model: Override model for QA1
        qa2_model: Override model for QA2
    
    Returns:
        {"status": "APPROVED"|"REJECTED", "issues": [...], ...}  # SAFETY-ALLOW: status-write
    """
    
    # =========================================================================
    # PHASE 1: PRE-FLIGHT TESTS
    # =========================================================================
    
    if run_tests:
        print("🧪 Phase 1: Pre-Flight Tests...")
        test_result = await run_preflight_tests_async(project_profile)
        
        if not test_result["passed"]:
            return {
                "status": "REJECTED",  # SAFETY-ALLOW: status-write
                "phase": "pre-flight",
                "message": f"❌ Pre-Flight Tests Failed: {test_result.get('message')}",
                "issues": [{
                    "severity": "critical",
                    "source": "Pre-Flight",
                    "description": test_result.get("error", "Tests failed")
                }],
                "timestamp": datetime.now().isoformat()
            }
        print(f"   ✅ {test_result.get('message', 'Passed')}")
    
    # =========================================================================
    # PHASE 2: DUAL QA (with Intent Check)
    # =========================================================================
    
    print("⚔️  Phase 2: Engaging Dual QA Protocol...")
    
    # Get models from environment or use provided overrides
    if not qa1_model:
        qa1_model = os.getenv("MODEL_LOGIC_MAX", "gpt-5.1-codex-max")
    if not qa2_model:
        qa2_model = os.getenv("MODEL_CREATIVE_FAST", "claude-sonnet-4-5@20250929")
    
    # Define QA agents (v8.0: QA1 includes intent check)
    qa1_def = get_qa1_definition(qa1_model, original_task_desc)
    qa2_def = get_qa2_definition(qa2_model)
    
    # Add context if provided
    code_with_context = code_content
    if context:
        code_with_context = f"CONTEXT: {context}\n\n{code_content}"
    if project_profile:
        code_with_context = f"PROJECT PROFILE: {project_profile}\n\n{code_with_context}"
    
    # Execute both QA checks in parallel
    print(f"   → QA1 ({qa1_model}): Logic + Intent...")
    print(f"   → QA2 ({qa2_model}): Style...")
    
    results = await asyncio.gather(
        run_qa_check(llm_client, qa1_def, code_with_context),
        run_qa_check(llm_client, qa2_def, code_with_context),
        return_exceptions=True
    )
    
    qa1_res, qa2_res = results
    
    # Handle exceptions
    if isinstance(qa1_res, Exception):
        qa1_res = {"status": "ERROR", "issues": [{"severity": "critical", "description": str(qa1_res)}]}  # SAFETY-ALLOW: status-write
    if isinstance(qa2_res, Exception):
        qa2_res = {"status": "ERROR", "issues": [{"severity": "critical", "description": str(qa2_res)}]}  # SAFETY-ALLOW: status-write
    
    # Evaluate consensus
    qa1_pass = qa1_res.get("status") == "PASS"
    qa2_pass = qa2_res.get("status") == "PASS"
    
    # Build response
    response = {
        "timestamp": datetime.now().isoformat(),
        "phase": "dual-qa",
        "qa1_result": qa1_res,
        "qa2_result": qa2_res,
        "qa1_model": qa1_model,
        "qa2_model": qa2_model,
        "original_task": original_task_desc,
        "project_profile": project_profile,
    }
    
    if qa1_pass and qa2_pass:
        response["status"] = "APPROVED"  # SAFETY-ALLOW: status-write
        response["message"] = "✅ Verified (Intent + Logic + Style)"
        response["issues"] = []
        print("  ✅ CONSENSUS: APPROVED (Pre-Flight + Both QA passed)")
    else:
        response["status"] = "REJECTED"  # SAFETY-ALLOW: status-write
        
        # Aggregate issues with source tags
        issues = []
        if not qa1_pass:
            for issue in qa1_res.get("issues", []):
                if isinstance(issue, dict):
                    issue["source"] = "QA1 (Compiler)"
                    issues.append(issue)
                else:
                    issues.append({"source": "QA1", "description": str(issue), "severity": "warning"})
        
        if not qa2_pass:
            for issue in qa2_res.get("issues", []):
                if isinstance(issue, dict):
                    issue["source"] = "QA2 (Critic)"
                    issues.append(issue)
                else:
                    issues.append({"source": "QA2", "description": str(issue), "severity": "warning"})
        
        response["issues"] = issues
        response["message"] = f"❌ Dual QA Failed ({len(issues)} issues)"
        
        failed_by = []
        if not qa1_pass:
            failed_by.append("QA1")
        if not qa2_pass:
            failed_by.append("QA2")
        
        print(f"  ❌ REJECTED by: {', '.join(failed_by)}")
    
    return response

# =============================================================================
# SYNCHRONOUS WRAPPER
# =============================================================================

def perform_dual_qa_sync(
    llm_client,
    code_content: str,
    original_task_desc: str = None,
    project_profile: str = None,
    context: str = ""
) -> Dict:
    """Synchronous wrapper for perform_dual_qa."""
    return asyncio.run(perform_dual_qa(
        llm_client, code_content, original_task_desc, project_profile, context
    ))

# =============================================================================
# COMPLEXITY ANALYSIS
# =============================================================================

COMPLEXITY_TRIGGERS = [
    "refactor", "rewrite", "migrate", "architecture",
    "redesign", "microservices", "overhaul", "rebuild",
    "from scratch", "entire system", "major change",
    "complete rewrite", "architectural change"
]

def analyze_complexity(user_input: str) -> str:
    """
    Heuristic to detect if task requires The Heavy (Opus).
    """
    input_lower = user_input.lower()
    
    for trigger in COMPLEXITY_TRIGGERS:
        if trigger in input_lower:
            return "high"
    
    if len(user_input.split()) > 150:
        return "high"
    
    file_mentions = sum(1 for ext in [".py", ".ts", ".tsx", ".js", ".jsx"] if ext in input_lower)
    if file_mentions >= 3:
        return "high"
    
    return "normal"

# =============================================================================
# MODEL ROUTING
# =============================================================================

def get_model_for_role(role: str, complexity: str = "normal") -> str:
    """Routes to the optimal model based on role and complexity."""
    logic_max = os.getenv("MODEL_LOGIC_MAX", "gpt-5.1-codex-max")
    creative_fast = os.getenv("MODEL_CREATIVE_FAST", "claude-sonnet-4-5@20250929")
    reasoning_ultra = os.getenv("MODEL_REASONING_ULTRA", "claude-opus-4-5-20251101")
    
    if complexity == "high":
        return reasoning_ultra
    
    role_lower = role.lower()
    
    if role_lower in ["backend", "librarian", "qa1", "commander", "orchestrator", "auditor"]:
        return logic_max
    
    if role_lower in ["frontend", "qa2", "writer", "designer"]:
        return creative_fast
    
    return logic_max
