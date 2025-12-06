"""
Atomic Mesh v9.0 - Compliance Tools
Enterprise-grade compliance enforcement for Code Book adherence.

Features:
- Import Whitelist: Block unauthorized libraries
- Citation Verifier: Ensure @citation tags point to real sections
- Incident Logger: Auto-log violations to COMPLIANCE_REPORT.md
- Traceability Matrix: Decision → Rule mapping for audits

For: Fintech, Medtech, Legaltech, Industrial Standards
"""

import os
import re
import csv
from datetime import datetime
from typing import Dict, List, Optional

# =============================================================================
# CONFIGURATION
# =============================================================================

# Standard library exceptions (never blocked)
STANDARD_LIB_WHITELIST = [
    "os", "sys", "json", "typing", "datetime", "time", "re", "math",
    "decimal", "collections", "pathlib", "functools", "itertools",
    "enum", "dataclasses", "abc", "copy", "io", "logging", "asyncio",
    "threading", "subprocess", "csv", "hashlib", "secrets", "uuid"
]

# Citation patterns to detect
CITATION_PATTERNS = [
    r'@citation\s+([^\s\n]+)',           # @citation 3.4.2
    r'Ref:\s*Section\s+([^\s\n]+)',       # Ref: Section 3.4.2
    r'Implements\s+Section\s+([^\s\n]+)', # Implements Section 3.4.2
    r'\[Citation:\s*([^\]]+)\]',          # [Citation: 3.4.2]
]


# =============================================================================
# LAYER 1: IMPORT WHITELIST
# =============================================================================

def verify_import_whitelist(code_content: str, project_root: str) -> Dict:
    """
    Ensures code only imports libraries listed in TECH_STACK.md.
    
    The "Closed World" principle: If it's not in the whitelist, it's forbidden.
    
    Args:
        code_content: The code to analyze
        project_root: Project root directory
    
    Returns:
        {"valid": bool, "error": str (if invalid), "imports": list}
    """
    # 1. Extract imports from code
    import_patterns = [
        r'^\s*import\s+([a-zA-Z0-9_]+)',           # import os
        r'^\s*from\s+([a-zA-Z0-9_]+)\s+import',    # from os import path
    ]
    
    imports = set()
    for pattern in import_patterns:
        matches = re.findall(pattern, code_content, re.MULTILINE)
        imports.update(matches)
    
    if not imports:
        return {"valid": True, "imports": [], "message": "No imports found"}
    
    # 2. Load Whitelist from TECH_STACK.md
    stack_path = os.path.join(project_root, "docs", "TECH_STACK.md")
    
    if not os.path.exists(stack_path):
        return {
            "valid": True,
            "imports": list(imports),
            "warning": "No TECH_STACK.md found. Whitelist check skipped."
        }
    
    with open(stack_path, 'r', encoding='utf-8') as f:
        stack_content = f.read().lower()
    
    # 3. Check each import
    violations = []
    for lib in imports:
        lib_lower = lib.lower()
        
        # Skip standard library
        if lib_lower in STANDARD_LIB_WHITELIST:
            continue
        
        # Check if explicitly approved in TECH_STACK.md
        if lib_lower not in stack_content:
            violations.append(lib)
    
    if violations:
        return {
            "valid": False,
            "imports": list(imports),
            "violations": violations,
            "error": f"Unauthorized Imports: {violations}. Add to docs/TECH_STACK.md to approve."
        }
    
    return {"valid": True, "imports": list(imports)}


# =============================================================================
# LAYER 2: CITATION VERIFIER
# =============================================================================

def extract_citations(code_content: str) -> List[str]:
    """
    Extracts all citation references from code.
    
    Supported formats:
    - @citation 3.4.2
    - Ref: Section 3.4.2
    - Implements Section 3.4.2
    - [Citation: 3.4.2]
    """
    citations = []
    for pattern in CITATION_PATTERNS:
        matches = re.findall(pattern, code_content, re.IGNORECASE)
        citations.extend(matches)
    
    return list(set(citations))  # Deduplicate


