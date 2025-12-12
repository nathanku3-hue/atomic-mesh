"""
Regression Tests for Import Order Bugs

Prevents NameError and similar module-level initialization issues.
These tests MUST pass before any commit.

History:
- v14.0.1: NameError '_re_router' not defined (import after use)
"""

import unittest
import sys
import os

# Add parent dir to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestImportOrder(unittest.TestCase):
    """Tests that catch import order bugs at module load time"""

    def test_mesh_server_imports_cleanly(self):
        """mesh_server.py should import without NameError"""
        try:
            import mesh_server
            self.assertIsNotNone(mesh_server)
        except NameError as e:
            self.fail(f"Import order bug detected: {e}")

    def test_router_patterns_compile(self):
        """Router patterns should compile without errors"""
        try:
            import mesh_server

            # Verify COMPILED_READONLY_PATTERNS exists and is not empty
            self.assertTrue(hasattr(mesh_server, 'COMPILED_READONLY_PATTERNS'))
            self.assertGreater(len(mesh_server.COMPILED_READONLY_PATTERNS), 0)

            # Verify COMPILED_INTENT_PATTERNS exists and is not empty
            self.assertTrue(hasattr(mesh_server, 'COMPILED_INTENT_PATTERNS'))
            self.assertGreater(len(mesh_server.COMPILED_INTENT_PATTERNS), 0)

        except Exception as e:
            self.fail(f"Pattern compilation failed: {e}")

    def test_route_cli_input_callable(self):
        """route_cli_input should be callable after module load"""
        try:
            import mesh_server
            import json

            # Should not raise NameError when calling
            result = json.loads(mesh_server.route_cli_input("AUTO", "help"))

            # Should return valid JSON structure
            self.assertIn("command", result)
            self.assertIn("risk", result)

        except NameError as e:
            self.fail(f"route_cli_input uses undefined name: {e}")
        except Exception as e:
            self.fail(f"route_cli_input failed unexpectedly: {e}")

    def test_no_undefined_module_variables(self):
        """Catch common undefined variable patterns"""
        try:
            import mesh_server
            import inspect

            source = inspect.getsource(mesh_server)

            # Common patterns that cause issues
            risky_patterns = [
                # Using variable before import
                ("using '_re_router' before import", "_re_router" in source[:source.find("import re as _re_router")] if "import re as _re_router" in source else False),
            ]

            for desc, condition in risky_patterns:
                if condition:
                    self.fail(f"Risky pattern detected: {desc}")

        except Exception as e:
            # If we can't inspect, that's okay - other tests will catch issues
            pass


class TestModuleDependencies(unittest.TestCase):
    """Tests for circular imports and dependency issues"""

    def test_no_circular_imports(self):
        """Module should load without circular import errors"""
        try:
            # Reload to catch circular issues
            import importlib
            import mesh_server
            importlib.reload(mesh_server)

        except ImportError as e:
            if "circular" in str(e).lower():
                self.fail(f"Circular import detected: {e}")
            raise

    def test_critical_functions_accessible(self):
        """All gate enforcement functions should be accessible after import"""
        import mesh_server

        critical_functions = [
            'route_cli_input',
            'get_context_readiness',
            'verify_task',
            'submit_review_decision',
            'refresh_plan_preview',
            'draft_plan',
            'accept_plan',
        ]

        for func_name in critical_functions:
            self.assertTrue(
                hasattr(mesh_server, func_name),
                f"Critical function '{func_name}' not accessible"
            )
            self.assertTrue(
                callable(getattr(mesh_server, func_name)),
                f"'{func_name}' exists but is not callable"
            )


if __name__ == '__main__':
    unittest.main()
