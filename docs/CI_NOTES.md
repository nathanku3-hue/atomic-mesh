# CI Infrastructure Notes

**Last Updated**: 2025-12-11  
**Task**: T-CI-SOURCE-REGISTRY  
**Status**: ✅ RESOLVED

---

## SOURCE_REGISTRY.json

### Purpose
The `SOURCE_REGISTRY.json` file provides a minimal structural registry for CI validation. It is used by `mesh_server.validate_registry_alignment()` to check that rule IDs (DR-*, HIPAA-*, GDPR-*, etc.) are properly registered.

### Location
```
docs/sources/SOURCE_REGISTRY.json
```

### Structure
```json
{
  "version": 1,
  "_meta": {
    "created": "2025-12-11",
    "purpose": "Minimal dev/CI placeholder registry",
    "status": "dev-placeholder"
  },
  "sources": {
    "STD-ENG": {
      "id": "STD-ENG",
      "title": "Standard Engineering Practices",
      "tier": "standard",
      "authority": "DEFAULT",
      "id_pattern": "STD-*"
    },
    "DEV-PLACEHOLDER": {
      "id": "DEV-PLACEHOLDER",
      "title": "Development Placeholder",
      "tier": "dev",
      "authority": "NONE",
      "id_pattern": "DEV-*"
    }
  }
}
```

### Important Notes

1. **This is a dev/CI placeholder**: This registry is NOT used for production authority decisions. Real authority sources are governed through The Gavel system and documented in source-specific files.

2. **No claims of authority**: The placeholder explicitly uses `"authority": "NONE"` to make clear it does not claim any legal, medical, or professional authority.

3. **CI validation only**: The purpose is to satisfy structural checks in `tests/run_ci.py` that verify the registry file exists and is properly formatted.

4. **Extensible**: New source entries can be added as needed, following the same pattern. Each entry should specify:
   - `id`: Unique identifier
   - `title`: Human-readable name
   - `tier`: standard, professional, derived, etc.
   - `authority`: DEFAULT, NONE, or specific authority type
   - `id_pattern`: Regex pattern for matching rule IDs

---

## CI Flow & Environment Management

### Issue Fixed (2025-12-11)
The CI runner had an environment isolation bug where `MESH_BASE_DIR` set by constitution tests persisted into the registry check, causing it to look for SOURCE_REGISTRY.json in a temporary directory instead of the real repo.

### Solution
Updated `tests/run_ci.py::run_registry_check()` to:
1. Clear `MESH_BASE_DIR` and `ATOMIC_MESH_DB` environment variables
2. Reload `mesh_server` module with clean environment
3. Then run the registry validation

This ensures each CI gate runs in the correct environment context.

### CI Gates

The CI runner (`tests/run_ci.py`) executes the following gates in order:

1. **Constitution Tests** - Verifies The Gavel governance pathway
2. **Registry Check** - Validates SOURCE_REGISTRY.json structure
3. **Static Safety Check** - Detects unsafe state mutations
4. **Golden Thread Smoke** - End-to-end critical path test

All gates must PASS for CI to pass.

---

## Maintenance

### Adding New Source Types
To add a new source type to the registry:

1. Add entry to `docs/sources/SOURCE_REGISTRY.json`
2. Follow the structure of existing entries
3. Use appropriate tier and authority values
4. Update this documentation

### Troubleshooting CI
If CI fails on Registry gate:

1. **Check file exists**: `docs/sources/SOURCE_REGISTRY.json`
2. **Validate JSON**: Ensure proper JSON syntax
3. **Check environment**: Verify `MESH_BASE_DIR` is not set to temp directory
4. **Run directly**: `python -c "import mesh_server; print(mesh_server.validate_registry_alignment())"`

---

## References

- **File**: `docs/sources/SOURCE_REGISTRY.json`
- **CI Runner**: `tests/run_ci.py`
- **Validator**: `mesh_server.py::validate_registry_alignment()`
- **Task**: T-CI-SOURCE-REGISTRY (completed 2025-12-11)

---

*This infrastructure supports CI validation WITHOUT claiming any regulatory or professional authority.*
