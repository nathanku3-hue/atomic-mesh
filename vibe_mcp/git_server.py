"""
Git MCP Server
==============
Provides structured Git operations for Vibe Coding workers.

Tools:
- git_status(): Get repo status
- git_diff(): Get file diffs
- git_commit(): Create atomic commit

Run: python -m vibe_mcp.git_server
"""

import subprocess
import os
from typing import Optional


def run_git(args: list, cwd: Optional[str] = None) -> dict:
    """Execute git command and return structured result."""
    try:
        result = subprocess.run(
            ["git"] + args,
            cwd=cwd or os.getcwd(),
            capture_output=True,
            text=True,
            timeout=30
        )
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip() if result.returncode != 0 else None
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Git command timed out"}
    except Exception as e:
        return {"success": False, "error": str(e)}


def git_status(cwd: Optional[str] = None) -> dict:
    """
    MCP Tool: Get repository status.
    
    Returns:
        {
            "branch": str,
            "staged": [files],
            "modified": [files],
            "untracked": [files],
            "clean": bool
        }
    """
    result = run_git(["status", "--porcelain", "-b"], cwd)
    if not result["success"]:
        return result
    
    lines = result["stdout"].split("\n")
    
    status = {
        "branch": "",
        "staged": [],
        "modified": [],
        "untracked": [],
        "clean": True
    }
    
    for line in lines:
        if line.startswith("##"):
            # Branch info
            branch_info = line[3:].split("...")[0]
            status["branch"] = branch_info
        elif line:
            status["clean"] = False
            code = line[:2]
            filename = line[3:]
            
            if code[0] in "MADRC":
                status["staged"].append(filename)
            if code[1] == "M":
                status["modified"].append(filename)
            elif code == "??":
                status["untracked"].append(filename)
    
    return status


def git_diff(file: Optional[str] = None, staged: bool = False, cwd: Optional[str] = None) -> dict:
    """
    MCP Tool: Get diff for files.
    
    Args:
        file: Specific file to diff (optional)
        staged: If True, show staged changes
        
    Returns:
        {"diff": str, "files": [str], "lines_added": int, "lines_removed": int}
    """
    args = ["diff", "--stat"]
    if staged:
        args.append("--staged")
    if file:
        args.append(file)
    
    result = run_git(args, cwd)
    if not result["success"]:
        return result
    
    # Get full diff too
    full_args = ["diff"]
    if staged:
        full_args.append("--staged")
    if file:
        full_args.append(file)
    
    full_result = run_git(full_args, cwd)
    
    # Parse stats
    lines_added = 0
    lines_removed = 0
    files = []
    
    for line in result["stdout"].split("\n"):
        if "|" in line:
            parts = line.split("|")
            files.append(parts[0].strip())
        if "insertion" in line:
            match = __import__("re").search(r"(\d+) insertion", line)
            if match:
                lines_added = int(match.group(1))
        if "deletion" in line:
            match = __import__("re").search(r"(\d+) deletion", line)
            if match:
                lines_removed = int(match.group(1))
    
    return {
        "diff": full_result.get("stdout", "")[:5000],  # Truncate large diffs
        "files": files,
        "lines_added": lines_added,
        "lines_removed": lines_removed
    }


def git_commit(message: str, files: Optional[list] = None, cwd: Optional[str] = None) -> dict:
    """
    MCP Tool: Create atomic commit.
    
    Args:
        message: Commit message (should follow feat(lane): description format)
        files: Specific files to commit (optional, defaults to all staged)
        
    Returns:
        {"success": bool, "commit_hash": str, "message": str}
    """
    # Stage files if specified
    if files:
        for f in files:
            stage_result = run_git(["add", f], cwd)
            if not stage_result["success"]:
                return {"success": False, "error": f"Failed to stage {f}"}
    
    # Commit
    result = run_git(["commit", "-m", message], cwd)
    
    if not result["success"]:
        if "nothing to commit" in result.get("stderr", "") or "nothing to commit" in result.get("stdout", ""):
            return {"success": False, "error": "Nothing to commit"}
        return result
    
    # Get commit hash
    hash_result = run_git(["rev-parse", "--short", "HEAD"], cwd)
    
    return {
        "success": True,
        "commit_hash": hash_result.get("stdout", "unknown"),
        "message": message
    }


def git_log(n: int = 5, cwd: Optional[str] = None) -> dict:
    """
    MCP Tool: Get recent commits.
    
    Args:
        n: Number of commits to show
        
    Returns:
        {"commits": [{"hash": str, "message": str, "author": str, "date": str}]}
    """
    result = run_git(["log", f"-{n}", "--pretty=format:%h|%s|%an|%ar"], cwd)
    if not result["success"]:
        return result
    
    commits = []
    for line in result["stdout"].split("\n"):
        if line:
            parts = line.split("|")
            if len(parts) >= 4:
                commits.append({
                    "hash": parts[0],
                    "message": parts[1],
                    "author": parts[2],
                    "date": parts[3]
                })
    
    return {"commits": commits}


# MCP Server Registration
MCP_TOOLS = {
    "git_status": {
        "description": "Get repository status (branch, staged, modified files)",
        "parameters": {}
    },
    "git_diff": {
        "description": "Get diff for files",
        "parameters": {
            "file": {"type": "string", "required": False},
            "staged": {"type": "boolean", "default": False}
        }
    },
    "git_commit": {
        "description": "Create atomic commit",
        "parameters": {
            "message": {"type": "string", "required": True},
            "files": {"type": "array", "items": {"type": "string"}, "required": False}
        }
    },
    "git_log": {
        "description": "Get recent commits",
        "parameters": {
            "n": {"type": "integer", "default": 5}
        }
    }
}


if __name__ == "__main__":
    import json
    print("=== Git MCP Server ===\n")
    
    print("Status:")
    print(json.dumps(git_status(), indent=2))
    
    print("\nRecent commits:")
    print(json.dumps(git_log(3), indent=2))
