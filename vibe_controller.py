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
    
    return context_str, None

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

# --- V5.4: BLUEPRINT PARSING (The Scribe) ---
PARSER_LOG = "PARSER_AUDIT.log"

def log_parser_event(message: str, level: str = "INFO"):
    """Logs Blueprint Parsing decisions to PARSER_AUDIT.log."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] [{level}] {message}\n"
    try:
        with open(PARSER_LOG, "a", encoding="utf-8") as f:
            f.write(entry)
    except Exception as e:
        print(f"❌ [ParserLog] Failed: {e}")

def run_librarian_parser(blueprint_task: dict) -> list:
    """
    Librarian Mode: SPEC WRITER & VALIDATOR (V5.5.1).
    Multi-Lane Decomposition with Traceability, Domain Inheritance & Rejection Logging.
    """
    bp_id = blueprint_task['id']
    bp_domain = blueprint_task.get('domain', 'general')
    print(f" >> [Librarian] Parsing Blueprint #{bp_id} ({bp_domain})...")
    log_parser_event(f"[START] Parsing Blueprint #{bp_id} (Domain: {bp_domain})")

    generated_tasks = []
    try:
        raw_text = blueprint_task.get('goal') or blueprint_task.get('description', '')
        if not raw_text:
            raise ValueError("Empty Blueprint - no content to parse")

        # 1. Multi-Lane Decomposition (V5.5)
        # In production: call LLM with "Split this into Backend/Frontend/Security tasks."
        generated_tasks = [
            {"goal": "Implement Backend API", "lane": "backend", "priority": 10, "type": "implementation"},
            {"goal": "Implement Frontend UI", "lane": "frontend", "priority": 10, "type": "implementation"},
            {"goal": "Write Unit Tests", "lane": "backend", "priority": 10, "type": "implementation"},
        ]

        if not generated_tasks:
            raise ValueError("LLM returned 0 tasks. Blueprint may be vague.")

        # 2. Domain Constraint Injection (The V-Model)
        if bp_domain == 'medicine':
            has_compliance = any("hipaa" in t['goal'].lower() or "compliance" in t['goal'].lower() for t in generated_tasks)
            if not has_compliance:
                generated_tasks.append({
                    "goal": "Verify HIPAA Compliance (MED-01)",
                    "lane": "security",
                    "priority": 8,
                    "type": "verification"
                })
                log_parser_event(f"[DOMAIN] Auto-Injected HIPAA Audit for Blueprint #{bp_id}")
        
        if bp_domain == 'law':
            has_audit = any("audit" in t['goal'].lower() for t in generated_tasks)
            if not has_audit:
                generated_tasks.append({
                    "goal": "Verify Audit Logs (LAW-02)",
                    "lane": "security",
                    "priority": 8,
                    "type": "verification"
                })
                log_parser_event(f"[DOMAIN] Auto-Injected Audit Task for Blueprint #{bp_id}")

        # 3. Traceability, Domain Inheritance & Cross-Lane Sanitization (V5.5.1)
        for t in generated_tasks:
            t['parent_id'] = bp_id
            t['domain'] = bp_domain  # Strict Inheritance (Rank #3)
            
            # Reject Cross-Lane Hallucinations
            if "/" in t.get('lane', ''):
                original_lane = t['lane']
                t['lane'] = "general"
                log_parser_event(f"[WARNING] Task '{t['goal']}' had mixed lane '{original_lane}'. Defaulting to 'general'.")
            
            t['traceability'] = {
                "parent_task": bp_id,
                "origin": "librarian_parser",
                "inherited_constraints": [bp_domain]
            }
            # save_task_to_db(t)  # In production
            print(f"    -> Created Task: {t['goal']} (Lane: {t['lane']}, Prio: {t['priority']})")
            log_parser_event(f"[CREATED] '{t['goal']}' | Lane: {t['lane']} | Domain: {t['domain']} | Parent: #{bp_id}")

        log_parser_event(f"[SUCCESS] Blueprint #{bp_id} -> {len(generated_tasks)} Atomic Tasks.")
        print(f" >> [Librarian] Blueprint parsed. {len(generated_tasks)} tasks created.")

    except Exception as e:
        # Rank #1: Explicit Rejection Logging
        print(f" >> [Librarian] Parsing FAILED: {e}")
        log_parser_event(f"[REJECTED] Blueprint #{bp_id} failed parsing. Reason: {str(e)}", level="ERROR")

    return generated_tasks


def main_loop():
    # --- V5.4: BLUEPRINT PARSING PHASE ---
    # Poll for Blueprints (status="PENDING_PARSING")
    mock_blueprints = [
        {"id": 200, "status": "PENDING_PARSING", "domain": "medicine", "goal": "Implement Auth Module with HIPAA constraints."}
    ]
    
    for bp in mock_blueprints:
        if bp.get("status") == "PENDING_PARSING":
            child_tasks = run_librarian_parser(bp)
            # In production: mark_task_complete(bp['id'])
            # Child tasks are added to the queue dynamically
    
    # --- STANDARD EXECUTION PHASE ---
    # Mock Task Queue (V5.3)
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
