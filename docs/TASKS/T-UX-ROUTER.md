# Follow-Up Tasks: Control Panel UX Router Wiring

**Created**: 2025-12-11  
**Parent Decision**: UX-CP-001  
**Status**: 📝 BACKLOG

---

## T-UX-ROUTER-01: Wire Router Output into Debug Overlay

**Priority**: Medium  
**Effort**: 1-2 hours  
**Assigned**: Unassigned  
**Dependencies**: None (UX-CP-001 deployed)

### Objective
Populate `$Global:LastRoutedCommand` in the routing logic so that the `/router-debug` overlay can display real routing decisions.

### Scope
- **IN SCOPE**: Debug-only feature, overlay rendering
- **OUT OF SCOPE**: Changing routing semantics, safety rails, or production behavior

### Implementation

Modify the routing logic (likely in `Invoke-ModalRoute` or similar function) to populate the debug variable:

```powershell
# In routing logic, AFTER command is routed
if ($Global:RouterDebug) {
    $Global:LastRoutedCommand = @{
        Input = $userInput
        RoutedTo = $routedCommand
        Reason = $routingReason
        Mode = $Global:CurrentMode
        Timestamp = Get-Date
    }
}
```

### Constraints
1. **Debug-only impact**: Only executes when `$Global:RouterDebug` is `$true`
2. **No semantic changes**: Does NOT change what gets routed where
3. **No safety changes**: Does NOT touch `/ship` confirmation or safety rails
4. **Performance**: Minimal overhead (simple variable assignment)

### Acceptance Criteria
- [ ] `$Global:LastRoutedCommand` is populated after each routing decision
- [ ] Debug overlay shows routing info when `/router-debug` is enabled
- [ ] No impact when debug is disabled (`$Global:RouterDebug = $false`)
- [ ] No performance degradation (< 1ms overhead)
- [ ] No changes to core routing semantics
- [ ] Static safety check still passes

### Verification
```powershell
# Test 1: Enable debugging
.\control_panel.ps1
> /router-debug
# Expected: "Router debug: ENABLED"

# Test 2: Type a routable phrase
> health
# Expected: Overlay shows "→ Routed to: /health (reason: keyword match)"

# Test 3: Disable and verify no overlay
> /router-debug
> health
# Expected: No overlay, normal routing behavior
```

---

## T-UX-ROUTER-02: Implement Routing Rules + Test Cases

**Priority**: Medium  
**Effort**: 3-4 hours  
**Assigned**: Unassigned  
**Dependencies**: T-UX-ROUTER-01 (recommended, not required)

### Objective
Implement 3-5 intelligent routing rules that map natural language inputs to slash commands, with comprehensive test coverage.

### Scope
- **IN SCOPE**: Keyword-based routing, mode-aware suggestions, test cases
- **OUT OF SCOPE**: LLM-based intent detection (future enhancement)

### Suggested Routing Rules

#### OPS Mode
| User Input | Routed Command | Reason |
|------------|----------------|--------|
| `"health"` | `/health` | Keyword match |
| `"drift"` | `/drift` | Keyword match |
| `"backup"` or `"snapshot"` | `/snapshot` | Keyword match (OR) |
| `"show me \u003cx\u003e"` | `/ops` | Pattern match |

#### PLAN Mode
| User Input | Routed Command | Reason |
|------------|----------------|--------|
| `"add \u003cfeature\u003e"` | `/plan` | Pattern match + context capture |
| `"design \u003ccomponent\u003e"` | `/plan` | Pattern match + context capture |
| `"I want to build \u003cx\u003e"` | `/plan` | Natural language match |

#### RUN Mode
| User Input | Routed Command | Reason |
|------------|----------------|--------|
| `"continue"` or `"go"` | `/run` | Keyword match (OR) |
| `"status"` | `/status` | Keyword match |
| `"what's next"` | `/run` | Natural language match |

#### SHIP Mode (Safety Critical)
| User Input | Routed Command | Reason |
|------------|----------------|--------|
| `"deploy"` or `"release"` | `/ship` | Keyword match → **MUST show confirmation prompt** |
| `"push to prod"` | `/ship` | Pattern match → **MUST show confirmation prompt** |

**CRITICAL**: Any routing to `/ship` MUST preserve the existing confirmation requirement. `/ship` without `--confirm` should still block.

### Test Cases

