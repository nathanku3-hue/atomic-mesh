# C:\Tools\atomic-mesh\librarian_tools.py
# THE LIBRARIAN - File System Safety Tools
# Features: Secret scanning, symlink protection, restore points, reference checking
# v8.4: Path Traversal Guard

import os
import re
import hashlib
import json
import shutil
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# =============================================================================
# v8.4 SECURITY: PATH TRAVERSAL GUARD
# =============================================================================
# CRITICAL: Prevents Path Traversal (../) attacks.
# Without this, a hallucinating agent could escape project_root and
# delete C:\Windows, ~/.ssh, or other critical system files.

def validate_path_safety(target_path: str, project_root: str = None) -> str:
    """
    SECURITY GUARD: Prevents Path Traversal (../) attacks.
    
    Args:
        target_path: The path to validate (can be relative or absolute)
        project_root: The allowed root directory (defaults to cwd)
    
    Returns:
        Absolute path if safe
        
    Raises:
        ValueError: If path escapes project_root (traversal attack detected)
    """
    if project_root is None:
        project_root = os.getcwd()
        
    # Resolve absolute paths
    abs_root = os.path.abspath(project_root)
    
    # Handle both relative and absolute target paths
    if os.path.isabs(target_path):
        abs_target = os.path.abspath(target_path)
    else:
        abs_target = os.path.abspath(os.path.join(abs_root, target_path))
    
    # Check if target is actually inside root
    # os.path.commonpath is the safest cross-platform way
    try:
        common = os.path.commonpath([abs_root, abs_target])
    except ValueError:
        # Happens on Windows if drives are different (C: vs D:)
        raise ValueError(f"🚨 SECURITY BLOCK: Target on different drive '{abs_target}'")

    if common != abs_root:
        raise ValueError(f"🚨 SECURITY BLOCK: Path traversal attempt detected '{target_path}' → '{abs_target}'")
    
    # Additional check: detect explicit .. in path
    if '..' in target_path:
        # Even if commonpath passes, we block explicit .. for safety
        raise ValueError(f"🚨 SECURITY BLOCK: Explicit '..' in path is forbidden '{target_path}'")
        
    return abs_target


def is_path_safe(target_path: str, project_root: str = None) -> bool:
    """
    Non-throwing version of validate_path_safety.
    Returns True if path is safe, False otherwise.
    """
    try:
        validate_path_safety(target_path, project_root)
        return True
    except ValueError:
        return False


# === CONFIGURATION ===

# Secret detection patterns (CRITICAL - blocks operations)
SECRET_PATTERNS = [
    (r"api[_-]?key\s*[:=]\s*['\"][^'\"]+['\"]", "API Key"),
    (r"password\s*[:=]\s*['\"][^'\"]+['\"]", "Password"),
    (r"secret\s*[:=]\s*['\"][^'\"]+['\"]", "Secret"),
    (r"AKIA[A-Z0-9]{16}", "AWS Access Key"),
    (r"sk-[a-zA-Z0-9]{48}", "OpenAI Key"),
    (r"ghp_[a-zA-Z0-9]{36}", "GitHub Token"),
    (r"-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----", "Private Key"),
    (r"mongodb\+srv://[^:]+:[^@]+@", "MongoDB Connection"),
    (r"postgres://[^:]+:[^@]+@", "Postgres Connection"),
    (r"mysql://[^:]+:[^@]+@", "MySQL Connection"),
    (r"Bearer\s+[a-zA-Z0-9\-_.]+", "Bearer Token"),
]

# Precompile secret patterns once to avoid per-call regex compilation
_COMPILED_SECRET_PATTERNS = [
    (re.compile(pattern, re.IGNORECASE), secret_type, pattern)
    for pattern, secret_type in SECRET_PATTERNS
]

# Files that should NEVER be touched
PROTECTED_PATTERNS = [
    ".git/*", ".gitignore", ".env*", "*.key", "*.pem", "*.crt",
    "package.json", "package-lock.json", "requirements.txt",
    "Cargo.toml", "go.mod", "*.lock", "node_modules/*"
]