def verify_citations(code_content: str, project_root: str, strict: bool = True) -> Dict:
    """
    Ensures @citation tags point to real sections in CODE_BOOK.md.
    
    In Compliance Mode, every core function MUST cite its source.
    
    Args:
        code_content: The code to analyze
        project_root: Project root directory
        strict: If True, missing citations are errors (not warnings)
    
    Returns:
        {"valid": bool, "error": str (if invalid), "citations": list}
    """
    citations = extract_citations(code_content)
    
    # Check if citations exist
    if not citations:
        if strict:
            return {
                "valid": False,
                "citations": [],
                "error": "Compliance Violation: No @citation tags found. Every core function must cite its source."
            }
        else:
            return {
                "valid": True,
                "citations": [],
                "warning": "No citations found. Consider adding @citation tags for traceability."
            }
    
    # Load Code Book
    book_path = os.path.join(project_root, "docs", "CODE_BOOK.md")
    
    if not os.path.exists(book_path):
        return {
            "valid": False,
            "citations": citations,
            "error": "CODE_BOOK.md not found. Cannot verify citation targets."
        }
    
    with open(book_path, 'r', encoding='utf-8') as f:
        book_content = f.read()
    
    # Verify each citation exists in the book
    missing = []
    found = []
    
    for cite in citations:
        # Look for section headers or references
        patterns_to_check = [
            cite,                    # Direct match
            f"## {cite}",            # Markdown header
            f"### {cite}",           # Markdown subheader
            f"Section {cite}",       # Section reference
            f"Article {cite}",       # Legal article
            f"Rule {cite}",          # Rule reference
        ]
        
        matched = False
        for pattern in patterns_to_check:
            if pattern in book_content:
                matched = True
                break
        
        if matched:
            found.append(cite)
        else:
            missing.append(cite)
    
    if missing:
        return {
            "valid": False,
            "citations": citations,
            "found": found,
            "missing": missing,
            "error": f"Citation targets not found in CODE_BOOK.md: {missing}"
        }
    
    return {"valid": True, "citations": citations, "all_verified": True}


