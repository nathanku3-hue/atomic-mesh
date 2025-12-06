"""
Atomic Mesh v8.4.1 - Spec Linter
On-demand tool to analyze ACTIVE_SPEC.md for ambiguities.

Usage: /refine command in control_panel.ps1
Purpose: Find "Logic Holes" before coding starts, not after.
"""

import os
import json
from typing import Dict

# =============================================================================
# SPEC ANALYSIS
# =============================================================================

AMBIGUITY_PATTERNS = [
    # Common ambiguity indicators in specs
    ("should", "Vague requirement - does this mean 'must' or 'nice to have'?"),
    ("etc", "Incomplete list - what else belongs here?"),
    ("appropriate", "Subjective - what criteria define 'appropriate'?"),
    ("user", "Which user? Admin, Customer, Anonymous?"),
    ("data", "What data exactly? Structure? Format?"),
    ("handle", "How to handle? Error message? Retry? Fail silently?"),
    ("similar", "Similar to what? Be specific."),
    ("various", "Which ones specifically?"),
    ("properly", "What defines 'proper' behavior?"),
    ("somehow", "Implementation unclear."),
]

LOGIC_HOLE_QUESTIONS = [
    "What happens when the operation fails?",
    "What are the edge cases for empty/null input?",
    "Who has permission to do this action?",
    "What's the fallback if the external service is down?",
    "How should conflicts be resolved?",
    "What's the expected response time / timeout?",
    "Is this idempotent? What if called twice?",
]


def analyze_spec_locally(spec_content: str) -> Dict:
    """
    Fast local analysis without LLM.
    Scans for common ambiguity patterns.
    """
    issues = []
    lines = spec_content.split('\n')
    
    for i, line in enumerate(lines, 1):
        line_lower = line.lower()
        for pattern, reason in AMBIGUITY_PATTERNS:
            if pattern in line_lower:
                # Only flag in story/requirement lines
                if '- [ ]' in line or '- [x]' in line or line.strip().startswith('-'):
                    issues.append({
                        "line": i,
                        "pattern": pattern,
                        "reason": reason,
                        "text": line.strip()[:60]
                    })
    
    return {
        "issues_found": len(issues),
        "issues": issues[:10],  # Limit to top 10
        "needs_review": len(issues) > 0
    }


async def analyze_spec_with_llm(llm_client, spec_content: str) -> str:
    """
    Deep analysis using LLM to find semantic logic holes.
    """
    prompt = f"""
ROLE: Senior Product Manager performing Spec Review.

INPUT: Software Specification below.

TASK: Identify the top 3 AMBIGUITIES or LOGIC HOLES that would confuse a developer.

CRITERIA:
- Focus on: "What happens if X fails?", "Data conflicts", "Missing edge cases"
- Ignore minor details, typos, or formatting
- If the spec is solid, output: "✅ Spec is clear. No blocking ambiguities."

OUTPUT FORMAT (plain text, not JSON):
1. [Specific question about unclear requirement] - (Why this blocks implementation)
2. [Another question] - (Why it matters)
3. [Third question if applicable] - (Impact)

If fewer than 3 issues, just list what you find.

---
SPECIFICATION:
{spec_content[:8000]}
---
"""
    
    try:
        response = await llm_client.generate_json(
            model="gpt-5.1-codex-max",
            system="You are a meticulous PM finding spec ambiguities. Be specific and actionable.",
            user=prompt
        )
        
        # Handle various response formats
        if isinstance(response, dict):
            if 'content' in response:
                return response['content']
            elif 'issues' in response:
                return json.dumps(response['issues'], indent=2)
            else:
                return str(response)
        return str(response)
        
    except Exception as e:
        return f"LLM Analysis Error: {e}\n\nFalling back to local analysis..."


def run_spec_linter() -> Dict:
    """
    Main entry point for /refine command.
    Runs local analysis first, then optionally LLM.
    """
    spec_path = os.path.join(os.getcwd(), "docs", "ACTIVE_SPEC.md")
    
    if not os.path.exists(spec_path):
        return {
            "success": False,
            "error": "No ACTIVE_SPEC.md found. Run /init first."
        }
    
    with open(spec_path, 'r', encoding='utf-8') as f:
        spec_content = f.read()
    
    if len(spec_content.strip()) < 50:
        return {
            "success": False,
            "error": "Spec is too short. Add requirements first."
        }
    
    # Run local analysis
    local_result = analyze_spec_locally(spec_content)
    
    return {
        "success": True,
        "spec_length": len(spec_content),
        "local_analysis": local_result,
        "recommendation": "Run with LLM for deeper analysis" if local_result["needs_review"] else "Spec looks clean locally"
    }


# =============================================================================
# SYNC WRAPPER
# =============================================================================

def run_spec_linter_sync() -> str:
    """Synchronous wrapper for command-line usage."""
    result = run_spec_linter()
    
    if not result["success"]:
        return f"❌ {result['error']}"
    
    output = []
    output.append("🧐 SPEC LINTER RESULTS")
    output.append("=" * 40)
    output.append(f"Spec Size: {result['spec_length']} chars")
    output.append("")
    
    local = result["local_analysis"]
    if local["issues_found"] > 0:
        output.append(f"⚠️ Found {local['issues_found']} potential ambiguities:")
        output.append("")
        for issue in local["issues"]:
            output.append(f"  Line {issue['line']}: '{issue['pattern']}' detected")
            output.append(f"    → {issue['reason']}")
            output.append(f"    Text: \"{issue['text']}...\"")
            output.append("")
    else:
        output.append("✅ No obvious ambiguities detected locally.")
    
    output.append("")
    output.append("TIP: Update docs/ACTIVE_SPEC.md to resolve these queries.")
    
    return "\n".join(output)


if __name__ == "__main__":
    print(run_spec_linter_sync())
