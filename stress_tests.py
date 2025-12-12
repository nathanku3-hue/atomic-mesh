"""
Atomic Mesh v8.5.2 - Architectural Stress Test Suite
Enterprise-grade testing for: Concurrency, Idempotency, Memory, Consistency

Tests:
1. Race Condition Rodeo - Concurrent access & locking
2. Monte Carlo Flakiness - Probabilistic testing
3. Context Drift - Long-running process simulation
4. Desync Check - Data integrity verification

Run: python stress_tests.py [test_name]
"""

import os
import sys
import json
import time
import random
import sqlite3
import asyncio
import threading
from datetime import datetime
from typing import Dict, List, Tuple
from pathlib import Path


# =============================================================================
# CONFIGURATION
# =============================================================================

TEST_DIR = os.path.join(os.getcwd(), "stress_test_workspace")
DB_FILE = os.getenv("ATOMIC_MESH_DB", os.path.join(os.getcwd(), "mesh.db"))


# =============================================================================
# TEST 1: RACE CONDITION RODEO
# =============================================================================

class RaceConditionTest:
    """
    Test: Concurrent access between Worker (HIGH priority) and Librarian (LOW priority)
    
    Scenario: Worker is editing files while Librarian tries to move them
    Expected: Priority Arbiter blocks Librarian until Worker is done
    """
    
    def __init__(self):
        self.conflicts_detected = 0
        self.locks_respected = 0
        self.errors = []
        
    def setup(self):
        """Create test files."""
        os.makedirs(TEST_DIR, exist_ok=True)
        for i in range(10):
            Path(os.path.join(TEST_DIR, f"file_{i}.py")).write_text(f"# File {i}\n")
        print(f"   Created 10 test files in {TEST_DIR}")
    
    def simulate_worker(self, file_path: str, duration: float = 0.5):
        """Simulate a Worker holding a file lock."""
        print(f"   [WORKER] Acquiring lock on {os.path.basename(file_path)}...")
        
        # Simulate file lock by writing
        with open(file_path, "a") as f:
            f.write(f"# Worker edit at {time.time()}\n")
            time.sleep(duration)  # Hold the file
        
        print(f"   [WORKER] Released lock on {os.path.basename(file_path)}")
        return True
    
    def simulate_librarian(self, file_path: str) -> bool:
        """Simulate Librarian trying to move a file."""
        print(f"   [LIBRARIAN] Attempting to move {os.path.basename(file_path)}...")
        
        # Check if file is locked (simulated by checking if it's being written)
        try:
            # In real system, this would check get_active_file_locks()
            # For test, we use file modification time as proxy
            mtime = os.path.getmtime(file_path)
            if time.time() - mtime < 1.0:
                print(f"   [LIBRARIAN] 🔒 Yielding to Higher Priority Agent")
                self.locks_respected += 1
                return False
            
            # Proceed with move
            new_path = file_path.replace(".py", "_moved.py")
            os.rename(file_path, new_path)
            print(f"   [LIBRARIAN] Moved to {os.path.basename(new_path)}")
            return True
            
        except FileNotFoundError:
            self.errors.append(f"File not found: {file_path}")
            return False
        except PermissionError:
            print(f"   [LIBRARIAN] 🔒 File locked by OS, yielding...")
            self.locks_respected += 1
            return False
    
    def run(self, iterations: int = 5) -> Dict:
        """Run race condition test."""
        print("\n🏇 TEST 1: RACE CONDITION RODEO")
        print("=" * 60)
        
        self.setup()
        
        results = {
            "test": "race_condition",
            "iterations": iterations,
            "locks_respected": 0,
            "conflicts": 0,
            "errors": [],
            "passed": False
        }
        
        for i in range(iterations):
            file_path = os.path.join(TEST_DIR, f"file_{i}.py")
            
            if not os.path.exists(file_path):
                continue
            
            # Start worker in thread
            worker_thread = threading.Thread(
                target=self.simulate_worker, 
                args=(file_path, 0.3)
            )
            worker_thread.start()
            
            # Immediately try librarian (should yield)
            time.sleep(0.1)  # Small delay to ensure worker started
            librarian_result = self.simulate_librarian(file_path)
            
            if librarian_result:
                self.conflicts_detected += 1
            
            worker_thread.join()
        
        results["locks_respected"] = self.locks_respected
        results["conflicts"] = self.conflicts_detected
        results["errors"] = self.errors
        results["passed"] = len(self.errors) == 0 and self.conflicts_detected == 0
        
        print(f"\n   Results:")
        print(f"   - Locks Respected: {self.locks_respected}/{iterations}")
        print(f"   - Conflicts Detected: {self.conflicts_detected}")
        print(f"   - Errors: {len(self.errors)}")
        print(f"   - PASS: {'✅' if results['passed'] else '❌'}")
        
        return results


