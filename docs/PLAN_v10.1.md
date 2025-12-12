# Implementation Plan: v10.1 "The Source of Truth"

## Overview
Implement the Two-Tier Source Strategy for provenance tracking. This enables "Code from Books" compliance where domain logic must cite authoritative sources while standard engineering practices use default references.

---

## Architecture Summary

### Two-Tier Source Strategy
| Tier | Purpose | Examples | Requirement |
|------|---------|----------|-------------|
| **A: Domain Sources** | Formulas, Compliance, Business Rules | `HIPAA-SEC-01`, `LAW-21-A` | **Mandatory** |
| **B: Standard Sources** | Logging, Auth, CSS, Error Handling | `STD-SEC-01`, `STD-CODE-01` | Implicit/Optional |

### Integration Points
- **Planner**: Assigns `source_ids` when creating tasks
- **Worker**: Injects source citations as code comments
- **Reviewer**: Verifies code matches cited source text

---

## Implementation Steps

### Step 1: Create Directory Structure
**Action:** Create `docs/sources/` directory

```
docs/
├── sources/                    # NEW: Source of Truth library
│   ├── STD_ENGINEERING.md     # Standard engineering practices (Tier B)
│   └── [DOMAIN]_BOOK.md       # Domain-specific sources (Tier A)
├── ACTIVE_SPEC.md
├── DOMAIN_RULES.md
└── ...
```

### Step 2: Create STD_ENGINEERING.md
**File:** `docs/sources/STD_ENGINEERING.md`

Content includes 5-15 golden engineering rules with stable IDs:
- `[STD-SEC-01]` No Hardcoded Secrets
- `[STD-CODE-01]` Single Responsibility
- `[STD-ERR-01]` Graceful Failure
- `[STD-TEST-01]` Test Coverage
- `[STD-DOC-01]` Self-Documenting Code

**ID Pattern:** `[A-Z0-9_-]+-[0-9]{2,}(-[A-Z])?`

### Step 3: Add MCP Tool - `get_source_text()`
**File:** `mesh_server.py` (add after existing knowledge tools ~line 862)

```python
@mcp.tool()
def get_source_text(source_id: str) -> str:
    """
    Looks up the text of a Source ID (e.g., 'HIPAA-SEC-01' or 'STD-CODE-01').
    Scans all files in docs/sources/.

    Args:
        source_id: The ID to look up (e.g., 'STD-SEC-01', 'HIPAA-SEC-01')

    Returns:
        The source text, or error if not found.
    """
```

**Logic:**
1. Scan all `.md` files in `docs/sources/`
2. Regex match: `## \[{source_id}\].*?\*\*Text:\*\*\s*(.*?)(?=\n##|\Z)`
3. Return matched text or "not found" error

### Step 4: Update Reviewer Prompt
**File:** `library/prompts/reviewer.md`

**Add new section after "Domain Rules Compliance":**

```markdown
### 2.5 Source Verification (The Citation Check)
For each `source_id` in the Task:
- [ ] Call `get_source_text(source_id)` to retrieve the authoritative text
- [ ] Verify the code **strictly adheres** to that text
- [ ] If code deviates from cited source: **FAIL**
- [ ] If source_id not found: **WARN** (log, but don't auto-fail)
```

### Step 5: Document tasks.json Schema Extension
**File:** `control/state/tasks.json` (document in `_meta`)

New task fields:
```json
{
  "source_ids": ["HIPAA-SEC-01", "STD-CODE-01"],
  "source_tier": "domain" | "standard"  // Optional, inferred from prefix
}
```

---

## Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `docs/sources/` | **NEW DIR** | Source library directory |
| `docs/sources/STD_ENGINEERING.md` | **NEW FILE** | Standard engineering golden rules |
| `mesh_server.py` | **EDIT** | Add `get_source_text()` tool |
| `library/prompts/reviewer.md` | **EDIT** | Add Source Verification section |
| `control/state/tasks.json` | **SCHEMA DOC** | Document `source_ids` field |

---

## Worker "Citation Injection" Rule
**Constraint for Worker prompts (future enhancement):**

> "If the Task has `source_ids`, you MUST append them as comments above the relevant function or class."

**Example:**
```python
# Implements [HIPAA-SEC-01] - All PHI must be encrypted at rest using AES-256
def encrypt_patient_data(data: bytes) -> bytes:
    ...
```

---

## Testing Checklist

1. [ ] `get_source_text("STD-SEC-01")` returns correct text
2. [ ] `get_source_text("INVALID-ID")` returns "not found" error
3. [ ] Reviewer can call tool and verify against code
4. [ ] Tasks can include `source_ids` field without breaking existing flow

---

## Version
- **Target:** v10.1 → v10.3
- **Codename:** "The Source of Truth" → "Deep Wiring"
- **Status:** DEPLOYED

---

## v10.3 "Deep Wiring" Extensions

### Additional Changes

| Component | Change |
|-----------|--------|
| `init_db()` | Added `source_ids` column + safe ALTER TABLE migration |
| `bootstrap_project()` | Auto-creates `docs/sources/` + `STD_ENGINEERING.md` |
| `post_task()` | Accepts `source_ids`, syncs to SQLite + JSON state machine |
| `register_task()` | Added `source_ids`, `source_tier` (auto-detected from prefix) |
| `get_source_context()` | New helper function for compliance context injection |
| `dispatch_to_worker()` | Injects compliance context into `full_task_context` |
| `generate_tests_for_task()` | Injects compliance context for test generation |