# TTL cache for recent file scans (reduce churn on dashboard refresh)
_RECENT_CACHE_TTL = int(os.getenv("LIBRARIAN_RECENT_TTL", "13"))  # seconds
_recent_cache = {}

# Safe to delete patterns (with conditions)
TEMP_PATTERNS = [
    r"^temp[_-].*", r"^tmp[_-].*", r"^junk[_-].*",
    r".*\.tmp$", r".*\.temp$", r".*\.bak$",
    r"^debug[_-].*\.log$", r"^test[_-]output.*"
]

# Import patterns for reference checking
IMPORT_PATTERNS = [
    r"import\s+.*{file_name}",
    r"from\s+['\"].*{file_name}['\"]",
    r"require\s*\(\s*['\"].*{file_name}['\"]",
    r"import\s*\(\s*['\"].*{file_name}['\"]",
]

# String literal patterns (dangerous - blocks auto-move)
LITERAL_PATTERNS = [
    r"open\s*\(\s*['\"].*{file_name}['\"]",
    r"src\s*=\s*['\"].*{file_name}['\"]",
    r"href\s*=\s*['\"].*{file_name}['\"]",
    r"path\s*[:=]\s*['\"].*{file_name}['\"]",
    r"file\s*[:=]\s*['\"].*{file_name}['\"]",
    r"\.\/.*{file_name}",
]


# === CORE SAFETY FUNCTIONS ===

def is_symlink_safe(path: str) -> bool:
    """Check if path is a symlink (should be skipped)."""
    return os.path.islink(path)


def get_visited_inodes() -> set:
    """Track visited inodes to prevent infinite loops."""
    return set()


# === PATCH 2: GIT GUARD (Dirty Tree Protection) ===

import subprocess
import logging

logger = logging.getLogger("LibrarianTools")

def check_git_status(project_root: str, ignore_untracked: bool = True) -> Dict:
    """
    Check if git working tree is clean (Patch 2: Git Conflict Fix).
    SECURITY: Uses list arguments to avoid shell injection.
    
    Args:
        project_root: Path to check
        ignore_untracked: If True, only block on Modified files, not new untracked files
    
    Returns:
        {"clean": bool, "modified_files": list, "untracked_files": list, "message": str}
    """
    result = {
        "clean": True,
        "modified_files": [],
        "untracked_files": [],
        "message": "Git working tree is clean"
    }
    
    try:
        # FIX: Use list arguments to avoid shell injection (Issue #2)
        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True,
            text=True,
            cwd=project_root,
            check=False  # Don't raise on non-zero exit
        )
        
        if proc.returncode != 0:
            logger.error(f"Git command failed: {proc.stderr}")
            return {
                "clean": True,
                "modified_files": [],
                "untracked_files": [],
                "message": "Git check skipped (command failed)"
            }
        
        if proc.stdout.strip():
            for line in proc.stdout.strip().split('\n'):
                if not line.strip():
                    continue
                
                status = line[:2]
                file_path = line[3:].strip()
                
                # ?? = untracked, M = modified, A = added, D = deleted
                if status.strip() == '??':
                    result["untracked_files"].append(file_path)
                else:
                    result["modified_files"].append(file_path)
        
        # Determine if we should block
        if result["modified_files"]:
            result["clean"] = False
            result["message"] = f"🔴 {len(result['modified_files'])} modified files (uncommitted changes)"
        elif result["untracked_files"] and not ignore_untracked:
            result["clean"] = False
            result["message"] = f"⚠️ {len(result['untracked_files'])} untracked files"
        
        return result
    
    # FIX: Specific exception handling (Issue #1)
    except FileNotFoundError:
        logger.warning("Git executable not found")
        return {
            "clean": True,
            "modified_files": [],
            "untracked_files": [],
            "message": "Git check skipped (git not found)"
        }
    except PermissionError as e:
        logger.error(f"Permission denied accessing project: {e}")
        return {
            "clean": True,
            "modified_files": [],
            "untracked_files": [],
            "message": f"Git check skipped: permission denied"
        }
    except Exception as e:
        logger.error(f"Unexpected error during git check: {e}")
        return {
            "clean": True,
            "modified_files": [],
            "untracked_files": [],
            "message": f"Git check skipped: {e}"
        }


