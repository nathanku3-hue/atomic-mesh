# import pytest (not needed for standalone run)
import sys
import os

# Ensure repo root is in path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def test_scaffold_tests_command_registry():
    """
    Verify that /scaffold-tests is registered in control_panel.ps1
    We do this by parsing the file since it's PowerShell
    """
    cp_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "control_panel.ps1")
    
    with open(cp_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check for registration in $Global:Commands
    assert '"scaffold-tests" = @{' in content
    assert 'Desc = "v13.2 autogenerate pytest scaffold: /scaffold-tests <task_id>"' in content
    
    # Check for handler in switch
    assert '"scaffold-tests" {' in content
    
    # Note: Whitespace might vary so we check for the key elements
    assert 'Call-MeshTool "scaffold_tests"' in content

if __name__ == "__main__":
    try:
        test_scaffold_tests_command_registry()
        print("✅ Command registration verified")
        sys.exit(0)
    except AssertionError as e:
        print(f"❌ Verification failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)
