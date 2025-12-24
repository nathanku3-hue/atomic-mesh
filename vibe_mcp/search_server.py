"""
Search MCP Server
=================
Provides code search capabilities using ripgrep.

Tools:
- search_code(): Search for patterns in codebase
- find_definition(): Find function/class definitions

Run: python -m vibe_mcp.search_server
"""

import subprocess
import os
import re
from typing import Optional


def run_rg(args: list, cwd: Optional[str] = None) -> dict:
    """Execute ripgrep command and return structured result."""
    try:
        # Try ripgrep first, fall back to grep
        result = subprocess.run(
            ["rg"] + args,
            cwd=cwd or os.getcwd(),
            capture_output=True,
            text=True,
            timeout=30
        )
        return {
            "success": result.returncode in [0, 1],  # 1 = no matches
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip() if result.returncode > 1 else None
        }
    except FileNotFoundError:
        # Fallback to grep on Windows
        try:
            result = subprocess.run(
                ["findstr", "/s", "/n"] + args,
                cwd=cwd or os.getcwd(),
                capture_output=True,
                text=True,
                timeout=30
            )
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout.strip(),
                "stderr": result.stderr.strip() if result.returncode != 0 else None,
                "fallback": "findstr"
            }
        except Exception as e:
            return {"success": False, "error": f"No search tool available: {e}"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def search_code(
    pattern: str,
    file_pattern: Optional[str] = None,
    max_results: int = 20,
    cwd: Optional[str] = None
) -> dict:
    """
    MCP Tool: Search for patterns in codebase.
    
    Args:
        pattern: Regex pattern to search for
        file_pattern: Glob pattern for files (e.g., "*.py")
        max_results: Maximum results to return
        
    Returns:
        {
            "matches": [{"file": str, "line": int, "content": str}],
            "total": int
        }
    """
    args = ["-n", "--max-count", str(max_results)]
    
    if file_pattern:
        args.extend(["-g", file_pattern])
    
    args.append(pattern)
    
    result = run_rg(args, cwd)
    
    if not result["success"]:
        return result
    
    matches = []
    for line in result["stdout"].split("\n"):
        if line:
            # Parse ripgrep output: file:line:content
            match = re.match(r"([^:]+):(\d+):(.+)", line)
            if match:
                matches.append({
                    "file": match.group(1),
                    "line": int(match.group(2)),
                    "content": match.group(3).strip()[:200]  # Truncate long lines
                })
    
    return {
        "matches": matches[:max_results],
        "total": len(matches)
    }


def find_definition(
    name: str,
    definition_type: str = "function",
    cwd: Optional[str] = None
) -> dict:
    """
    MCP Tool: Find function/class definitions.
    
    Args:
        name: Name of function/class to find
        definition_type: "function" or "class"
        
    Returns:
        {"definitions": [{"file": str, "line": int, "signature": str}]}
    """
    # Build pattern based on type and common languages
    patterns = []
    
    if definition_type == "function":
        patterns = [
            f"def {name}\\s*\\(",           # Python
            f"function {name}\\s*\\(",      # JavaScript
            f"(async )?function {name}",    # JS async
            f"const {name}\\s*=\\s*\\(",    # JS arrow
            f"fn {name}\\s*\\(",            # Rust
        ]
    elif definition_type == "class":
        patterns = [
            f"class {name}[:\\(]",          # Python/TypeScript
            f"class {name}\\s*{{",          # JavaScript
            f"struct {name}\\s*{{",         # Rust/Go
            f"interface {name}",            # TypeScript
        ]
    
    all_matches = []
    for pattern in patterns:
        result = search_code(pattern, max_results=5, cwd=cwd)
        if result.get("matches"):
            all_matches.extend(result["matches"])
    
    # Dedupe
    seen = set()
    definitions = []
    for m in all_matches:
        key = f"{m['file']}:{m['line']}"
        if key not in seen:
            seen.add(key)
            definitions.append({
                "file": m["file"],
                "line": m["line"],
                "signature": m["content"]
            })
    
    return {"definitions": definitions[:10]}


def find_usages(
    name: str,
    file_pattern: Optional[str] = None,
    cwd: Optional[str] = None
) -> dict:
    """
    MCP Tool: Find all usages of a symbol.
    
    Args:
        name: Symbol name to search for
        file_pattern: Limit to specific file types
        
    Returns:
        {"usages": [{"file": str, "line": int, "context": str}]}
    """
    result = search_code(f"\\b{name}\\b", file_pattern=file_pattern, max_results=30, cwd=cwd)
    
    if not result.get("matches"):
        return {"usages": [], "total": 0}
    
    usages = [
        {"file": m["file"], "line": m["line"], "context": m["content"]}
        for m in result["matches"]
    ]
    
    return {"usages": usages, "total": len(usages)}


# MCP Server Registration
MCP_TOOLS = {
    "search_code": {
        "description": "Search for patterns in codebase",
        "parameters": {
            "pattern": {"type": "string", "required": True},
            "file_pattern": {"type": "string", "required": False},
            "max_results": {"type": "integer", "default": 20}
        }
    },
    "find_definition": {
        "description": "Find function/class definitions",
        "parameters": {
            "name": {"type": "string", "required": True},
            "definition_type": {"type": "string", "enum": ["function", "class"], "default": "function"}
        }
    },
    "find_usages": {
        "description": "Find all usages of a symbol",
        "parameters": {
            "name": {"type": "string", "required": True},
            "file_pattern": {"type": "string", "required": False}
        }
    }
}


if __name__ == "__main__":
    import json
    print("=== Search MCP Server ===\n")
    
    print("Search for 'def sanitize':")
    print(json.dumps(search_code("def sanitize", "*.py"), indent=2))
    
    print("\nFind definitions of 'get_db':")
    print(json.dumps(find_definition("get_db"), indent=2))