def check_file_in_git_changes(file_path: str, project_root: str) -> bool:
    """Check if specific file has uncommitted changes. SECURITY: No shell=True."""
    try:
        # FIX: Use list arguments to avoid shell injection (Issue #2)
        result = subprocess.run(
            ["git", "status", "--porcelain", "--", file_path],
            capture_output=True,
            text=True,
            cwd=project_root,
            check=False
        )
        # If output exists and doesn't start with ??, it's modified
        output = result.stdout.strip()
        return bool(output) and not output.startswith('??')
    
    # FIX: Specific exception handling (Issue #1)
    except FileNotFoundError:
        logger.warning("Git executable not found")
        return False
    except Exception as e:
        logger.error(f"Error checking git status for {file_path}: {e}")
        return False


def safe_scan_directory(root_path: str, max_depth: int = 10) -> Dict:
    """
    Safely scan directory with symlink and loop protection.
    CRITICAL: followlinks=False to prevent infinite loops.
    """
    result = {
        "files": [],
        "dirs": [],
        "symlinks_skipped": [],
        "errors": [],
        "total_size": 0
    }
    
    visited_inodes = set()
    current_depth = 0
    
    try:
        for root, dirs, files in os.walk(root_path, followlinks=False):
            # Depth check
            depth = root.replace(root_path, '').count(os.sep)
            if depth > max_depth:
                result["errors"].append(f"Max depth exceeded: {root}")
                dirs[:] = []  # Don't descend further
                continue
            
            # Get inode to detect loops
            try:
                stat_info = os.stat(root)
                inode = stat_info.st_ino
                if inode in visited_inodes:
                    result["errors"].append(f"Loop detected: {root}")
                    dirs[:] = []
                    continue
                visited_inodes.add(inode)
            except OSError as e:
                result["errors"].append(f"Cannot stat: {root} - {e}")
                continue
            
            # Check for symlinks in dirs (skip them)
            for d in dirs[:]:
                dir_path = os.path.join(root, d)
                if is_symlink_safe(dir_path):
                    result["symlinks_skipped"].append(dir_path)
                    dirs.remove(d)
                # Skip node_modules, .git, etc.
                if d in ['.git', 'node_modules', '__pycache__', '.next', 'dist', 'build']:
                    dirs.remove(d)
            
            # Process files
            for f in files:
                file_path = os.path.join(root, f)
                
                if is_symlink_safe(file_path):
                    result["symlinks_skipped"].append(file_path)
                    continue
                
                try:
                    stat = os.stat(file_path)
                    result["files"].append({
                        "path": file_path,
                        "name": f,
                        "size": stat.st_size,
                        "modified": stat.st_mtime,
                        "age_days": (datetime.now().timestamp() - stat.st_mtime) / 86400
                    })
                    result["total_size"] += stat.st_size
                except OSError as e:
                    result["errors"].append(f"Cannot read: {file_path} - {e}")
            
            result["dirs"].append(root)
    
    except Exception as e:
        result["errors"].append(f"Scan failed: {e}")
    
    return result


def calculate_file_hash(file_path: str) -> Optional[str]:
    """Calculate SHA-256 hash for deduplication."""
    try:
        sha256 = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                sha256.update(chunk)
        return sha256.hexdigest()
    except Exception:
        return None


