import os
import json
import re
import subprocess
from datetime import datetime

# --- CONFIGURATION ---
SKILLS_DIR = "skills"
DOMAINS_DIR = os.path.join(SKILLS_DIR, "domains")
HISTORY_FILE = "PROJECT_HISTORY.md"
LESSONS_FILE = "LESSONS_LEARNED.md"

# --- SECURITY & VALIDATION ---
SECURITY_PATTERNS = [
    r"AKIA[0-9A-Z]{16}",                  # AWS
    r"sk-[a-zA-Z0-9]{48}",                # OpenAI
    r"-----BEGIN PRIVATE KEY-----",       # RSA
    r"password\s*=\s*['\"][^'\"]+['\"]"   # Passwords
]

def scan_for_secrets(diff_text):
    """Deterministic pre-flight check for credentials."""
    for pattern in SECURITY_PATTERNS:
        if re.search(pattern, diff_text):
            return False, f"CRITICAL: Found secret pattern: {pattern}"
    return True, "Safe"

def validate_commit_message(message, task_id):
    """
    Refinement #2: Commit Validation.
    Enforces pattern: <type>(<scope>): <subject> (Ref: #ID)
    """
    # 1. Check for ID presence
    id_tag = f"(Ref: #{task_id})"
    if id_tag not in message:
        return False, f"Commit message missing Traceability Tag: '{id_tag}'"
    
    # 2. Check for Conventional Commit Structure (heuristic)
    # Looks for: word(word): ...
    # We use a simplified regex to allow for standard conventional commits
    if not re.match(r"^[a-z]+\([a-z0-9_-]+\): .+" + re.escape(id_tag) + "$", message):
         return False, f"Commit message violates Conventional Commits format. Expected: 'feat(scope): msg {id_tag}'"

    return True, "Valid"

# --- CORE LOGIC ---
def append_lesson_learned(content: str, category: str = "General"):
    """
    Appends a new lesson to LESSONS_LEARNED.md.
    """
    timestamp = datetime.now().strftime("%Y-%m-%d")
    entry = f"\n- **[{timestamp}] {category}:** {content}"
    
    try:
        with open(LESSONS_FILE, "a", encoding="utf-8") as f:
            f.write(entry)
    except Exception as e:
        print(f"❌ [Lessons] Failed to append: {e}")

def inject_domain_and_lane_rules(task, domain=None, lane=None):
    """Injects rules with Supremacy Clause."""
    context_str = ""
    
    # Domain (Absolute)
    if domain:
        d_path = os.path.join(DOMAINS_DIR, f"{domain}.md")
        if not os.path.exists(d_path):
            return None, f"CRITICAL: Domain Rules '{domain}' NOT FOUND."
        with open(d_path, 'r') as f:
            context_str += f"\n\n--- DOMAIN RULES (ABSOLUTE OVERRIDE) ---\n{f.read()}"

    # Lane (Supplementary)
    if lane:
        l_path = os.path.join(SKILLS_DIR, f"{lane}.md")
        if os.path.exists(l_path):
            with open(l_path, 'r') as f:
                 context_str += f"\n\n--- LANE RULES (Supplementary) ---\n{f.read()}"
        else:
            # Fallback Protocol (V4.1)
            default_path = os.path.join(SKILLS_DIR, "_default.md")
            if os.path.exists(default_path):
                 print(f" >> [Controller] ⚠️  Lane '{lane}' missing. Using Fallback.")
                 append_lesson_learned(f"Missing skill pack for lane '{lane}'. Fallback applied.", "System")
                 with open(default_path, 'r') as f:
                     context_str += f"\n\n--- LANE RULES (Fallback) ---\n{f.read()}"
            else:
                 print(f" >> [Controller] ⚠️  Lane '{lane}' missing and No Default found.")

