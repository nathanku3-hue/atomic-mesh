# SNIPPET: safe_json_load
# LANG: python
# TAGS: json, file, error-handling
# INTENT: Load JSON file with graceful error handling and default fallback
# UPDATED: 2025-12-12

import json
from pathlib import Path

def safe_json_load(file_path, default=None):
    """
    Load JSON file with error handling.

    Args:
        file_path: Path to JSON file
        default: Value to return if file missing or invalid (default: None)

    Returns:
        Parsed JSON data, or default if error occurs
    """
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, IOError):
        return default if default is not None else {}