def scan_for_secrets(file_path: str) -> Dict:
    """
    Scan file for potential secrets.
    BLOCKS operation if found.
    """
    result = {
        "blocked": False,
        "secrets_found": [],
        "file": file_path
    }
    
    try:
        # Skip binary files
        with open(file_path, 'rb') as f:
            chunk = f.read(1024)
            if b'\x00' in chunk:
                return result  # Binary file, skip

        # Stream file; short-circuit on first hit to minimize IO on large files
        tail = ""
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                window = tail + line

                for regex, secret_type, pattern in _COMPILED_SECRET_PATTERNS:
                    if not regex.search(window):
                        continue

                    match_count = 0
                    for _ in regex.finditer(window):
                        match_count += 1

                    result["blocked"] = True
                    result["secrets_found"].append({
                        "type": secret_type,
                        "pattern": pattern,
                        "count": match_count or 1
                    })
                    return result

                # Keep a small tail to catch secrets spanning a newline
                tail = window[-2048:] if len(window) > 2048 else window

    except Exception as e:
        result["error"] = str(e)
    
    return result


def check_file_references(file_path: str, project_root: str) -> Dict:
    """
    Find all references to a file in the codebase.
    Distinguishes between imports (auto-updatable) and literals (manual review).
    """
    file_name = os.path.basename(file_path)
    file_stem = os.path.splitext(file_name)[0]

    # Precompile patterns once per invocation
    compiled_imports = [re.compile(p, re.IGNORECASE) for p in (p.format(file_name=file_stem) for p in IMPORT_PATTERNS)]
    compiled_literals = [re.compile(p, re.IGNORECASE) for p in (p.format(file_name=file_name) for p in LITERAL_PATTERNS)]

    result = {
        "file": file_path,
        "import_refs": [],
        "literal_refs": [],
        "can_auto_update": True,
        "total_refs": 0
    }

    skip_dirs = {'.git', 'node_modules', '__pycache__', '.next', '.venv', 'venv', 'dist', 'build', '.tox', '.pytest_cache', '.mypy_cache'}

    try:
        for root, dirs, files in os.walk(project_root, followlinks=False):
            # Skip common non-source dirs
            dirs[:] = [d for d in dirs if d not in skip_dirs]
            
            for f in files:
                if not f.endswith(('.py', '.js', '.ts', '.tsx', '.jsx', '.md', '.html', '.css')):
                    continue

                check_path = os.path.join(root, f)
                if check_path == file_path:
                    continue

                found_import = False
                found_literal = False

                # Quick binary check
                try:
                    with open(check_path, 'rb') as fh:
                        if b'\x00' in fh.read(512):
                            continue
                except Exception:
                    continue

                try:
                    with open(check_path, 'r', encoding='utf-8', errors='ignore') as fh:
                        for line in fh:
                            if not found_import:
                                for regex in compiled_imports:
                                    if regex.search(line):
                                        result["import_refs"].append(check_path)
                                        result["total_refs"] += 1
                                        found_import = True
                                        break

                            if not found_literal:
                                for regex in compiled_literals:
                                    if regex.search(line):
                                        result["literal_refs"].append({
                                            "file": check_path,
                                            "pattern": regex.pattern
                                        })
                                        result["can_auto_update"] = False
                                        result["total_refs"] += 1
                                        found_literal = True
                                        break

                            if found_import and found_literal:
                                break
                except Exception:
                    continue

    except Exception as e:
        result["error"] = str(e)
    
    return result


def is_protected_file(file_path: str) -> bool:
    """Check if file matches protected patterns."""
    from fnmatch import fnmatch
    for pattern in PROTECTED_PATTERNS:
        if fnmatch(file_path, pattern) or fnmatch(os.path.basename(file_path), pattern):
            return True
    return False


def is_temp_file(file_name: str) -> bool:
    """Check if file matches temp/junk patterns."""
    for pattern in TEMP_PATTERNS:
        if re.match(pattern, file_name, re.IGNORECASE):
            return True
    return False


def find_duplicates(files: List[Dict]) -> List[Dict]:
    """Find duplicate files by hash."""
    hash_map = {}
    duplicates = []
    
    for f in files:
        file_hash = calculate_file_hash(f["path"])
        if file_hash:
            if file_hash in hash_map:
                duplicates.append({
                    "original": hash_map[file_hash],
                    "duplicate": f["path"],
                    "hash": file_hash,
                    "size": f["size"]
                })
            else:
                hash_map[file_hash] = f["path"]
    
    return duplicates


# === RESTORE POINT GENERATION ===