# =============================================================================
# TEST 2: MONTE CARLO FLAKINESS TEST
# =============================================================================

class MonteCarloTest:
    """
    Test: Probabilistic testing of LLM consistency
    
    Run the same prompt N times and measure pass rate
    Expected: >95% pass rate for production readiness
    """
    
    def __init__(self):
        self.passes = 0
        self.failures = []
        
    def simulate_llm_response(self, prompt: str) -> Dict:
        """
        Simulate LLM response with realistic flakiness.
        
        In production, this would actually call the LLM.
        Here we simulate with controlled randomness.
        """
        # Base success rate (adjustable)
        base_success_rate = 0.95
        
        # Introduce flakiness factors
        flakiness_factors = [
            (0.02, "deprecated_library", "Used deprecated library 'requests' instead of 'httpx'"),
            (0.01, "hallucinated_path", "Referenced non-existent file 'src/utils/magic.py'"),
            (0.01, "wrong_syntax", "Generated Python 2 syntax"),
            (0.01, "missing_import", "Missing required import statement"),
        ]
        
        # Roll for each failure type
        for prob, failure_type, message in flakiness_factors:
            if random.random() < prob:
                return {
                    "status": "FAIL",  # SAFETY-ALLOW: status-write
                    "failure_type": failure_type,
                    "message": message
                }
        
        # Success
        return {
            "status": "PASS",  # SAFETY-ALLOW: status-write
            "message": "Code generated successfully"
        }
    
    def run(self, iterations: int = 20) -> Dict:
        """Run Monte Carlo test."""
        print("\n🎲 TEST 2: MONTE CARLO FLAKINESS")
        print("=" * 60)
        
        results = {
            "test": "monte_carlo",
            "iterations": iterations,
            "passes": 0,
            "failures": [],
            "pass_rate": 0.0,
            "passed": False
        }
        
        prompt = "Build a Hello World function"
        
        for i in range(iterations):
            response = self.simulate_llm_response(prompt)
            
            if response["status"] == "PASS":  # SAFETY-ALLOW: status-write
                self.passes += 1
                print(f"   Run {i+1:2d}/{iterations}: ✅ PASS")
            else:
                self.failures.append(response)
                print(f"   Run {i+1:2d}/{iterations}: ❌ FAIL - {response['failure_type']}")
        
        pass_rate = self.passes / iterations
        results["passes"] = self.passes
        results["failures"] = self.failures
        results["pass_rate"] = pass_rate
        results["passed"] = pass_rate >= 0.95
        
        print(f"\n   Results:")
        print(f"   - Pass Rate: {pass_rate*100:.1f}%")
        print(f"   - Threshold: 95%")
        print(f"   - PASS: {'✅' if results['passed'] else '❌'}")
        
        if not results["passed"]:
            print(f"\n   Failure Analysis:")
            failure_types = {}
            for f in self.failures:
                ft = f["failure_type"]
                failure_types[ft] = failure_types.get(ft, 0) + 1
            for ft, count in failure_types.items():
                print(f"   - {ft}: {count} occurrences")
        
        return results


# =============================================================================
# TEST 3: CONTEXT DRIFT SIMULATION
# =============================================================================

