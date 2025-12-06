"""
Atomic Mesh v7.8 - Dual QA Protocol
The "Zero-Spaghetti" Code Quality System

This module implements the Double-Blind QA Protocol:
  QA1 (The Compiler): Hard logic - security, types, architecture
  QA2 (The Critic): Soft logic - readability, style, spaghetti detection

Code is only APPROVED when BOTH QA agents pass.
This creates a "Swiss Cheese" defense - what one misses, the other catches.
"""

import os
import json
import asyncio
from typing import Dict, List, Optional
from datetime import datetime

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
    "Is variable naming descriptive (not x, temp, data)?",
    "Is function length reasonable (< 50 lines)?",
    "Is code DRY (Don't Repeat Yourself)?",
    "Are nested loops < 3 levels deep (spaghetti detector)?",
    "Is code readable by a junior developer?",
    "Are magic numbers explained with constants?",
    "Are complex sections commented?",
    "Does the code 'smell' clean?",
]

# =============================================================================
# QA AGENT DEFINITIONS
# =============================================================================

def get_qa1_definition(model: str) -> Dict:
    """
    QA1: The Compiler
    Uses GPT-5.1/GPT-4o for hard logic checks.
    """
    return {
        "role": "QA1 (The Compiler)",
        "model": model,
        "personality": "Strict, unforgiving, security-focused. Like a compiler that rejects bad code.",
        "checks": QA1_CHECKS,
        "fail_on": ["security vulnerability", "type error", "missing auth", "sql injection"]
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
    
    Args:
        llm_client: The LLM client with generate_json method
        prompt_def: QA agent definition (role, model, checks)
        code_content: The code to review
    
    Returns:
        {"status": "PASS"|"FAIL", "issues": [...], "score": 0-100}
    """
    system_msg = f"""
You are {prompt_def['role']}.
{prompt_def.get('personality', '')}

OBJECTIVE: Review the code below strictly against these criteria:
{json.dumps(prompt_def['checks'], indent=2)}

CRITICAL FAILURES (auto-fail if found):
{json.dumps(prompt_def.get('fail_on', []), indent=2)}

OUTPUT FORMAT (JSON ONLY, no markdown):
{{
    "status": "PASS" | "FAIL",
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
        # This would call the actual LLM
        # For now, return a mock response structure
        response = await llm_client.generate_json(
            model=prompt_def['model'],
            system=system_msg,
            user=f"CODE TO REVIEW:\n```\n{code_content}\n```"
        )
        return response
    except Exception as e:
        return {
            "status": "ERROR",
            "issues": [{"severity": "critical", "description": f"QA check failed: {str(e)}"}],
            "score": 0,
            "summary": f"QA execution error: {e}"
        }

async def perform_dual_qa(
    llm_client,
    code_content: str,
    context: str = "",
    qa1_model: str = None,
    qa2_model: str = None
) -> Dict:
    """
    The v7.8 Double-Blind QA Protocol.
    
    Runs code through both QA1 (hard logic) and QA2 (soft style) in parallel.
    Code is APPROVED only if BOTH pass.
    
    Args:
        llm_client: LLM client with generate_json method
        code_content: The code to review
        context: Optional context (file type, purpose, etc.)
        qa1_model: Override model for QA1
        qa2_model: Override model for QA2
    
    Returns:
        {
            "status": "APPROVED"|"REJECTED",
            "qa1_result": {...},
            "qa2_result": {...},
            "issues": [...],
            "timestamp": "..."
        }
    """
    print("⚔️  Engaging Dual QA Protocol...")
    
    # Get models from environment or use provided overrides
    if not qa1_model:
        qa1_model = os.getenv("MODEL_LOGIC_MAX", "gpt-4o")
    if not qa2_model:
        qa2_model = os.getenv("MODEL_CREATIVE_FAST", "claude-3-5-sonnet-20240620")
    
    # Define the QA agents
    qa1_def = get_qa1_definition(qa1_model)
    qa2_def = get_qa2_definition(qa2_model)
    
    # Add context if provided
    if context:
        code_with_context = f"CONTEXT: {context}\n\n{code_content}"
    else:
        code_with_context = code_content
    
    # Execute both QA checks in parallel
    print(f"  → QA1 ({qa1_model}): Checking hard logic...")
    print(f"  → QA2 ({qa2_model}): Checking style...")
    
    results = await asyncio.gather(
        run_qa_check(llm_client, qa1_def, code_with_context),
        run_qa_check(llm_client, qa2_def, code_with_context),
        return_exceptions=True
    )
    
    qa1_res, qa2_res = results
    
    # Handle exceptions
    if isinstance(qa1_res, Exception):
        qa1_res = {"status": "ERROR", "issues": [{"severity": "critical", "description": str(qa1_res)}]}
    if isinstance(qa2_res, Exception):
        qa2_res = {"status": "ERROR", "issues": [{"severity": "critical", "description": str(qa2_res)}]}
    
    # Evaluate consensus
    qa1_pass = qa1_res.get("status") == "PASS"
    qa2_pass = qa2_res.get("status") == "PASS"
    
    # Build response
    response = {
        "timestamp": datetime.now().isoformat(),
        "qa1_result": qa1_res,
        "qa2_result": qa2_res,
        "qa1_model": qa1_model,
        "qa2_model": qa2_model,
    }
    
    if qa1_pass and qa2_pass:
        response["status"] = "APPROVED"
        response["message"] = "✅ Logic & Style Verified by Dual QA"
        response["issues"] = []
        print("  ✅ CONSENSUS: APPROVED (Both QA passed)")
    else:
        response["status"] = "REJECTED"
        
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
# SYNCHRONOUS WRAPPER (for non-async contexts)
# =============================================================================

def perform_dual_qa_sync(llm_client, code_content: str, context: str = "") -> Dict:
    """
    Synchronous wrapper for perform_dual_qa.
    Use this in non-async contexts.
    """
    return asyncio.run(perform_dual_qa(llm_client, code_content, context))

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
    
    Returns:
        "high" - Use Opus for complex architectural tasks
        "normal" - Use standard model routing
    """
    input_lower = user_input.lower()
    
    # Check for trigger phrases
    for trigger in COMPLEXITY_TRIGGERS:
        if trigger in input_lower:
            return "high"
    
    # Word count heuristic (very long prompts often mean complex tasks)
    if len(user_input.split()) > 150:
        return "high"
    
    # Multiple file mentions often mean complex refactoring
    file_mentions = sum(1 for ext in [".py", ".ts", ".tsx", ".js", ".jsx"] if ext in input_lower)
    if file_mentions >= 3:
        return "high"
    
    return "normal"

# =============================================================================
# MODEL ROUTING (Standalone version)
# =============================================================================

def get_model_for_role(role: str, complexity: str = "normal") -> str:
    """
    Routes to the optimal model based on role and complexity.
    
    Args:
        role: Agent role (backend, frontend, qa1, qa2, etc.)
        complexity: Task complexity ("normal" or "high")
    
    Returns:
        Model identifier string
    """
    # Environment-based configuration
    logic_max = os.getenv("MODEL_LOGIC_MAX", "gpt-4o")
    creative_fast = os.getenv("MODEL_CREATIVE_FAST", "claude-3-5-sonnet-20240620")
    reasoning_ultra = os.getenv("MODEL_REASONING_ULTRA", "claude-3-opus-20240229")
    
    # The Heavy for complex tasks
    if complexity == "high":
        return reasoning_ultra
    
    # Role-based routing
    role_lower = role.lower()
    
    # Logic Cluster (GPT)
    if role_lower in ["backend", "librarian", "qa1", "commander", "orchestrator", "auditor"]:
        return logic_max
    
    # Creative Cluster (Claude Sonnet)
    if role_lower in ["frontend", "qa2", "writer", "designer"]:
        return creative_fast
    
    # Default fallback
    return logic_max