def generate_restore_script(manifest_id: str, operations: List[Dict], output_dir: str) -> str:
    """
    Generate a shell script to restore all operations.
    THE UNDO GUARANTEE.
    """
    script_path = os.path.join(output_dir, f"restore_{manifest_id}.sh")
    
    lines = [
        "#!/bin/bash",
        f"# Restore script for manifest: {manifest_id}",
        f"# Generated: {datetime.now().isoformat()}",
        "# Run this script to undo all operations",
        "",
        "set -e  # Exit on error",
        ""
    ]
    
    # Reverse the operations
    for op in reversed(operations):
        if op["action"] == "move":
            lines.append(f'mv "{op["to"]}" "{op["from"]}"')
        elif op["action"] == "delete":
            # For deletes, we need to have backed up the file
            backup_path = op.get("backup_path")
            if backup_path:
                lines.append(f'cp "{backup_path}" "{op["target"]}"')
            else:
                lines.append(f'# WARNING: No backup for deleted file: {op["target"]}')
        elif op["action"] == "archive":
            lines.append(f'mv "{op["to"]}" "{op["from"]}"')
    
    lines.append("")
    lines.append("echo 'Restore complete!'")
    
    # Ensure directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    with open(script_path, 'w') as f:
        f.write('\n'.join(lines))
    
    # Make executable on Unix
    try:
        os.chmod(script_path, 0o755)
    except Exception:
        pass
    
    return script_path


# === MANIFEST GENERATION ===

def generate_manifest(project_root: str, scan_result: Dict) -> Dict:
    """
    Generate a complete manifest of proposed operations.
    """
    manifest_id = f"lib_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    manifest = {
        "manifest_id": manifest_id,
        "created_at": datetime.now().isoformat(),
        "project_root": project_root,
        "risk_level": "LOW",
        "operations": [],
        "blocked_operations": [],
        "stats": {
            "total_files": len(scan_result["files"]),
            "proposed_moves": 0,
            "proposed_deletes": 0,
            "blocked": 0,
            "symlinks_skipped": len(scan_result["symlinks_skipped"])
        }
    }
    
    # Analyze each file
    for f in scan_result["files"]:
        file_path = f["path"]
        file_name = f["name"]
        
        # Skip protected files
        if is_protected_file(file_path):
            continue
        
        # Check for secrets FIRST
        secret_check = scan_for_secrets(file_path)
        if secret_check["blocked"]:
            manifest["blocked_operations"].append({
                "action": "ANY",
                "target": file_path,
                "reason": f"SECRETS DETECTED: {secret_check['secrets_found']}",
                "risk": "CRITICAL"
            })
            manifest["stats"]["blocked"] += 1
            manifest["risk_level"] = "CRITICAL"
            continue
        
        # Check if temp file (candidate for deletion)
        if is_temp_file(file_name) and f["age_days"] > 7:
            ref_check = check_file_references(file_path, project_root)
            if ref_check["total_refs"] == 0:
                manifest["operations"].append({
                    "action": "delete",
                    "target": file_path,
                    "reason": f"Temp file, {f['age_days']:.0f} days old, no references",
                    "risk": "LOW"
                })
                manifest["stats"]["proposed_deletes"] += 1
    
    # Find duplicates
    duplicates = find_duplicates(scan_result["files"])
    for dup in duplicates:
        manifest["operations"].append({
            "action": "delete",
            "target": dup["duplicate"],
            "reason": f"Duplicate of {dup['original']} (hash: {dup['hash'][:8]})",
            "risk": "LOW"
        })
        manifest["stats"]["proposed_deletes"] += 1
    
    # Update risk level
    if manifest["stats"]["blocked"] > 0:
        manifest["risk_level"] = "CRITICAL"
    elif manifest["stats"]["proposed_deletes"] > 5:
        manifest["risk_level"] = "HIGH"
    elif manifest["stats"]["proposed_moves"] + manifest["stats"]["proposed_deletes"] > 0:
        manifest["risk_level"] = "MEDIUM"
    
    return manifest


# === EXECUTION ===