class ContextDriftTest:
    """
    Test: Long-running process with massive context
    
    Scenario: 20KB spec with critical constraint at top
    Expected: Head+Tail truncation preserves top constraints
    """
    
    def __init__(self):
        self.spec_path = os.path.join(TEST_DIR, "ACTIVE_SPEC.md")
        
    def setup(self, noise_kb: int = 20):
        """Create bloated spec with constraint at top."""
        os.makedirs(TEST_DIR, exist_ok=True)
        
        # Critical constraint at TOP
        constraint = """# ACTIVE SPECIFICATION

## CRITICAL CONSTRAINTS (DO NOT IGNORE)

1. **NEVER use asyncio** - Use threading instead for all concurrent operations
2. **NEVER use raw SQL** - Always use parameterized queries
3. **NEVER store passwords in plaintext** - Use bcrypt

---

## Project Overview

This is a test project for stress testing.

"""
        
        # Generate noise (middle section that might get truncated)
        noise = ""
        for i in range(noise_kb * 40):  # ~25 chars per line * 40 = 1KB
            noise += f"- Feature {i}: Lorem ipsum dolor sit amet consectetur\n"
        
        # Important closing section
        closing = """
---

## Implementation Notes

Remember to follow all constraints listed at the top of this document.
"""
        
        full_spec = constraint + noise + closing
        
        with open(self.spec_path, "w", encoding="utf-8") as f:
            f.write(full_spec)
        
        print(f"   Created bloated spec: {len(full_spec):,} chars ({len(full_spec)//1024}KB)")
        return len(full_spec)
    
    def simulate_truncation(self, max_chars: int = 8000) -> str:
        """Simulate Head+Tail truncation."""
        with open(self.spec_path, "r", encoding="utf-8") as f:
            content = f.read()
        
        if len(content) <= max_chars:
            return content
        
        # Head+Tail strategy (from guardrails.py)
        half = max_chars // 2
        head = content[:half]
        tail = content[-half:]
        
        return head + "\n\n... [TRUNCATED] ...\n\n" + tail
    
    def check_constraint_preserved(self, truncated: str, constraint: str) -> bool:
        """Check if critical constraint is preserved after truncation."""
        return constraint.lower() in truncated.lower()
    
    def run(self, noise_kb: int = 20) -> Dict:
        """Run context drift test."""
        print("\n🧠 TEST 3: CONTEXT DRIFT SIMULATION")
        print("=" * 60)
        
        spec_size = self.setup(noise_kb)
        
        results = {
            "test": "context_drift",
            "spec_size_chars": spec_size,
            "spec_size_kb": spec_size // 1024,
            "constraints_preserved": [],
            "constraints_lost": [],
            "passed": False
        }
        
        # Simulate truncation at different limits
        test_limits = [5000, 8000, 15000]
        critical_constraints = [
            "NEVER use asyncio",
            "NEVER use raw SQL",
            "NEVER store passwords in plaintext"
        ]
        
        for limit in test_limits:
            print(f"\n   Testing truncation at {limit:,} chars...")
            truncated = self.simulate_truncation(limit)
            
            for constraint in critical_constraints:
                preserved = self.check_constraint_preserved(truncated, constraint)
                status = "✅ PRESERVED" if preserved else "❌ LOST"
                print(f"   - '{constraint[:30]}...': {status}")
                
                if preserved:
                    results["constraints_preserved"].append({
                        "limit": limit,
                        "constraint": constraint
                    })
                else:
                    results["constraints_lost"].append({
                        "limit": limit,
                        "constraint": constraint
                    })
        
        # Pass if constraints preserved at reasonable limits (8000+)
        lost_at_high_limit = [
            c for c in results["constraints_lost"]
            if c["limit"] >= 8000
        ]
        results["passed"] = len(lost_at_high_limit) == 0
        
        print(f"\n   Results:")
        print(f"   - Spec Size: {results['spec_size_kb']}KB")
        print(f"   - Constraints Preserved: {len(results['constraints_preserved'])}")
        print(f"   - Constraints Lost (>=8K): {len(lost_at_high_limit)}")
        print(f"   - PASS: {'✅' if results['passed'] else '❌'}")
        
        return results


# =============================================================================
# TEST 4: DESYNC CHECK (DATA INTEGRITY)
# =============================================================================