### Data Flow

```
PLANNER ──[assigns source_ids]──> post_task()
                                       │
                           ┌───────────┴───────────┐
                           ▼                       ▼
                      SQLite (tasks)        JSON (tasks.json)
                           │                       │
                           └───────────┬───────────┘
                                       ▼
                              dispatch_to_worker()
                                       │
                           ┌───────────┴───────────┐
                           ▼                       ▼
                    WORKER (code)           TESTER (tests)
                    gets full_task_context  gets compliance_context
                           │                       │
                           └───────────┬───────────┘
                                       ▼
                                  REVIEWER
                                  calls get_source_text()
                                  verifies # Implements [ID]
```

---

## v10.5 "The Traffic Controller" Extensions

### Overview
Enforces dependencies at execution time, preventing tasks from running before their dependencies are satisfied.

### Components Added

| Component | Change |
|-----------|--------|
| `get_task_dependency_status()` | Checks if a task's dependencies are all COMPLETE |
| `detect_circular_dependencies()` | DFS-based deadlock detection |
| `would_create_cycle()` | Pre-creation cycle validation |
| `get_next_valid_task()` | Archetype-priority task selection |
| `check_task_dependencies()` | MCP tool for dependency status |
| `get_next_task_to_execute()` | MCP tool for next ready task |

### pick_task() Integration
- Now checks JSON state machine dependencies via `get_task_dependency_status()`
- Skips tasks with unsatisfied dependencies
- Syncs status changes to JSON state machine (IN_PROGRESS, COMPLETE, FAILED)

### dashboard() Enhancement
- Shows deadlock warnings if circular dependencies detected
- Shows archetype badge for each task
- Shows blocking info (`🔒 blocked by: T-001,T-002`)

### get_project_status() Enhancement
- New `dependencies` section with deadlock and blocking info
- Shows ready vs blocked task counts

### Cycle Prevention
- `create_task_with_sources()` validates dependencies before creation
- `post_task()` validates dependencies before creation
- Returns `CIRCULAR_DEPENDENCY` error if cycle would be created

### Task Status Sync
- `complete_task()` → syncs COMPLETE to JSON state machine
- `reopen_task()` → syncs PENDING to JSON state machine
- `pick_task()` → syncs IN_PROGRESS on task assignment
- Failure after max retries → syncs FAILED

### Data Flow
```
PLANNER ──[creates task with deps]──> create_task_with_sources()
                                            │
                                    ┌───────┴───────┐
                                    ▼               ▼
                                 cycle check    REJECT if cycle
                                    │
                                    ▼
                              SQLite + JSON
                                    │
                                    ▼
pick_task() ──[checks deps]──> get_task_dependency_status()
        │                           │
        ├──[blocked]──────────> skip task, continue search
        │
        └──[ready]──────────────> dispatch + sync IN_PROGRESS
                                    │
                                    ▼
                              complete_task()
                                    │
                                    ▼
                              sync COMPLETE → JSON
                                    │
                                    ▼
                              dependent tasks now ready
```

### Status: DEPLOYED

---

## v10.5b "The Structured Architect" Extensions

### Overview
Moves from fragile string parsing to explicit database columns. Adds idempotent task creation for safe replanning.

### Database Schema (Self-Healing Migration)

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `archetype` | TEXT | 'GENERIC' | Task classification (DB, API, LOGIC, UI, SEC, TEST, CLARIFICATION) |
| `dependencies` | TEXT | '[]' | JSON list of dependency task IDs |
| `trace_reasoning` | TEXT | '' | Why this task exists (traceability) |

### New MCP Tool: `upsert_task()`

**Idempotent task creation** - prevents duplicates when replanning:

```python
upsert_task(
    title="[DB] Create consent table",
    archetype="DB",
    source_ids="HIPAA-01,STD-SEC-01",
    dependencies="1,2",
    reasoning="Derived from HIPAA clause: All consent must be recorded",
    priority="HIGH"
)
```

**Behavior:**
- Checks for existing task by `title + archetype` uniqueness
- If found: UPDATE the existing task's metadata
- If not found: CREATE new task
- Returns `{"action": "CREATED"}` or `{"action": "UPDATED"}`

### New Control Panel Commands

| Command | Description |
|---------|-------------|
| `/plan_from_source <ID>` | Load a source and prepare for planning |
| `/sources` | List all available Source IDs |

### Data Flow

```
USER ──[/plan_from_source HIPAA-01]──> Control Panel
                                            │
                                    ┌───────┴───────┐
                                    ▼               ▼
                             get_source_text()  Show Source Preview
                                    │
                                    ▼
                              PLANNER AGENT
                                    │
                           [calls upsert_task() for each requirement]
                                    │
                                    ▼
                        ┌───────────┴───────────┐
                        ▼                       ▼
                   SQLite (explicit columns)  JSON State Machine
                        │                       │
                        └───────────┬───────────┘
                                    ▼
                              WORKER AGENT
                              (sees archetype, dependencies, reasoning)
```

### Status: DEPLOYED

---

## v10.6 "The Stable Autopilot" Extensions

### Overview
Three pillars: Anti-Spam (Semantic Fingerprinting), Autopilot (Coverage Gap Planning), and Compliance Officer (Test Pairing).

### 1. Semantic Fingerprinting (`upsert_task`)

**Anti-Spam Guardrail**: A Source ID cannot have duplicate Archetypes.

```
Before v10.6: Idempotency by Title + Archetype
After v10.6:  Idempotency by Source + Archetype (Semantic)
```