def execute_operation(operation: Dict, backup_dir: str) -> Dict:
    """Execute a single operation with backup."""
    result = {"success": False, "operation": operation}
    
    try:
        if operation["action"] == "move":
            # Ensure target directory exists
            target_dir = os.path.dirname(operation["to"])
            os.makedirs(target_dir, exist_ok=True)
            shutil.move(operation["from"], operation["to"])
            result["success"] = True
        
        elif operation["action"] == "delete":
            # Backup first
            backup_path = os.path.join(backup_dir, os.path.basename(operation["target"]))
            shutil.copy2(operation["target"], backup_path)
            operation["backup_path"] = backup_path
            
            # Move to trash instead of permanent delete
            trash_path = os.path.join(backup_dir, "_trash", os.path.basename(operation["target"]))
            os.makedirs(os.path.dirname(trash_path), exist_ok=True)
            shutil.move(operation["target"], trash_path)
            result["success"] = True
        
        elif operation["action"] == "archive":
            target_dir = os.path.dirname(operation["to"])
            os.makedirs(target_dir, exist_ok=True)
            shutil.move(operation["from"], operation["to"])
            result["success"] = True
    
    except Exception as e:
        result["error"] = str(e)
    
    return result


# === MAIN ENTRY POINT ===

def librarian_full_scan(project_root: str, db_path: str = None, ignore_untracked: bool = True) -> Dict:
    """
    Main entry point for the Librarian.
    Performs full safe scan and generates manifest.
    
    Args:
        project_root: Path to scan
        db_path: Database path for lock checking
        ignore_untracked: If True, allow operations on untracked files (default safe)
    """
    print(f"🔍 Scanning: {project_root}")
    
    # 0. GIT GUARD CHECK (Patch 2: Git Conflict Fix)
    git_status = check_git_status(project_root, ignore_untracked=ignore_untracked)
    if not git_status["clean"]:
        print(f"   {git_status['message']}")
        return {
            "manifest_id": None,
            "blocked": True,
            "reason": "GIT_DIRTY",
            "message": f"🔴 BLOCKED: {git_status['message']}. Commit or stash changes before running Librarian.",
            "modified_files": git_status["modified_files"][:10],  # Show first 10
            "hint": "Run 'git stash' or 'git commit' before Librarian scan"
        }
    print(f"   ✅ Git working tree is clean")
    
    # 1. Get locked files (Patch 1: Active File Lock)
    locked_files = []
    if db_path:
        locked_files = get_locked_files(db_path, project_root)
        print(f"   🔒 {len(locked_files)} files locked by active tasks")
    
    # 2. Safe scan
    scan_result = safe_scan_directory(project_root)
    print(f"   Found {len(scan_result['files'])} files, {len(scan_result['symlinks_skipped'])} symlinks skipped")
    
    # 3. Filter out locked files
    scan_result["files"] = [f for f in scan_result["files"] if f["path"] not in locked_files]
    scan_result["locked_skipped"] = locked_files
    
    # 4. Generate manifest
    manifest = generate_manifest(project_root, scan_result)
    manifest["locked_files"] = locked_files
    print(f"   Risk Level: {manifest['risk_level']}")
    print(f"   Proposed: {manifest['stats']['proposed_moves']} moves, {manifest['stats']['proposed_deletes']} deletes")
    print(f"   Blocked: {manifest['stats']['blocked']}")
    
    return manifest


# === PATCH 1: ACTIVE FILE LOCK ===

