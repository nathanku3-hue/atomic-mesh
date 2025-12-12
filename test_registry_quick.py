#!/usr/bin/env python3
"""Quick test of registry check"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def test_registry():
    import mesh_server
    import json
    print("Calling validate_registry_alignment()...")
    res = mesh_server.validate_registry_alignment()
    print(f"Result: {res}")
    res_dict = json.loads(res)
    return res_dict.get("status") in ["OK", "WARNING"]

if __name__ == "__main__":
    result = test_registry()
    print(f"Test result: {result}")
    sys.exit(0 if result else 1)
