"""
Atomic Mesh v8.0 - Product Owner Agent
The Scribe - Handles spec updates and changelog maintenance.

CRITICAL: Only runs AFTER QA approves code (Patch 3).
This prevents "Hearsay" updates where specs are updated based on false claims.
"""

import os
import json
from datetime import datetime
from typing import Dict, List, Optional

# =============================================================================
# CONFIGURATION
# =============================================================================

CHANGELOG_HEADER = """# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

"""

MAJOR_FEATURE_KEYWORDS = [
    "feature", "feat", "add", "implement", "create", "build",
    "new", "integrate", "support", "enable"
]

# =============================================================================
# SPEC SYNC (Check off completed stories)
# =============================================================================

def find_matching_story(spec_content: str, task_desc: str) -> Optional[str]:
    """
    Finds an unchecked user story that matches the completed task.
    Uses fuzzy matching on keywords.
    
    Args:
        spec_content: The full ACTIVE_SPEC.md content
        task_desc: The description of the completed task
    
    Returns:
        The matching unchecked story line, or None
    """
    task_lower = task_desc.lower()
    keywords = [w for w in task_lower.split() if len(w) > 3]
    
    lines = spec_content.split('\n')
    best_match = None
    best_score = 0
    
    for line in lines:
        # Only consider unchecked stories
        if "- [ ]" not in line:
            continue
        
        line_lower = line.lower()
        
        # Score by keyword matches
        score = sum(1 for kw in keywords if kw in line_lower)
        
        if score > best_score:
            best_score = score
            best_match = line
    
    # Only return if we have at least 2 keyword matches
    if best_score >= 2:
        return best_match
    
    return None

def check_off_story(spec_content: str, story_line: str) -> str:
    """
    Marks a user story as completed by replacing [ ] with [x].
    """
    checked_line = story_line.replace("- [ ]", "- [x]")
    return spec_content.replace(story_line, checked_line)

