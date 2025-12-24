"""
Skill Compactor MCP Server
===========================
Provides compact skill pack access for context-efficient prompts.

Tools:
- get_lane_rules(): Get condensed MUST/AVOID rules
- get_relevant_lessons(): Get lessons matching keywords

Run: python -m vibe_mcp.skill_compactor
"""

import os
import re
import json
from typing import Optional

# Config
SKILLS_DIR = os.getenv("SKILLS_DIR", "skills")
LESSONS_FILE = os.getenv("LESSONS_FILE", "LESSONS_LEARNED.md")


def get_lane_rules(lane: str, max_bullets: int = 12) -> dict:
    """
    MCP Tool: Get condensed MUST/AVOID rules for a lane.
    Returns only the most critical rules to stay within context limits.
    
    Args:
        lane: The worker lane (frontend, backend, security, etc.)
        max_bullets: Maximum number of bullet points to return
        
    Returns:
        {"lane": str, "must": [], "avoid": [], "directive": str}
    """
    skill_file = os.path.join(SKILLS_DIR, f"{lane}.md")
    if not os.path.exists(skill_file):
        skill_file = os.path.join(SKILLS_DIR, "_default.md")
        if not os.path.exists(skill_file):
            return {"lane": lane, "error": "No skill pack found"}
    
    with open(skill_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract sections
    result = {
        "lane": lane,
        "directive": "",
        "must": [],
        "avoid": [],
    }
    
    # Parse DIRECTIVE
    directive_match = re.search(r'## DIRECTIVE\n(.+?)(?=\n##|\n---|\Z)', content, re.DOTALL)
    if directive_match:
        result["directive"] = directive_match.group(1).strip()[:200]
    
    # Parse MUST
    must_match = re.search(r'## MUST.*?\n((?:- .+\n?)+)', content)
    if must_match:
        bullets = re.findall(r'- (.+)', must_match.group(1))
        result["must"] = bullets[:max_bullets // 2]
    
    # Parse AVOID
    avoid_match = re.search(r'## AVOID.*?\n((?:- .+\n?)+)', content)
    if avoid_match:
        bullets = re.findall(r'- (.+)', avoid_match.group(1))
        result["avoid"] = bullets[:max_bullets // 2]
    
    return result


def get_relevant_lessons(keywords: list, limit: int = 5) -> dict:
    """
    MCP Tool: Get lessons matching keywords.
    Searches LESSONS_LEARNED.md for relevant entries.
    
    Args:
        keywords: List of keywords to search for
        limit: Maximum lessons to return
        
    Returns:
        {"lessons": [{"date": str, "category": str, "content": str}]}
    """
    if not os.path.exists(LESSONS_FILE):
        return {"lessons": [], "error": "No lessons file found"}
    
    with open(LESSONS_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Parse lessons
    lessons = []
    pattern = r'\*\*\[(\d{4}-\d{2}-\d{2})\]\s*([^:]+):\*\*\s*(.+)'
    for match in re.finditer(pattern, content):
        date, category, text = match.groups()
        lessons.append({
            "date": date,
            "category": category.strip(),
            "content": text.strip()
        })
    
    # Filter by keywords
    if keywords:
        filtered = []
        for lesson in lessons:
            for kw in keywords:
                if kw.lower() in lesson["content"].lower() or kw.lower() in lesson["category"].lower():
                    filtered.append(lesson)
                    break
        lessons = filtered
    
    return {"lessons": lessons[:limit]}


def format_compact_context(lane: str, keywords: Optional[list] = None) -> str:
    """
    Utility: Generate a compact context string for task injection.
    Combines lane rules + relevant lessons.
    """
    rules = get_lane_rules(lane)
    lessons = get_relevant_lessons(keywords or [lane], limit=3)
    
    lines = [f"## {lane.upper()} RULES (Compact)"]
    
    if rules.get("directive"):
        lines.append(f"Role: {rules['directive']}")
    
    if rules.get("must"):
        lines.append("\nMUST:")
        for item in rules["must"]:
            lines.append(f"  ✓ {item}")
    
    if rules.get("avoid"):
        lines.append("\nAVOID:")
        for item in rules["avoid"]:
            lines.append(f"  ✗ {item}")
    
    if lessons.get("lessons"):
        lines.append("\nLESSONS:")
        for l in lessons["lessons"]:
            lines.append(f"  • [{l['category']}] {l['content']}")
    
    return "\n".join(lines)


# MCP Server Registration (for Codex CLI)
MCP_TOOLS = {
    "get_lane_rules": {
        "description": "Get condensed MUST/AVOID rules for a lane",
        "parameters": {
            "lane": {"type": "string", "required": True},
            "max_bullets": {"type": "integer", "default": 12}
        }
    },
    "get_relevant_lessons": {
        "description": "Get lessons matching keywords",
        "parameters": {
            "keywords": {"type": "array", "items": {"type": "string"}, "required": True},
            "limit": {"type": "integer", "default": 5}
        }
    }
}


if __name__ == "__main__":
    # Demo
    print("=== Skill Compactor MCP ===\n")
    
    print("Frontend Rules:")
    print(json.dumps(get_lane_rules("frontend"), indent=2))
    
    print("\nRelevant Lessons (auth):")
    print(json.dumps(get_relevant_lessons(["auth", "security"]), indent=2))
    
    print("\nCompact Context:")
    print(format_compact_context("frontend"))
