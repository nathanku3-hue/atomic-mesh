"""
MCP Package Init
================
Vibe Coding MCP Servers for Codex integration.

Available servers:
- skill_compactor: Compact skill pack access
- git_server: Git operations
- search_server: Code search

Usage:
    python -m vibe_mcp.skill_compactor
    python -m vibe_mcp.git_server
    python -m vibe_mcp.search_server
"""

from .skill_compactor import get_lane_rules, get_relevant_lessons, format_compact_context
from .git_server import git_status, git_diff, git_commit, git_log
from .search_server import search_code, find_definition, find_usages

__all__ = [
    # Skill Compactor
    "get_lane_rules",
    "get_relevant_lessons", 
    "format_compact_context",
    
    # Git
    "git_status",
    "git_diff",
    "git_commit",
    "git_log",
    
    # Search
    "search_code",
    "find_definition",
    "find_usages",
]