**Logic:**
```python
# If HIPAA-01 already has a [DB] task, don't create another
for existing_task in tasks:
    if set(new_sources).intersection(existing_sources) and archetype_match:
        UPDATE existing_task  # Don't create duplicate
```

**Benefit:** Running the Planner twice on "Chapter 4" won't flood the queue with duplicates.

### 2. Coverage Gap Autopilot (`get_coverage_gaps`, `/plan_gaps`)

**New MCP Tool:**
```python
get_coverage_gaps(limit=5)  # Returns UNMAPPED sources (High Priority first)
```

**New Command:**
```
/plan_gaps  →  Analyzes coverage, shows gaps, preps for Planner
```

**Output Example:**
```
🚀 AUTOPILOT: Analyzing Coverage Gaps...
🔍 Found 3 UNMAPPED sources

[HIGH] HIPAA-SEC-02
       File: HIPAA_COMPLIANCE.md
[MEDIUM] STD-LOG-01
       File: STD_ENGINEERING.md

AUTOPILOT READY
TIP: Ask the AI to 'Plan tasks for the coverage gaps'
```

### 3. Test Pairing Rule (`planner.md`)

**Mandatory Compliance:** Every `[LOGIC]`, `[API]`, `[SEC]` task needs a paired `[TEST]` task.

```
T-001: [LOGIC] Implement consent validation
       source_ids: HIPAA-01

T-002: [TEST] Test consent validation logic
       source_ids: HIPAA-01     ← Same sources!
       deps: T-001              ← Depends on implementation!
```

### Files Modified

| File | Change |
|------|--------|
| `mesh_server.py` | `upsert_task` semantic fingerprinting |
| `mesh_server.py` | Added `get_coverage_gaps()` MCP tool |
| `control_panel.ps1` | Added `/plan_gaps` command |
| `library/prompts/planner.md` | Added PAIRING RULE section |

### Status: DEPLOYED

---

## v10.7 "The Reality Check" Extensions

### Overview
Provenance Scanner that converts "Intent" (tasks claiming to implement sources) into "Evidence" (actual code with `# Implements [ID]` comments). Detects "Paper Tigers" (tasks with no implementation).

### Components Added

| Component | Change |
|-----------|--------|
| `generate_provenance_report()` | Scans codebase for `# Implements [ID]` tags |
| `get_provenance()` | Lookup provenance for specific Source ID |
| `/provenance` command | CLI command for provenance reality check |
| `upsert_task()` fix | Dependencies now MERGE instead of overwrite |

### The Provenance Chain

```
INTENT (Tasks)                    REALITY (Code)
────────────────                  ────────────────
Task claims source_ids: []   →    # Implements [ID] comments in code
      ↓                                ↓
      └─────────────────────────────────┘
                    ↓
             PROVENANCE CHECK
                    ↓
      ┌─────────────┼─────────────┐
      ↓             ↓             ↓
  VERIFIED      PAPER TIGER    ORPHAN CODE
  (Intent=Reality) (Intent, no code) (Code, no task)
```

### Provenance Scanner Logic

```python
# Scans for pattern: # Implements [SOURCE-ID] or // Implements [SOURCE-ID]
pattern = r'[#/]+\s*Implements\s*\[([A-Z0-9,\s\-_]+)\]'

# For each match:
# 1. Extract Source IDs (supports multiple: [STD-SEC-01, STD-ERR-01])
# 2. Track file path and line number
# 3. Cross-reference with tasks claiming those sources

# Result categories:
# - VERIFIED: Task exists AND code implements it
# - PAPER_TIGER: Task exists BUT no code found
# - ORPHAN_CODE: Code exists BUT no task claims it
```

### Dependency Auto-Merge Fix

**Before v10.7:**
```python
# Calling upsert_task twice with different deps:
upsert_task("Task A", dependencies="1,2")  # deps: [1,2]
upsert_task("Task A", dependencies="3,4")  # deps: [3,4]  <-- Overwrites!
```

**After v10.7:**
```python
# Dependencies are now MERGED:
upsert_task("Task A", dependencies="1,2")  # deps: [1,2]
upsert_task("Task A", dependencies="3,4")  # deps: [1,2,3,4]  <-- Merged!
```

### CLI Usage

```
/provenance              # Summary: Paper Tigers + Orphan Code
/provenance STD-SEC-01   # Details for specific Source ID
```

### Output Files

| File | Purpose |
|------|---------|
| `control/state/provenance.json` | Full provenance data |

### Data Flow

```
/provenance ──────────> generate_provenance_report()
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
             Scan src/, tests/      Load tasks from SQLite
                    │                     │
                    ▼                     ▼
             Find # Implements []   Get task.source_ids
                    │                     │
                    └──────────┬──────────┘
                               ▼
                        Cross-Reference
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
          VERIFIED        PAPER TIGER      ORPHAN CODE
          (Task+Code)     (Task only)      (Code only)
                               │
                               ▼
                    provenance.json saved
```

### Status: DEPLOYED

---

## v10.8 "The Librarian" Extensions

### Overview
Document Ingestion Pipeline that automates "Bridge 1" - converting PDFs, DOCX files, and other documents into Source Markdown files for the Planner to consume.

### The Problem Solved
Before v10.8:
```
1. Open PDF of Medical Textbook
2. Manually copy Chapter 4
3. Paste into docs/sources/MED_CH4.md
4. Manually format with ## [ID] headers
5. Repeat for every chapter...
```

