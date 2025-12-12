# Reference Code Library

This folder contains reference code from "Great Projects" that agents use for style transfer and pattern learning.

## How to Add a Reference Project

### Option 1: Symlink (Recommended for local repos)
```powershell
# Windows (Run as Admin)
New-Item -ItemType Junction -Path ".\context7" -Target "E:\Path\To\Great\Project"
```

### Option 2: Copy specific files
Copy only the "perfect" examples you want agents to mimic:
- python/perfect_router.py - Example FastAPI router
- 	ypescript/perfect_component.tsx - Example React component

## Available References

| Folder | Source | Description |
|--------|--------|-------------|
| python/ | Local templates | Python code samples |
| 	ypescript/ | Local templates | TypeScript code samples |
| context7/ | (Symlink) | External reference project |

## Usage

Agents query references via:
```
/reference api_route python
```

Or via MCP tool:
```python
get_reference("api_route", "python_backend")
```