def get_locked_files(db_path: str, project_root: str, bypass_cache: bool = False) -> List[str]:
    """
    Get files currently being worked on by Workers/Auditor.
    These files should NOT be touched by the Librarian.
    """
    import sqlite3
    
    locked = set()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # 1. Files in active tasks
        cursor.execute("SELECT files_changed FROM tasks WHERE status='in_progress'")
        for row in cursor.fetchall():
            if row[0]:
                try:
                    files = json.loads(row[0])
                    locked.update(files)
                except json.JSONDecodeError:
                    pass
        
        # 2. Files being audited
        cursor.execute("SELECT files_changed FROM tasks WHERE auditor_status IN ('rejected', 'reviewing')")
        for row in cursor.fetchall():
            if row[0]:
                try:
                    files = json.loads(row[0])
                    locked.update(files)
                except json.JSONDecodeError:
                    pass
        
        conn.close()
    except Exception as e:
        print(f"   ⚠️ Could not check locked files: {e}")
    
    # 3. Files modified in last 5 minutes (safety buffer)
    recent_files = get_recently_modified_files(project_root, minutes=5, bypass_cache=bypass_cache)
    locked.update(recent_files)
    
    return list(locked)


def get_recently_modified_files(project_root: str, minutes: int = 5, bypass_cache: bool = False) -> List[str]:
    """
    Get files modified within the last N minutes.
    Uses a short TTL cache to reduce churn on frequent dashboard refreshes.
    """
    key = (os.path.abspath(project_root), minutes)

    now_ts = time.time()
    cached = _recent_cache.get(key)
    if cached and not bypass_cache:
        age = now_ts - cached["ts"]
        if age <= _RECENT_CACHE_TTL:
            logger.debug(f"recent-files: cached (age={age:.1f}s, ttl={_RECENT_CACHE_TTL}s)")
            return list(cached["files"])

    threshold = now_ts - (minutes * 60)
    recent_set = set()
    skip_dirs = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', '.next', 'dist', 'build'}

    def scan_dir(path: str):
        try:
            with os.scandir(path) as it:
                for entry in it:
                    try:
                        if entry.name in skip_dirs:
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            scan_dir(entry.path)
                            continue
                        if entry.is_file(follow_symlinks=False):
                            if entry.stat(follow_symlinks=False).st_mtime > threshold:
                                recent_set.add(entry.path)
                    except Exception:
                        continue
        except Exception:
            return

    scan_dir(project_root)

    _recent_cache[key] = {"ts": now_ts, "files": recent_set}
    return list(recent_set)


# === PATCH 4: DEEP IMPORT REFACTOR ===

def calculate_relative_depth_change(old_path: str, new_path: str, project_root: str) -> int:
    """Calculate how many levels deeper the file moved."""
    old_rel = os.path.relpath(old_path, project_root)
    new_rel = os.path.relpath(new_path, project_root)
    
    old_depth = old_rel.count(os.sep)
    new_depth = new_rel.count(os.sep)
    
    return new_depth - old_depth