After v10.8:
```
/ingest Medical_Textbook_Ch4.pdf MED-CH4
-> Creates MED-CH4_INGESTED.md with [MED-CH4-001] through [MED-CH4-047]
-> Next: Run '/plan_gaps' to see new unmapped sources
```

### Components Added

| Component | Change |
|-----------|--------|
| `ingest_file_to_source()` | MCP tool: PDF/DOCX/TXT -> Source Markdown |
| `list_ingestable_files()` | MCP tool: Lists files ready for ingestion |
| `/ingest <path> <PREFIX>` | CLI command for direct file ingestion |

### Dependencies (Optional)
```bash
pip install pypdf python-docx markdownify
```

The system gracefully degrades if dependencies are missing - it will prompt you to install them.

### CLI Usage
```
# v10.8 MODE: Direct file ingestion
/ingest C:\Books\HIPAA_Guide.pdf HIPAA
/ingest "E:\Medical\Chapter 4.docx" MED-CH4

# v9.1 MODE: Inbox-based (still works)
/ingest  # Processes all files in docs/inbox/
```

### Output Format
The ingestion tool generates Source Markdown files:

```markdown
# Ingested Source: HIPAA_Guide.pdf

**Domain Prefix:** HIPAA
**Ingested:** 2024-01-15 14:30
**Original File:** C:\Books\HIPAA_Guide.pdf

---

## [HIPAA-001]
**Text:** All covered entities must implement safeguards to protect PHI...

## [HIPAA-002]
**Text:** Business associates must sign agreements before accessing...
```

### Data Flow

```
User --[/ingest file.pdf PREFIX]--> ingest_file_to_source()
                                          |
                            +-------------+-------------+
                            v                           v
                      PDF Extract               DOCX Extract
                      (pypdf)                   (python-docx)
                            |                           |
                            +-----------+---------------+
                                        v
                                  Paragraph Split
                                  (min 50 chars)
                                        |
                                        v
                                  Auto-ID Assignment
                                  PREFIX-001, PREFIX-002, ...
                                        |
                                        v
                              docs/sources/PREFIX_INGESTED.md
                                        |
                                        v
                              /plan_gaps -> Shows unmapped sources
                                        |
                                        v
                              Planner -> Creates tasks with source_ids
```

### Workflow Integration
```
Step 1: /ingest "Medical_Book.pdf" MED-CH4
        -> Creates MED-CH4_INGESTED.md with [MED-CH4-001]...[MED-CH4-047]

Step 2: /plan_gaps
        -> Shows "Found 47 UNMAPPED sources"

Step 3: Planner Agent
        -> "Plan tasks from source MED-CH4-001"
        -> Creates [DB], [LOGIC], [API], [TEST] tasks

Step 4: Worker executes
        -> Writes code with # Implements [MED-CH4-001] comments

Step 5: /provenance
        -> Verifies INTENT matches REALITY
```

### Status: DEPLOYED

---

## v10.9 "The Research Airlock" Extensions

### Overview
Sanitizes external knowledge before it enters the Source of Truth system. Creates a "firewall for the mind" that transforms messy PDFs and articles into stable, ID-based Professional Standards.

### The Problem Solved
**Before v10.9:** Random web research pollutes the Planner's context with non-deterministic, changing information.

**After v10.9:** All external knowledge passes through an Airlock:
```
External World          The Airlock              Source of Truth
--------------          -----------              ----------------
PDF Articles    -->   docs/research/inbox/   -->   [PRO-*] IDs
Web Research    -->      /compile            -->   STD_PROFESSIONAL.md
Best Practices  -->   AI Extraction          -->   Stable, Citable Rules
```

### Three-Tier Source Hierarchy
| Tier | Prefix | Override Policy | Examples |
|------|--------|-----------------|----------|
| **LAW** | `HIPAA-`, `LAW-`, `REG-` | NEVER override | Legal mandates |
| **PRO** | `PRO-` | Override with justification | Best practices |
| **STD** | `STD-` | Implicit default | Engineering plumbing |

### Components Added

| Component | Change |
|-----------|--------|
| `docs/research/inbox/` | Drop zone for raw research files |
| `docs/research/archive/` | Processed files storage |
| `docs/sources/STD_PROFESSIONAL.md` | Curated PRO-* rules |
| `research_compiler.md` | Prompt for extraction agent |
| `compile_research()` | MCP tool for airlock processing |
| `get_research_status()` | MCP tool for airlock status |
| `/compile` | CLI command to process inbox |
| `/research` | CLI command to view airlock status |

### Research Compiler Prompt
Located at `library/prompts/research_compiler.md`:
- Extracts actionable rules in imperative voice
- Assigns `[PRO-CATEGORY-SEQ]` IDs
- Requires Text, Context, and Source fields
- Categories: PRO-SEC, PRO-ARCH, PRO-PERF, PRO-API, PRO-DATA, PRO-TEST

### CLI Usage
```
# Check airlock status
/research

# Process inbox files
/compile

# Workflow
1. Drop PDF into docs/research/inbox/
2. Run /compile
3. Content staged in STD_PROFESSIONAL.md
4. AI extracts [PRO-*] rules
5. /plan_gaps shows new PRO sources
6. Planner creates tasks citing PRO-* IDs
```

### Data Flow