```gherkin
Feature: Natural Language Routing

Scenario: Health check routing in OPS mode
  Given I am in OPS mode
  When I type "health"
  Then the router suggests "/health"
  And the debug overlay shows "→ /health (reason: keyword 'health')"
  And the command is executed

Scenario: Plan routing with context capture
  Given I am in PLAN mode
  When I type "add login feature"
  Then the router suggests "/plan"
  And the captured context includes "login feature"
  And the debug overlay shows routing reason

Scenario: Safety preserved for /ship
  Given I am in SHIP mode
  When I type "deploy"
  Then the router suggests "/ship"
  But the confirmation prompt is still shown
  And the command does NOT auto-execute without --confirm

Scenario: No false positives
  Given I am in OPS mode
  When I type "healthy food recipes"
  Then the router does NOT route to "/health"
  And the input is treated as natural language chat

Scenario: Mode-aware routing
  Given I am in PLAN mode
  When I type "health"
  Then the router does NOT route to "/health" (wrong mode)
  And the suggestion is mode-appropriate
```

### Implementation Guidance

```powershell
function Invoke-ModalRoute {
    param(
        [string]$UserInput,
        [string]$Mode
    )
    
    # Simple keyword routing (start here)
    $routes = @{
        'OPS' = @{
            'health' = '/health'
            'drift' = '/drift'
            'backup|snapshot' = '/snapshot'
        }
        'PLAN' = @{
            '^add ' = '/plan'
            '^design ' = '/plan'
        }
    }
    
    # Check for matches
    foreach ($pattern in $routes[$Mode].Keys) {
        if ($UserInput -match $pattern) {
            $routedCommand = $routes[$Mode][$pattern]
            $reason = "keyword match: '$pattern'"
            
            # Debug logging
            if ($Global:RouterDebug) {
                $Global:LastRoutedCommand = "$routedCommand (reason: $reason)"
            }
            
            return $routedCommand
        }
    }
    
    # No route found
    return $null
}
```

### Acceptance Criteria
- [ ] 3+ routing rules implemented per mode
- [ ] All test scenarios pass
- [ ] Debug overlay shows routing reason for each rule
- [ ] No false positives (wrong command suggestions)
- [ ] Safety: `/ship` still requires explicit `--confirm`
- [ ] Performance: routing decision < 100ms
- [ ] Static safety check passes
- [ ] Documentation includes routing table

### Verification
Run test suite:
```powershell
python tests\test_router.py
# Expected: All tests PASS
```

Manual verification:
```powershell
.\control_panel.ps1
> /router-debug  # Enable debugging
> health          # Test OPS routing
> [Tab]           # Switch to PLAN
> add new feature # Test PLAN routing
> deploy          # Test SHIP safety (should still require confirmation)
```

---

## T-CI-SOURCE-REGISTRY: Fix CI Source Registry Check

**Priority**: Low  
**Effort**: 30 minutes - 1 hour  
**Assigned**: Unassigned  
**Status**: 📝 BACKLOG

### Problem
CI tests are failing because `SOURCE_REGISTRY.json` is missing from the gold repo. This is **not** related to the UX changes but blocks the CI gate.

### Objective
Resolve the SOURCE_REGISTRY.json issue without weakening safety or governance.

### Options

#### Option A: Create Minimal Dev Placeholder (Recommended)
```json
{
  "source": "atomic-mesh",
  "version": "13.2.0",
  "last_updated": "2025-12-11",
  "components": {
    "control_panel": {
      "path": "control_panel.ps1",
      "version": "13.2.0-ux",
      "status": "stable"
    }
  }
}
```

Benefits:
- ✅ Minimal change
- ✅ CI will pass
- ✅ Provides baseline for future registry work

#### Option B: Make Missing Registry Non-Fatal for UI-Only Changes
Modify `tests/run_ci.py` to treat missing registry as a warning (not error) when:
- Only UI files changed (`control_panel.ps1`)
- No backend/API changes
- Static safety check passes

Benefits:
- ✅ More flexible for future UI-only changes
- ⚠️ Requires careful safety logic

### Recommended Approach
**Option A** - Create a minimal placeholder `SOURCE_REGISTRY.json` in the gold repo.

### Acceptance Criteria
- [ ] CI tests pass after fix
- [ ] No weakening of safety or governance gates
- [ ] Static safety check still runs and passes
- [ ] Solution documented

### Verification
```powershell
cd E:\Code\atomic-mesh
python tests\run_ci.py
# Expected: All gates PASS
```

---

## Summary

| Task ID | Priority | Effort | Status | Blocks |
|---------|----------|--------|--------|--------|
| T-UX-ROUTER-01 | Medium | 1-2h | 📝 Backlog | - |
| T-UX-ROUTER-02 | Medium | 3-4h | 📝 Backlog | T-UX-ROUTER-01 (recommended) |
| T-CI-SOURCE-REGISTRY | Low | 30m-1h | 📝 Backlog | - |

**Total Effort**: 4.5-7 hours across all tasks

---

*Created as follow-up to Decision Packet UX-CP-001*