def get_section_text(code_book_path: str, section_id: str) -> Optional[str]:
    """
    Extracts the text content of a specific section from CODE_BOOK.md.
    Used by QA3 Redliner to compare implementation vs rule text.
    
    Args:
        code_book_path: Path to CODE_BOOK.md
        section_id: The section identifier (e.g., "3.4.2")
    
    Returns:
        Section text or None if not found
    """
    if not os.path.exists(code_book_path):
        return None
    
    with open(code_book_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find section header
    patterns = [
        rf'##\s*{re.escape(section_id)}[^\n]*\n(.*?)(?=\n##|\Z)',
        rf'###\s*{re.escape(section_id)}[^\n]*\n(.*?)(?=\n###|\n##|\Z)',
        rf'Section\s*{re.escape(section_id)}[^\n]*\n(.*?)(?=\nSection|\n##|\Z)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, content, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip()
    
    return None


# =============================================================================
# LAYER 3: INCIDENT LOGGER
# =============================================================================

def log_compliance_incident(
    violation_type: str,
    details: str,
    file_path: str = "N/A",
    severity: str = "HIGH"
) -> str:
    """
    Auto-logs violations to docs/incidents/COMPLIANCE_REPORT.md.
    
    This creates an immutable audit trail for compliance reviews.
    
    Args:
        violation_type: Category (e.g., "Unauthorized Import", "Missing Citation")
        details: Specific details of the violation
        file_path: File that triggered the violation
        severity: HIGH, MEDIUM, LOW
    
    Returns:
        Incident ID
    """
    incident_dir = os.path.join(os.getcwd(), "docs", "incidents")
    os.makedirs(incident_dir, exist_ok=True)
    
    report_path = os.path.join(incident_dir, "COMPLIANCE_REPORT.md")
    
    incident_id = int(datetime.now().timestamp())
    timestamp = datetime.now().isoformat()
    
    entry = f"""
## Incident #{incident_id}
- **Date:** {timestamp}
- **Severity:** {severity}
- **Violation Type:** {violation_type}
- **File:** {file_path}
- **Details:** {details}
- **Status:** Auto-Logged by Atomic Mesh v9.0
- **Resolution:** Pending

---
"""
    
    # Create or append
    file_exists = os.path.exists(report_path)
    
    with open(report_path, 'a', encoding='utf-8') as f:
        if not file_exists:
            f.write("# Compliance Incident Log\n\n")
            f.write("This log is auto-generated by Atomic Mesh v9.0 Compliance Suite.\n\n")
            f.write("---\n")
        f.write(entry)
    
    print(f"   ⚠️ COMPLIANCE INCIDENT LOGGED: #{incident_id}")
    
    return str(incident_id)


# =============================================================================
# LAYER 3: TRACEABILITY MATRIX
# =============================================================================

def append_traceability(
    decision: str,
    citation: str,
    file_path: str = "",
    status: str = "Implemented"
) -> None:
    """
    Logs Decision → Citation mapping to audit/TRACEABILITY_MATRIX.csv.
    
    This creates a complete audit trail showing how each implementation
    decision traces back to the Code Book.
    
    Args:
        decision: What was implemented (e.g., "calculate_tax function")
        citation: Which rule it implements (e.g., "Section 3.4.2")
        file_path: File containing the implementation
        status: Implementation status
    """
    audit_dir = os.path.join(os.getcwd(), "audit")
    os.makedirs(audit_dir, exist_ok=True)
    
    matrix_path = os.path.join(audit_dir, "TRACEABILITY_MATRIX.csv")
    
    file_exists = os.path.exists(matrix_path)
    
    with open(matrix_path, 'a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        
        if not file_exists:
            writer.writerow([
                "Timestamp",
                "Decision/Implementation",
                "Citation/Rule Reference",
                "File",
                "Status",
                "Verified By"
            ])
        
        writer.writerow([
            datetime.now().isoformat(),
            decision,
            citation,
            file_path,
            status,
            "Atomic Mesh v9.0"
        ])
    
    print(f"   📋 Traceability logged: {decision} → {citation}")


# =============================================================================
# COMPLIANCE CHECK RUNNER
# =============================================================================

def run_compliance_checks(code_content: str, project_root: str = None) -> Dict:
    """
    Runs all compliance checks on code.
    
    This is the main entry point for the Compliance Suite.
    
    Args:
        code_content: The code to analyze
        project_root: Project root (defaults to cwd)
    
    Returns:
        {"passed": bool, "checks": dict, "issues": list}
    """
    if project_root is None:
        project_root = os.getcwd()
    
    print("\n🔒 COMPLIANCE PRE-FLIGHT (v9.0)")
    print("=" * 50)
    
    issues = []
    checks = {}
    
    # Check 1: Import Whitelist
    print("   1. Import Whitelist Check...")
    whitelist_result = verify_import_whitelist(code_content, project_root)
    checks["import_whitelist"] = whitelist_result
    
    if not whitelist_result.get("valid", True):
        issues.append(whitelist_result.get("error"))
        log_compliance_incident("Unauthorized Import", whitelist_result.get("error", ""))
        print(f"      ❌ {whitelist_result.get('error')}")
    else:
        print(f"      ✅ Passed ({len(whitelist_result.get('imports', []))} imports verified)")
    
    # Check 2: Citation Verification
    print("   2. Citation Verification...")
    citation_result = verify_citations(code_content, project_root, strict=True)
    checks["citations"] = citation_result
    
    if not citation_result.get("valid", True):
        issues.append(citation_result.get("error"))
        log_compliance_incident("Citation Missing/Invalid", citation_result.get("error", ""))
        print(f"      ❌ {citation_result.get('error')}")
    else:
        citations = citation_result.get("citations", [])
        print(f"      ✅ Passed ({len(citations)} citations verified)")
    
    print("=" * 50)
    
    passed = len(issues) == 0
    
    if passed:
        print("   ✅ COMPLIANCE PRE-FLIGHT: PASSED")
    else:
        print(f"   ❌ COMPLIANCE PRE-FLIGHT: FAILED ({len(issues)} issues)")
    
    print("")
    
    return {
        "passed": passed,
        "checks": checks,
        "issues": issues
    }