```
User drops file --> docs/research/inbox/
                          |
                    /compile
                          |
          +---------------+---------------+
          |               |               |
     PDF Extract    DOCX Extract    TXT/MD Read
     (pypdf)        (python-docx)
          |               |               |
          +-------+-------+---------------+
                  |
            Content Staged
            in STD_PROFESSIONAL.md
                  |
            AI Extraction
            (Research Compiler prompt)
                  |
            [PRO-SEC-01] Rule extracted
            [PRO-ARCH-01] Rule extracted
                  |
            Original --> docs/research/archive/
                  |
            /plan_gaps shows new PRO sources
                  |
            Planner creates tasks
            with source_ids: [PRO-SEC-01]
```

### Why This Matters
1. **Determinism:** External knowledge becomes stable IDs
2. **Auditability:** Every PRO rule traces to an archived source
3. **Override Policy:** PRO can be overridden (unlike LAW), but requires justification
4. **No Hallucination:** AI curates format, not facts

### Status: DEPLOYED

---

## v10.10 "The Knowledge Refinery" Extensions

### Overview
The Curator agent transforms raw, verbose source text (Book Chunks) into **Atomic, Imperative Engineering Rules** that can be directly enforced by the Reviewer. Adds Authority Layer for governance.

### The Problem Solved
**Before v10.10:** Ingested chunks are verbose academic prose ("It is recommended that...")
**After v10.10:** Curated rules are strict engineering constraints ("MUST encrypt all PHI")

### Components Added

| Component | Change |
|-----------|--------|
| `docs/sources/SOURCE_REGISTRY.json` | Authority Layer - defines tiers and override policies |
| `library/prompts/curator.md` | The Refinery Protocol prompt |
| `compile_curated_rules()` | MCP tool for batch curation |
| `get_source_registry()` | MCP tool for registry access |
| `register_source()` | MCP tool for registering new sources |
| `/curate <PREFIX>` | CLI command for curation |
| `/registry` | CLI command for authority display |

### The Refinery Protocol

```
1. FLATTEN - Remove Academic Fluff
   Strip: Historical context, "It is recommended...", Marketing language

2. HARDEN - Strengthen Language
   "should" → "MUST"
   "may" → "SHALL" (if required) or DELETE (if optional)
   "consider" → "IMPLEMENT"
   "ideally" → DELETE or "MUST"

3. ATOMIZE - One Rule Per Entry
   Split multi-requirement chunks into separate rules
   Each gets its own ID: [DR-PREFIX-SEQ]

4. TRACE - Maintain Provenance
   Every rule MUST reference: Derived From: [ORIGINAL-ID]

5. DEDUPLICATE - Merge Redundant Rules
   Create ONE rule from multiple sources saying the same thing
```

### Authority Layer

| Authority | Override Policy | Example Sources |
|-----------|-----------------|-----------------|
| **MANDATORY** | NEVER override. Reviewer auto-fails. | HIPAA, GDPR, Legal |
| **STRONG** | Override requires documented justification | OWASP, Best Practices |
| **DEFAULT** | Engineering baseline. Implicit. | STD-* rules |
| **ADVISORY** | Can be ignored without justification | Suggestions |

### Source Registry Schema

```json
{
  "_meta": {
    "version": "10.10",
    "authority_levels": {...},
    "tiers": {
      "domain": "Business rules, compliance. MANDATORY authority.",
      "professional": "Industry best practices. STRONG authority.",
      "standard": "Engineering plumbing. DEFAULT authority."
    }
  },
  "sources": {
    "STD-ENG": { "tier": "standard", "authority": "DEFAULT" },
    "STD-PRO": { "tier": "professional", "authority": "STRONG" }
  },
  "curated_rules": {
    "DOMAIN_RULES": { "file": "DOMAIN_RULES.md", "id_pattern": "DR-*" }
  }
}
```

### Curated Rule Output Format

```markdown
## [DR-{PREFIX}-{SEQ}] {Imperative Title}
**Text:** {The Rule. MUST/SHALL language only. No "should" or "may".}
**Context:** {One sentence: Why this matters for implementation.}
**Derived From:** [{ORIGINAL-ID}]
**Authority:** {MANDATORY | STRONG | DEFAULT}
```

### CLI Usage

```
# Curate ingested chunks into domain rules
/curate HIPAA
-> Creates DR-HIPAA-01, DR-HIPAA-02, ... in DOMAIN_RULES.md

# View authority registry
/registry
-> Shows all sources with their authority levels

# Full workflow
1. /ingest "Medical_Compliance.pdf" HIPAA    # Ingest → [HIPAA-001]...[HIPAA-047]
2. /curate HIPAA                              # Refine → [DR-HIPAA-01]...[DR-HIPAA-15]
3. /plan_gaps                                 # Plan → Create tasks citing DR-* rules
4. /go                                        # Execute → Worker implements
5. /provenance                                # Verify → Check INTENT matches REALITY
```

### Data Flow

```
External Document
       │
       ▼
/ingest ──────────> [PREFIX-001]...[PREFIX-n] (Raw Chunks)
                           │
                           ▼
/curate ──────────> Curator Agent (The Refinery)
                           │
                    ┌──────┴──────┐
                    │   FLATTEN   │  Remove academic fluff
                    │   HARDEN    │  "should" → "MUST"
                    │   ATOMIZE   │  Split into atomic rules
                    │   TRACE     │  Link to source
                    │   DEDUP     │  Merge redundant
                    └──────┬──────┘
                           │
                           ▼
              [DR-PREFIX-01]...[DR-PREFIX-m]
                    (Curated Domain Rules)
                           │
                           ▼
              docs/sources/DOMAIN_RULES.md
                           │
                           ▼
               Planner creates tasks citing DR-*
                           │
                           ▼
               Worker implements with # Implements [DR-*]
                           │
                           ▼
               Reviewer enforces via Authority Layer
```

