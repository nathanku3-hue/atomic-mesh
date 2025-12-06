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
    
    return {
        "synced": True,
        "changes": changes,
        "spec_updated": spec_result.get("updated", False),
        "changelog_updated": log_result.get("updated", False)
    }

# =============================================================================
# ASYNC WRAPPER (for integration with async pipelines)
# =============================================================================

async def run_product_sync_async(task_desc: str, qa_status: str, files_changed: List[str] = None) -> Dict:
    """
    Async wrapper for run_product_sync.
    """
    return run_product_sync(task_desc, qa_status, files_changed)