def update_active_spec(task_desc: str) -> Dict:
    """
    Finds and checks off the matching story in ACTIVE_SPEC.md.
    
    Returns:
        {"updated": bool, "story": str or None}
    """
    spec_path = os.path.join(os.getcwd(), "docs", "ACTIVE_SPEC.md")
    
    if not os.path.exists(spec_path):
        return {"updated": False, "reason": "ACTIVE_SPEC.md not found"}
    
    with open(spec_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find matching unchecked story
    story = find_matching_story(content, task_desc)
    
    if story:
        updated_content = check_off_story(content, story)
        
        with open(spec_path, 'w', encoding='utf-8') as f:
            f.write(updated_content)
        
        print(f"   ✅ Spec Updated: {story[:60]}...")
        return {"updated": True, "story": story}
    
    return {"updated": False, "reason": "No matching story found"}

# =============================================================================
# CHANGELOG (Document major features)
# =============================================================================

def is_major_feature(task_desc: str) -> bool:
    """
    Determines if a task represents a major feature worth documenting.
    """
    task_lower = task_desc.lower()
    return any(kw in task_lower for kw in MAJOR_FEATURE_KEYWORDS)

def format_changelog_entry(task_desc: str, category: str = "Added") -> str:
    """
    Formats a task description into a changelog entry.
    """
    date_str = datetime.now().strftime("%Y-%m-%d")
    
    # Clean up task description
    clean_desc = task_desc.strip()
    if clean_desc.endswith('.'):
        clean_desc = clean_desc[:-1]
    
    return f"### {category}\n- {clean_desc} ({date_str})\n\n"

def update_changelog(task_desc: str) -> Dict:
    """
    Adds an entry to CHANGELOG.md for major features.
    
    Returns:
        {"updated": bool, "entry": str or None}
    """
    if not is_major_feature(task_desc):
        return {"updated": False, "reason": "Not a major feature"}
    
    changelog_path = os.path.join(os.getcwd(), "CHANGELOG.md")
    entry = format_changelog_entry(task_desc)
    
    if os.path.exists(changelog_path):
        with open(changelog_path, 'r', encoding='utf-8') as f:
            existing = f.read()
        
        # Insert after header
        if "## [Unreleased]" in existing:
            # Insert under Unreleased section
            parts = existing.split("## [Unreleased]", 1)
            if len(parts) == 2:
                new_content = parts[0] + "## [Unreleased]\n\n" + entry + parts[1].lstrip()
            else:
                new_content = existing + "\n" + entry
        else:
            # Add Unreleased section
            new_content = existing.rstrip() + "\n\n## [Unreleased]\n\n" + entry
    else:
        # Create new changelog
        new_content = CHANGELOG_HEADER + "## [Unreleased]\n\n" + entry
    
    with open(changelog_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print(f"   📝 Changelog Updated: {task_desc[:50]}...")
    return {"updated": True, "entry": entry}

# =============================================================================
# v8.6 CONVENTIONAL COMMITS (Vibe Coding Norm)
# =============================================================================
# Git log should read like a history book.
# Format: type(scope): subject

COMMIT_TYPE_PATTERNS = [
    # (keywords, type, scope_guess)
    (["feat", "feature", "add", "implement", "create", "build", "new"], "feat", None),
    (["fix", "bug", "patch", "resolve", "correct"], "fix", None),
    (["doc", "docs", "readme", "comment"], "docs", None),
    (["style", "css", "ui", "format", "spacing"], "style", "ui"),
    (["refactor", "restructure", "reorganize", "clean"], "refactor", None),
    (["perf", "performance", "speed", "optimize"], "perf", None),
    (["test", "spec", "coverage"], "test", None),
    (["chore", "config", "setup", "upgrade", "version"], "chore", None),
]

def detect_commit_type(task_desc: str) -> tuple:
    """
    Detects the semantic commit type from task description.
    Returns: (type, scope)
    """
    task_lower = task_desc.lower()
    
    for keywords, commit_type, scope_guess in COMMIT_TYPE_PATTERNS:
        if any(kw in task_lower for kw in keywords):
            # Try to extract scope from common patterns
            scope = scope_guess
            if "auth" in task_lower:
                scope = "auth"
            elif "api" in task_lower:
                scope = "api"
            elif "db" in task_lower or "database" in task_lower:
                scope = "db"
            elif "ui" in task_lower or "component" in task_lower:
                scope = "ui"
            return commit_type, scope
    
    return "chore", None

def generate_conventional_commit(task_desc: str, files_changed: list = None) -> str:
    """
    Generates a Conventional Commit message from task description.
    
    Format: type(scope): subject
    Types: feat, fix, docs, style, refactor, perf, test, chore
    
    Args:
        task_desc: The task description
        files_changed: Optional list of changed files (for scope detection)
    
    Returns:
        Conventional commit message string
    
    Example:
        "Add JWT login support" → "feat(auth): add jwt login support"
    """
    commit_type, scope = detect_commit_type(task_desc)
    
    # Try to infer scope from file paths if not detected
    if not scope and files_changed:
        for f in files_changed:
            if "auth" in f.lower():
                scope = "auth"
                break
            elif "api" in f.lower():
                scope = "api"
                break
            elif "component" in f.lower() or "ui" in f.lower():
                scope = "ui"
                break
    
    # Clean up subject (lowercase, no period)
    subject = task_desc.strip()
    if subject.endswith('.'):
        subject = subject[:-1]
    
    # Remove common prefixes that are redundant with type
    for prefix in ["add", "fix", "implement", "create", "build", "update"]:
        if subject.lower().startswith(prefix + " "):
            subject = subject[len(prefix):].strip()
            break
    
    # Lowercase subject per convention
    subject = subject[0].lower() + subject[1:] if subject else ""
    
    # Format
    if scope:
        return f"{commit_type}({scope}): {subject}"
    else:
        return f"{commit_type}: {subject}"


# =============================================================================
# MAIN SYNC FUNCTION
# =============================================================================

def run_product_sync(task_desc: str, qa_status: str, files_changed: List[str] = None) -> Dict:
    """
    Syncs documentation after QA approval.
    
    PATCH 3 (CRITICAL): Only runs if qa_status == "APPROVED"
    This prevents updating specs based on false claims.
    
    Args:
        task_desc: Description of the completed task
        qa_status: Must be "APPROVED" for sync to proceed
        files_changed: Optional list of files modified
    
    Returns:
        {"synced": bool, "changes": list, "reason": str}
    """
    # PATCH 3: VERIFIED SPEC UPDATE
    if qa_status != "APPROVED":
        print("   ⏭️ PO: Skipping sync (QA not approved)")
        return {
            "synced": False,
            "reason": f"QA status is '{qa_status}', not 'APPROVED'"
        }
    
    print("👔 PO: Syncing Reality with Documentation...")
    
    changes = []
    
    # 1. Update ACTIVE_SPEC.md
    spec_result = update_active_spec(task_desc)
    if spec_result.get("updated"):
        changes.append("ACTIVE_SPEC.md (story checked off)")
    
    # 2. Update CHANGELOG.md
    log_result = update_changelog(task_desc)
    if log_result.get("updated"):
        changes.append("CHANGELOG.md (entry added)")
    
    if changes:
        print(f"   ✅ PO Sync Complete: {len(changes)} updates")
    else:
        print("   ⏭️ PO: No documentation updates needed")
    
    # =========================================================================
    # v8.6 GAP #3: CONVENTIONAL COMMIT SUGGESTION
    # =========================================================================
    commit_msg = generate_conventional_commit(task_desc, files_changed or [])
    print(f"   📝 Suggested Commit: {commit_msg}")
    # =========================================================================
    
    return {
        "synced": True,
        "changes": changes,
        "spec_updated": spec_result.get("updated", False),
        "changelog_updated": log_result.get("updated", False),
        "suggested_commit": commit_msg
    }

# =============================================================================
# ASYNC WRAPPER (for integration with async pipelines)
# =============================================================================

async def run_product_sync_async(task_desc: str, qa_status: str, files_changed: List[str] = None) -> Dict:
    """
    Async wrapper for run_product_sync.
    """
    return run_product_sync(task_desc, qa_status, files_changed)


# =============================================================================
# v9.1 AIR GAP INGESTION (The Spec Compiler)
# =============================================================================
# Compiles raw PRDs/notes from inbox into strict, executable specs.
# This is the boundary between "Human Chaos" and "Machine Execution".

import shutil
import glob

async def ingest_inbox(llm_client=None, inbox_content: str = "") -> str:
    """
    Compiles Raw PRDs/Notes into the Strict Spec.
    Moves processed files to archive.

    Args:
        llm_client: Optional LLM client for AI compilation (if None, uses rule-based extraction)
        inbox_content: v15.1 - Optional pre-extracted content from docs/INBOX.md

    Returns:
        Status message describing what was processed
    """
    root = os.getcwd()
    inbox_path = os.path.join(root, "docs", "inbox")
    archive_path = os.path.join(root, "docs", "archive")

    # Ensure paths exist
    os.makedirs(inbox_path, exist_ok=True)
    os.makedirs(archive_path, exist_ok=True)

    # 1. SCAN INBOX
    files = [f for f in os.listdir(inbox_path)
             if os.path.isfile(os.path.join(inbox_path, f)) and not f.startswith(".")]

    # v15.1: Allow processing if we have INBOX.md content even without folder files
    has_inbox_content = bool(inbox_content and inbox_content.strip())

    if not files and not has_inbox_content:
        return "📭 Inbox is empty. Drop files in `docs/inbox/` or add notes to `docs/INBOX.md`."

    print(f"📥 PO: Found {len(files)} raw documents. Compiling...")

    # 2. READ RAW CONTEXT
    raw_context = ""

    # v15.1: Prepend INBOX.md content if provided
    if has_inbox_content:
        raw_context += f"\n--- SOURCE: INBOX.md (ephemeral notes) ---\n{inbox_content}\n"

    for filename in files:
        filepath = os.path.join(inbox_path, filename)
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                raw_context += f"\n--- SOURCE: {filename} ---\n{f.read()}\n"
        except Exception as e:
            print(f"   ⚠️ Could not read {filename}: {e}")

    # 3. READ DOMAIN RULES (Constitution)
    domain_rules = ""
    domain_rules_path = os.path.join(root, "docs", "DOMAIN_RULES.md")
    if os.path.exists(domain_rules_path):
        with open(domain_rules_path, "r", encoding="utf-8") as f:
            domain_rules = f.read()
    
    # 4. COMPILE (Extract constraints)
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    
    if llm_client:
        # AI-POWERED COMPILATION
        prompt = f"""
        ROLE: Strict Spec Compiler.
        TASK: Convert raw input into formal Spec Constraints.
        
        [DOMAIN RULES - CONSTITUTION]
        {domain_rules}
        
        [RAW INPUT]
        {raw_context}
        
        [INSTRUCTIONS]
        1. EXTRACT clear User Stories and Functional Constraints.
        2. DISCARD fluff, questions, or "nice-to-haves".
        3. IF AMBIGUOUS: Do not guess. List it as a "CLARIFICATION NEEDED" item.
        4. FORMAT: Markdown list suitable for ACTIVE_SPEC.md.
        """
        
        try:
            response = await llm_client.generate_json(
                model="gpt-5.1-codex-max", 
                system="You are the Product Owner.", 
                user=prompt
            )
            compiled_content = response.get("content") or response.get("text") or str(response)
        except Exception as e:
            print(f"   ⚠️ LLM compilation failed: {e}. Using rule-based fallback.")
            compiled_content = _rule_based_extract(raw_context)
    else:
        # RULE-BASED COMPILATION (No LLM)
        compiled_content = _rule_based_extract(raw_context)

    # 5. UPDATE SPEC
    spec_path = os.path.join(root, "docs", "ACTIVE_SPEC.md")
    
    # Create file if doesn't exist
    if not os.path.exists(spec_path):
        with open(spec_path, "w", encoding="utf-8") as f:
            f.write("# Active Specification\n\nThis is the executable contract for the Delegator.\n\n---\n")
    
    with open(spec_path, "a", encoding="utf-8") as f:
        f.write(f"\n\n## Ingestion Batch ({timestamp})\n")
        f.write(f"*Sources: {', '.join(files)}*\n\n")
        f.write(compiled_content)

    # 6. ARCHIVE FILES
    archived = []
    for filename in files:
        src = os.path.join(inbox_path, filename)
        # Prefix with timestamp to avoid collisions
        ts_prefix = datetime.now().strftime("%Y%m%d_%H%M%S")
        dst = os.path.join(archive_path, f"{ts_prefix}_{filename}")
        try:
            shutil.move(src, dst)
            archived.append(filename)
        except Exception as e:
            print(f"   ⚠️ Could not archive {filename}: {e}")
    
    result = f"✅ Ingested {len(files)} files. Spec updated. {len(archived)} files archived."
    print(f"   {result}")
    return result


def _rule_based_extract(raw_content: str) -> str:
    """
    Simple rule-based extraction when LLM is not available.
    Looks for common patterns in raw PRDs.
    """
    lines = raw_content.split('\n')
    constraints = []
    
    # Patterns that indicate requirements
    requirement_patterns = [
        "must ", "should ", "shall ", "need to ", "has to ", "require",
        "- [ ]", "* [ ]", "TODO:", "MUST:", "SHOULD:",
    ]
    
    for line in lines:
        line_lower = line.lower().strip()
        if any(pattern in line_lower for pattern in requirement_patterns):
            # Clean up the line
            cleaned = line.strip()
            if cleaned and not cleaned.startswith("---"):
                constraints.append(f"- [ ] {cleaned}")
    
    if constraints:
        return "### Extracted Requirements\n\n" + "\n".join(constraints)
    else:
        return "### Raw Content (No structured requirements found)\n\n" + raw_content[:500] + "..."