### Integration with Reviewer

The Reviewer now checks Authority Level before allowing overrides:

```python
# In review logic:
authority = get_authority_for_source(source_id)

if authority == "MANDATORY":
    # NEVER allow override - auto-fail
    return {"status": "FAIL", "reason": "MANDATORY rule violation"}
elif authority == "STRONG":
    # Require justification in code comment
    if not has_justification_comment(code):
        return {"status": "FAIL", "reason": "STRONG rule override requires justification"}
```

### Status: DEPLOYED

---

## v10.11 "The Gatekeeper" Extensions

### Overview
The Gatekeeper is the enforcement layer that actually stops tasks from completing if they violate authority rules. It's the "Judge" that enforces the rules defined by the "Legislature" (Curator) and tracked by the "Police" (Provenance).

### The Problem Solved
**Before v10.11:** Authority levels were defined but not enforced. Tasks could claim to implement HIPAA but have no code evidence.
**After v10.11:** The Gatekeeper blocks task completion if mandatory rules are not provably implemented.

### Components Added

| Component | Change |
|-----------|--------|
| `override_justification` column | Database field for override reasoning |
| `get_authority_for_source()` | Resolves source ID to authority level |
| `validate_task_completion()` | The Gatekeeper validation logic |
| `add_justification()` | MCP tool for adding override justification |
| `check_gatekeeper()` | MCP tool for pre-checking compliance |
| `/justify <id> 'reason'` | CLI command for override justification |
| `/gatekeeper <id>` | CLI command for compliance pre-check |

### Enforcement Rules

| Authority | Enforcement | Override |
|-----------|-------------|----------|
| **MANDATORY** | MUST have `# Implements [ID]` tag in code | **NEVER** - No exceptions |
| **STRONG** | MUST have code tag OR justification | Allowed with documented reason |
| **DEFAULT** | No enforcement | N/A (pass through) |
| **ADVISORY** | No enforcement | N/A (pass through) |

### Database Schema

```sql
ALTER TABLE tasks ADD COLUMN override_justification TEXT DEFAULT '';
```

Self-healing migration ensures existing databases get the new column.

### Gatekeeper Logic Flow

```
complete_task(task_id) called
         │
         ▼
validate_task_completion(task_id)
         │
         ├── Load task.source_ids
         ├── Load provenance.json
         │
         ▼
For each source_id:
         │
         ├── get_authority_for_source(src_id)
         │         │
         │         ├── DR-* → MANDATORY (refined domain rules)
         │         ├── PRO-* → STRONG (professional)
         │         ├── STD-* → DEFAULT (engineering)
         │         └── HIPAA/LAW/GDPR → MANDATORY
         │
         ▼
    ┌────────────────────────────────────────┐
    │           AUTHORITY CHECK              │
    ├────────────────────────────────────────┤
    │ MANDATORY:                             │
    │   has_evidence? → PASS                 │
    │   no_evidence? → BLOCK (no override)   │
    ├────────────────────────────────────────┤
    │ STRONG:                                │
    │   has_evidence? → PASS                 │
    │   has_justification? → PASS (warning)  │
    │   neither? → BLOCK                     │
    ├────────────────────────────────────────┤
    │ DEFAULT/ADVISORY:                      │
    │   → PASS (no enforcement)              │
    └────────────────────────────────────────┘
         │
         ▼
    ┌─────────┬─────────────┐
    │  PASS   │   BLOCKED   │
    │         │             │
    │ Task    │ Return JSON │
    │ marked  │ with errors │
    │ complete│ and fix     │
    │         │ instructions│
    └─────────┴─────────────┘
```

### CLI Usage

```
# Pre-check compliance before completing
/gatekeeper 105
-> Shows: SOURCES, VIOLATIONS, WARNINGS, FIX instructions

# Add justification to override STRONG rule
/justify 105 'Using Redis instead of SQL for performance requirements'
-> Records justification, allows STRONG override

# Attempting to complete a MANDATORY-violating task
Worker calls complete_task(105)
-> Returns: BLOCKED, MANDATORY VIOLATION, fix instructions
```

### MCP Tool Examples

```python
# Check if task would pass
result = check_gatekeeper(105)
# Returns: {"status": "BLOCKED", "errors": [...], "sources": [...]}

# Add justification for STRONG override
result = add_justification(105, "Using Redis for performance")
# Returns: {"status": "SUCCESS", "justification": "..."}

# complete_task now enforces
result = complete_task(105, "Done", success=True)
# Returns: {"status": "BLOCKED", "reason": "GATEKEEPER_VIOLATION", ...}
# OR: "Task Completed." if all checks pass
```

### Integration with complete_task()

```python
@mcp.tool()
def complete_task(task_id, output, success=True, ...):
    if success:
        # v10.11: THE GATEKEEPER CHECK
        validation = validate_task_completion(task_id)

        if not validation["ok"]:
            return json.dumps({
                "status": "BLOCKED",
                "reason": "GATEKEEPER_VIOLATION",
                "errors": validation["errors"],
                "fix_instructions": "Add # Implements [ID] OR /justify"
            })

    # ... proceed with normal completion ...
```

### The Escape Hatch

For STRONG rules that cannot be implemented as designed:

```
1. /gatekeeper 105           # See what's blocking
2. /justify 105 'reason'     # Document the override
3. /go                       # Task can now complete
```

MANDATORY rules have NO escape hatch - you must implement the code.

### Why This Matters

1. **Compliance Teeth:** Authority levels are enforced, not advisory
2. **Audit Trail:** Justifications are timestamped and persisted
3. **Flexibility:** STRONG rules can be overridden with documentation
4. **Safety:** MANDATORY rules (legal/regulatory) cannot be bypassed

### Status: DEPLOYED

---

## v10.11.2 "The Authority Resolver & Test Gate" Extensions

### Overview
Enhances the Gatekeeper with smart authority resolution and test coverage enforcement. Without this, derived rules (DR-HIPAA-01) wouldn't match their source registry entries (HIPAA), causing mandatory rules to be treated as standard suggestions.

### Components Added

| Component | Change |
|-----------|--------|
| `resolve_authority()` | Smart longest-prefix-match for Source ID → Registry lookup |
| `find_paired_test()` | Helper to find TEST tasks sharing source_ids |
| `validate_task_completion()` | Now includes TEST GATE enforcement |
| `check_gatekeeper()` | Enhanced with test_gate status in response |

### Smart Authority Resolution

**The Problem:**
```
Source ID:    DR-HIPAA-01
Registry Key: HIPAA

Without resolver: DR-HIPAA-01 → NO MATCH → DEFAULT authority (wrong!)
With resolver:    DR-HIPAA-01 → HIPAA → MANDATORY authority (correct!)
```

**Resolution Algorithm:**
```python
def resolve_authority(source_id: str, registry: dict) -> dict:
    """
    1. Clean and normalize source_id
    2. Extract domain hint from DR-* prefix (DR-HIPAA-01 → "HIPAA")
    3. Longest-prefix-match against registry keys
    4. Return matched authority config or defaults
    """
    # Prefix-based defaults
    if source_id.startswith("DR-"):
        default_tier = "domain"
        default_authority = "MANDATORY"
    elif source_id.startswith("PRO-"):
        default_tier = "professional"
        default_authority = "STRONG"
    elif source_id.startswith("STD-"):
        default_tier = "standard"
        default_authority = "DEFAULT"
    # ... longest-prefix-match logic
```

### Test Gate Enforcement

**The Rule:** Tasks with testable archetypes (LOGIC, API, SEC, DB) that cite domain or professional sources MUST have a paired TEST task.

**Testable Archetypes:**
- `[LOGIC]` - Business logic implementation
- `[API]` - API endpoints
- `[SEC]` - Security-critical code
- `[DB]` - Database operations

**Enforcement Flow:**
```
validate_task_completion(task_id)
         │
         ├── Load task archetype
         ├── Load task source_ids
         │
         ▼
Is archetype in [LOGIC, API, SEC, DB]?
         │
         ├── NO → Skip test gate
         │
         └── YES → Has domain/professional sources?
                    │
                    ├── NO → Skip test gate
                    │
                    └── YES → find_paired_test(source_ids)
                               │
                               ├── Found TEST task → PASS
                               │
                               └── No TEST task → BLOCK
                                   "TEST GATE VIOLATION"
```

**Test Pairing Logic:**
```python
def find_paired_test(source_ids: list, task_archetype: str = None) -> dict:
    """
    Searches for [TEST] tasks that share any source_ids with the target.

    Returns:
        {"found": bool, "task": dict or None, "status": str or None}
    """
    # Find TEST tasks with overlapping source_ids
    for test_task in test_tasks:
        if source_ids_overlap(test_task.source_ids, source_ids):
            return {"found": True, "task": test_task, "status": ...}
    return {"found": False, "task": None, "status": None}
```

### CLI Impact

**/gatekeeper** now includes test_gate status:
```
/gatekeeper 105

⛔ GATEKEEPER: BLOCKED

SOURCES:
  [DR-HIPAA-01] MANDATORY
  [STD-SEC-01] DEFAULT

VIOLATIONS:
  ⛔ TEST GATE VIOLATION: Task [105] (LOGIC) cites domain/professional
     sources but has no paired [TEST] task.

FIX:
  TEST GATE: Create a [TEST] task with matching source_ids.
```

### Data Flow

```
Planner creates:
  T-001: [LOGIC] Implement consent validation
         source_ids: [DR-HIPAA-01]

  T-002: [TEST] Test consent validation
         source_ids: [DR-HIPAA-01]  ← Same source!
         deps: [1]
                    │
                    ▼
Worker completes T-001
                    │
                    ▼
complete_task(1, output)
                    │
                    ▼
validate_task_completion(1)
                    │
     ┌──────────────┴──────────────┐
     ▼                             ▼
resolve_authority("DR-HIPAA-01")   find_paired_test(["DR-HIPAA-01"])
     │                             │
     ▼                             ▼
MANDATORY (via HIPAA match)        Found: T-002 [TEST]
     │                             │
     └──────────────┬──────────────┘
                    ▼
              ALL GATES PASS
                    │
                    ▼
              Task Completed
```

### Why This Matters

1. **Smart Matching:** DR-HIPAA-01 correctly inherits HIPAA's MANDATORY authority
2. **Test Coverage:** Domain-critical code cannot skip testing
3. **Planner Integration:** v10.6 PAIRING RULE now has enforcement teeth
4. **Compliance Chain:** Book → Rule → Task → Code → Test (fully traced)

### Status: DEPLOYED

---

## v10.12 + v10.12.2 "The Safe Autobahn" Extensions