def run_librarian_review(task, worker_summary):
    print(f" >> [Controller] Librarian reviewing Task #{task['id']}...")

    # 1. Get Diff
    try:
        diff_text = subprocess.run(["git", "diff", "--staged"], capture_output=True, text=True).stdout
    except Exception:
        return {"status": "REJECTED", "reason": "Git Error - Could not read diff"}
    
    # 0. The Linter Gate (V5.3 Refinement)
    # Don't pay LLM to find syntax errors.
    print(" >> [Controller] Running Linter (Ruff)...")
    try:
        # Check current directory. Adjust command as needed (e.g. "ruff check .")
        # Using check . --select E,F to keep it basic/fast
        subprocess.run(["ruff", "check", ".", "--select", "E,F"], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        # Linter failed
        error_out = e.stderr.decode() if e.stderr else e.stdout.decode()
        return {"status": "REJECTED", "reason": f"Linter Failed: {error_out[:200]}..."}
    except FileNotFoundError:
        print(" >> [Controller] Warning: Ruff not installed. Skipping Linter Gate.")

    if diff_text is None: diff_text = ""

    # 2. Security Scan
    is_safe, sec_msg = scan_for_secrets(diff_text)
    if not is_safe:
        return {"status": "REJECTED", "reason": sec_msg}

    # 3. LLM Interaction (Stub)
    # In production, you send 'diff_text' + 'librarian_sop' to the LLM.
    # The LLM returns a JSON with { "action": "commit", "message": "..." }
    # For simulation (since we don't have the LLM connected in this script logic), 
    # we'll simulate a SUCCESSFUL response if it were real.
    # NOTE: This part replaces the actual LLM call.
    llm_response = {
        "action": "commit", 
        "message": f"feat(backend): implement logging (Ref: #{task['id']})" 
    }

    # 4. Commit Validation (Refinement #2)
    if llm_response["action"] == "commit":
        is_valid, val_msg = validate_commit_message(llm_response["message"], task['id'])
        if not is_valid:
             return {"status": "REJECTED", "reason": f"Librarian Error: {val_msg}"}
        
        # 5. Execute Commit
        # In production, we run: subprocess.run(["git", "commit", "-m", llm_response["message"]])
        # For now, print it.
        print(f" >> [Librarian] Committing: {llm_response['message']}")
        return {"status": "COMPLETED"}
    
    return {"status": "REJECTED", "reason": llm_response.get("reason", "Unknown")}



def prioritize_tasks(tasks):
    """
    Sorts tasks by Priority (Descending) then ID (Ascending).
    Default priority is 5.
    """
    return sorted(tasks, key=lambda x: (-x.get('priority', 5), x['id']))

def main_loop():
    # Mock Task Queue
    raw_tasks = [
        {"id": 101, "priority": 3, "domain": "medicine", "lane": "backend", "goal": "Fix logs"},
        {"id": 102, "priority": 9, "domain": "medicine", "lane": "backend", "goal": "Critical Security Patch"},
    ]
    
    # Priority Sort
    queue = prioritize_tasks(raw_tasks)
    task = queue[0]
    print(f" >> [Controller] Picked Top Task #{task['id']} (Priority: {task.get('priority')})")
    
    # 1. Inject
    rules, error = inject_domain_and_lane_rules(task, task["domain"], task["lane"])
    if error:
        print(f" >> [SAFETY SWITCH] {error}")
        return

    # 2. Work (Stub)
    print(" >> [Worker] Working...")
    # ... worker does 'git add .' ...
    worker_summary = "Added logs."

    # 3. Review
    result = run_librarian_review(task, worker_summary)
    print(f" >> [Final Status] {result['status']}")

    # 4. Feedback Loop & Audit Logging (V5.2 Final Refinements)
    audit_file = "AUDIT.log"
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    if result['status'] == "REJECTED":
        rejection_reason = result.get('reason', 'Unknown Reason')
        print(f" >> [Controller] 🔄 LOOPBACK: Sending error to Worker: {rejection_reason}")
        
        # In a real agent loop, we would do:
        # worker_agent.add_context(f"PREVIOUS ATTEMPT REJECTED. REASON: {rejection_reason}. FIX THIS.")
        
        with open(audit_file, "a") as f:
            f.write(f"[{timestamp}] REJECTED Task #{task['id']}: {rejection_reason}\n")

    elif result['status'] == "COMPLETED":
        with open(audit_file, "a") as f:
            f.write(f"[{timestamp}] COMPLETED Task #{task['id']}\n")

if __name__ == "__main__":
    main_loop()