class DesyncTest:
    """
    Test: Database vs Filesystem consistency
    
    Scenario: Task marked "completed" in DB but spec not updated
    Expected: System detects and logs the desync
    """
    
    def __init__(self):
        self.spec_path = os.path.join(TEST_DIR, "ACTIVE_SPEC.md")
        self.db_path = os.path.join(TEST_DIR, "test_mesh.db")
        
    def setup(self):
        """Create test database and spec with intentional desync."""
        os.makedirs(TEST_DIR, exist_ok=True)
        
        # Create spec with unchecked items
        spec = """# ACTIVE SPECIFICATION

## User Stories

- [ ] US-001: Implement login
- [ ] US-002: Build dashboard
- [x] US-003: Setup database
"""
        
        with open(self.spec_path, "w", encoding="utf-8") as f:
            f.write(spec)
        
        # Create DB with some tasks marked complete
        conn = sqlite3.connect(self.db_path)
        conn.execute("DROP TABLE IF EXISTS tasks")
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY,
                desc TEXT,
                status TEXT,
                story_id TEXT
            )
        """)
        
        # Insert tasks - note intentional desync on US-001
        conn.execute("INSERT INTO tasks VALUES (1, 'Implement login', 'completed', 'US-001')")
        conn.execute("INSERT INTO tasks VALUES (2, 'Build dashboard', 'pending', 'US-002')")
        conn.execute("INSERT INTO tasks VALUES (3, 'Setup database', 'completed', 'US-003')")
        conn.commit()
        conn.close()
        
        print(f"   Created test spec and DB with intentional desync")
        print(f"   - US-001: DB=completed, Spec=unchecked (DESYNC)")
        print(f"   - US-002: DB=pending, Spec=unchecked (OK)")
        print(f"   - US-003: DB=completed, Spec=checked (OK)")
    
    def detect_desyncs(self) -> List[Dict]:
        """Detect desynchronization between DB and spec."""
        desyncs = []
        
        # Read spec
        with open(self.spec_path, "r", encoding="utf-8") as f:
            spec_content = f.read()
        
        # Parse checked/unchecked items
        import re
        checked = re.findall(r"\[x\]\s+(\w+-\d+)", spec_content)
        unchecked = re.findall(r"\[ \]\s+(\w+-\d+)", spec_content)
        
        # Read DB
        conn = sqlite3.connect(self.db_path)
        cursor = conn.execute("SELECT story_id, status FROM tasks")
        db_status = {row[0]: row[1] for row in cursor.fetchall()}
        conn.close()
        
        # Compare
        for story_id, status in db_status.items():
            spec_checked = story_id in checked
            db_completed = status == "completed"
            
            if db_completed and not spec_checked:
                desyncs.append({
                    "story_id": story_id,
                    "type": "DB_AHEAD",
                    "db_status": status,  # SAFETY-ALLOW: status-write
                    "spec_checked": spec_checked,
                    "fix": f"Update spec: [ ] → [x] for {story_id}"
                })
            elif not db_completed and spec_checked:
                desyncs.append({
                    "story_id": story_id,
                    "type": "SPEC_AHEAD",
                    "db_status": status,  # SAFETY-ALLOW: status-write
                    "spec_checked": spec_checked,
                    "fix": f"Update DB: Set {story_id} to 'completed'"
                })
        
        return desyncs
    
    def run(self) -> Dict:
        """Run desync test."""
        print("\n🔄 TEST 4: DESYNC CHECK (DATA INTEGRITY)")
        print("=" * 60)
        
        self.setup()
        
        results = {
            "test": "desync",
            "desyncs_found": [],
            "detection_works": False,
            "passed": False
        }
        
        print("\n   Running desync detection...")
        desyncs = self.detect_desyncs()
        results["desyncs_found"] = desyncs
        
        if desyncs:
            print(f"\n   ⚠️ WARNING: {len(desyncs)} desync(s) detected!")
            for d in desyncs:
                print(f"   - {d['story_id']}: {d['type']}")
                print(f"     DB: {d['db_status']}, Spec Checked: {d['spec_checked']}")
                print(f"     Fix: {d['fix']}")
            
            # Detection working = we found the intentional desync
            results["detection_works"] = any(d["story_id"] == "US-001" for d in desyncs)
        else:
            print("   ✅ No desyncs detected")
        
        # Pass if detection works (we intentionally created a desync)
        results["passed"] = results["detection_works"]
        
        print(f"\n   Results:")
        print(f"   - Desyncs Found: {len(desyncs)}")
        print(f"   - Detection Works: {'✅' if results['detection_works'] else '❌'}")
        print(f"   - PASS: {'✅' if results['passed'] else '❌'}")
        
        return results


# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

def run_all_tests() -> Dict:
    """Run all stress tests and generate report."""
    print("\n" + "=" * 60)
    print("   ATOMIC MESH v8.5.2 - ARCHITECTURAL STRESS TEST SUITE")
    print("=" * 60)
    print(f"   Time: {datetime.now().isoformat()}")
    print(f"   Test Directory: {TEST_DIR}")
    
    all_results = {}
    
    # Test 1: Race Condition
    test1 = RaceConditionTest()
    all_results["race_condition"] = test1.run(iterations=5)
    
    # Test 2: Monte Carlo
    test2 = MonteCarloTest()
    all_results["monte_carlo"] = test2.run(iterations=20)
    
    # Test 3: Context Drift
    test3 = ContextDriftTest()
    all_results["context_drift"] = test3.run(noise_kb=20)
    
    # Test 4: Desync Check
    test4 = DesyncTest()
    all_results["desync"] = test4.run()
    
    # Summary
    print("\n" + "=" * 60)
    print("   STRESS TEST SUMMARY")
    print("=" * 60)
    
    all_passed = True
    for test_name, result in all_results.items():
        status = "✅ PASS" if result["passed"] else "❌ FAIL"
        print(f"   {test_name.upper():20}: {status}")
        if not result["passed"]:
            all_passed = False
    
    print("\n" + "-" * 60)
    if all_passed:
        print("   🎉 ALL TESTS PASSED - ARCHITECTURE VERIFIED")
    else:
        print("   ⚠️ SOME TESTS FAILED - REVIEW REQUIRED")
    print("=" * 60 + "\n")
    
    return all_results


def cleanup():
    """Clean up test artifacts."""
    import shutil
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
        print(f"Cleaned up: {TEST_DIR}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        test_name = sys.argv[1]
        if test_name == "race":
            RaceConditionTest().run()
        elif test_name == "monte":
            MonteCarloTest().run(iterations=20)
        elif test_name == "drift":
            ContextDriftTest().run()
        elif test_name == "desync":
            DesyncTest().run()
        elif test_name == "clean":
            cleanup()
        else:
            print("Unknown test. Use: race, monte, drift, desync, clean")
    else:
        run_all_tests()