### Overview
Implements the Review Packet system with Safety Locks. Tasks must pass through a formal review process before being marked COMPLETE. Prevents stale approvals and ensures the Gatekeeper is re-validated before final sign-off.

### The Problem Solved
**Before v10.12:** Tasks could be marked COMPLETE without formal review. Code could change after approval but before the status update.
**After v10.12:** Only `submit_review_decision()` can mark tasks COMPLETE, and it re-runs the Gatekeeper to prevent drift.

### Components Added

| Component | Change |
|-----------|--------|
| `hash_dict()` | Creates stable hash for freshness detection |
| `create_review_packet()` | Generates frozen Evidence Brief |
| `generate_review_packet()` | MCP tool to create review packets |
| `submit_review_decision()` | The Gavel - only way to COMPLETE a task |
| `list_pending_reviews()` | MCP tool listing reviews with stale detection |
| `review_decision` column | Database field for decision (APPROVE/REJECT) |
| `review_notes` column | Database field for review notes |
| `/reviews` command | CLI to show pending reviews |
| `/approve` command | CLI to approve reviewed tasks |
| `/reject` command | CLI to reject tasks for rework |

### Database Schema (v10.12)

```sql
ALTER TABLE tasks ADD COLUMN review_decision TEXT DEFAULT '';
ALTER TABLE tasks ADD COLUMN review_notes TEXT DEFAULT '';
```

### Task Lifecycle with Review

```
PENDING → IN_PROGRESS → REVIEWING → COMPLETE
                │           │
                │           └── REJECT → IN_PROGRESS (rework)
                │
                └── (No longer can skip to COMPLETE)
```

### Review Packet Structure

```json
{
  "meta": {
    "task_id": 105,
    "generated_at": "2024-01-15T14:30:00",
    "snapshot_hash": "a1b2c3d4...",
    "version": "10.12.2"
  },
  "claims": {
    "description": "Implement consent validation",
    "source_ids": ["DR-HIPAA-01"],
    "archetype": "LOGIC",
    "dependencies": [1, 2],
    "override_justification": ""
  },
  "evidence": {
    "code_refs": {
      "DR-HIPAA-01": ["src/consent.py:45"]
    },
    "paired_test": {
      "id": 106,
      "status": "COMPLETE"
    }
  },
  "gatekeeper": {
    "ok": true,
    "errors": [],
    "warnings": []
  }
}
```

### v10.12.2 Safety Locks

**1. Status Check**
```python
if task["status"] != "reviewing":
    return "REJECTED: Task is not in REVIEWING state"
```

**2. Gatekeeper Re-Validation on APPROVE**
```python
if decision == "APPROVE":
    validation = validate_task_completion(task_id)
    if not validation["ok"]:
        return "BLOCKED: State drift detected"
```

**3. Stale Detection**
```python
# Compare current task hash vs packet hash
current_hash = hash_dict(current_snapshot)
is_stale = current_hash != packet["meta"]["snapshot_hash"]
```

**4. Auto-Cleanup**
```python
# After decision, remove the packet
if os.path.exists(packet_path):
    os.remove(packet_path)
```

### CLI Commands

```
/reviews                    # List pending reviews with stale detection
/approve 105 'Looks good'  # Approve and mark COMPLETE
/reject 105 'Needs tests'  # Reject and return to IN_PROGRESS
```

### /reviews Output Example

```
⚖️ REVIEW QUEUE (v10.12)
─────────────────────────────────────
Pending: 3  |  Stale: 1

✅ T-105
   Implement consent validation
   Sources: DR-HIPAA-01
   Age: 2.5h
   Test: T-106 [COMPLETE]

⛔ T-107 [STALE]
   Add encryption layer
   Sources: DR-SEC-02
   Age: 26.3h
   Test: T-108 [PENDING]
   ⚠️ STALE - Task changed since packet was generated

─────────────────────────────────────
Use: /approve <id> 'notes'  or  /reject <id> 'reason'
```

### Data Flow

```
Worker completes work
         │
         ▼
generate_review_packet(task_id)
         │
         ├── Gather evidence (provenance, tests)
         ├── Create snapshot hash
         ├── Run gatekeeper validation
         ├── Save to control/state/reviews/T-{id}.json
         └── Set status = REVIEWING
                    │
                    ▼
/reviews ─────────────────────────────────────────────
         │                                            │
         │  Reviewer examines packet                  │
         │  ├── Check evidence                        │
         │  ├── Verify test coverage                  │
         │  └── Review gatekeeper status              │
         │                                            │
         ▼                                            ▼
/approve {id} 'notes'                    /reject {id} 'reason'
         │                                            │
         ▼                                            ▼
submit_review_decision(APPROVE)       submit_review_decision(REJECT)
         │                                            │
         ├── Check status == REVIEWING                ├── Check status == REVIEWING
         ├── Re-run Gatekeeper (drift check)          │
         ├── If OK: status = COMPLETE                 └── status = IN_PROGRESS
         └── Cleanup packet file                           (rework loop)
                    │
                    ▼
              TASK COMPLETE
              (Only path to completion)
```

### Why This Matters

1. **Stale Prevention:** Can't approve based on outdated evidence
2. **Data Hygiene:** Packets auto-cleanup after decision
3. **Process Lock:** Only the Gavel can grant COMPLETE status
4. **Drift Detection:** Re-validates Gatekeeper on every approval
5. **Audit Trail:** Decisions and notes are persisted

### Status: DEPLOYED