def validate_python_syntax(file_path: str) -> Dict:
    """
    Validate Python file syntax after regex modifications.
    If syntax is broken, return error details.
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            source = f.read()
        
        compile(source, file_path, 'exec')
        return {"valid": True}
    
    except SyntaxError as e:
        return {
            "valid": False,
            "error": str(e),
            "line": e.lineno,
            "offset": e.offset
        }


def fix_internal_imports(moved_file: str, depth_change: int) -> Dict:
    """
    Fix relative imports INSIDE the moved file.
    Includes syntax validation after regex modification.
    """
    result = {
        "file": moved_file,
        "changes": [],
        "errors": [],
        "syntax_valid": True
    }
    
    if depth_change == 0:
        return result  # No change needed
    
    # Only process Python files
    if not moved_file.endswith('.py'):
        return result
    
    try:
        with open(moved_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        original_content = content
        
        if depth_change > 0:
            # Moved DEEPER - need more parent references
            
            # Fix: from . import X -> from .. import X (add dots)
            def add_dots_simple(match):
                dots = match.group(1)
                new_dots = "." * (len(dots) + depth_change)
                return f'from {new_dots} import'
            
            content = re.sub(r'from\s+(\.+)\s+import', add_dots_simple, content)
            
        elif depth_change < 0:
            # Moved SHALLOWER - need fewer parent references
            reduce = abs(depth_change)
            
            def remove_dots(match):
                dots = match.group(1)
                new_dots = max(1, len(dots) - reduce)
                return f'from {"." * new_dots} import'
            
            content = re.sub(r'from\s+(\.+)\s+import', remove_dots, content)
        
        if content != original_content:
            # Write changes
            with open(moved_file, 'w', encoding='utf-8') as f:
                f.write(content)
            
            result["changes"].append(f"Fixed relative imports (depth change: {depth_change})")
            
            # CRITICAL: Validate syntax after regex modification
            syntax_check = validate_python_syntax(moved_file)
            if not syntax_check["valid"]:
                result["syntax_valid"] = False
                result["errors"].append(f"Syntax error after import fix: {syntax_check['error']}")
                
                # Rollback to original
                with open(moved_file, 'w', encoding='utf-8') as f:
                    f.write(original_content)
                result["errors"].append("Rolled back to original content. Manual fix required.")
        
    except Exception as e:
        result["errors"].append(str(e))
    
    return result


def update_import_statement(ref_file: str, old_path: str, new_path: str) -> bool:
    """Update import statement in a file that references the moved file."""
    old_name = os.path.splitext(os.path.basename(old_path))[0]
    new_name = os.path.splitext(os.path.basename(new_path))[0]
    
    # Calculate new module path
    # This is simplified - full implementation would need package analysis
    
    try:
        with open(ref_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Simple replacement (may need enhancement for complex cases)
        new_content = content.replace(
            f'from {old_name}',
            f'from {new_name}'
        ).replace(
            f'import {old_name}',
            f'import {new_name}'
        )
        
        if new_content != content:
            with open(ref_file, 'w', encoding='utf-8') as f:
                f.write(new_content)
            return True
        
        return False
    
    except Exception:
        return False


def execute_move_with_import_fix(from_path: str, to_path: str, project_root: str) -> Dict:
    """
    Move file and fix BOTH external callers AND internal imports.
    Complete bi-directional path repair.
    
    v8.4: Added path traversal guard.
    """
    result = {
        "success": False,
        "external_updates": [],
        "internal_updates": [],
        "errors": [],
        "rollback_needed": False
    }
    
    # v8.4 SECURITY: Validate paths before any operation
    try:
        validate_path_safety(from_path, project_root)
        validate_path_safety(to_path, project_root)
    except ValueError as e:
        result["errors"].append(str(e))
        print(f"    {e}")
        return result
    
    # 1. Check references (external callers)
    refs = check_file_references(from_path, project_root)
    if not refs["can_auto_update"]:
        result["errors"].append("Cannot auto-update: string literals found")
        result["errors"].append(f"Manual review required: {refs['literal_refs']}")
        return result
    
    # 2. Calculate depth change
    depth_change = calculate_relative_depth_change(from_path, to_path, project_root)
    
    # 3. Backup original file
    backup_content = None
    try:
        with open(from_path, 'r', encoding='utf-8') as f:
            backup_content = f.read()
    except OSError:
        pass
    
    # 4. Move the file
    try:
        os.makedirs(os.path.dirname(to_path), exist_ok=True)
        shutil.move(from_path, to_path)
    except Exception as e:
        result["errors"].append(f"Move failed: {e}")
        return result
    
    # 5. Fix external callers
    for ref_file in refs["import_refs"]:
        try:
            if update_import_statement(ref_file, from_path, to_path):
                result["external_updates"].append(ref_file)
        except Exception as e:
            result["errors"].append(f"Failed to update {ref_file}: {e}")
    
    # 6. Fix internal imports INSIDE the moved file (Patch 4)
    internal_result = fix_internal_imports(to_path, depth_change)
    result["internal_updates"] = internal_result["changes"]
    result["errors"].extend(internal_result["errors"])
    
    # 7. Check if syntax broke and we need rollback
    if not internal_result["syntax_valid"]:
        result["rollback_needed"] = True
        result["errors"].append("Import fix broke syntax. Consider manual intervention.")
    
    result["success"] = len(result["errors"]) == 0
    return result


if __name__ == "__main__":
    # Test run
    import sys
    if len(sys.argv) > 1:
        result = librarian_full_scan(sys.argv[1])
        print(json.dumps(result, indent=2))
    else:
        print("Usage: python librarian_tools.py <project_root>")

