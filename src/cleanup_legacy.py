# C:\Tools\atomic-mesh\cleanup_legacy.py
# Legacy file cleanup for Atomic Mesh v7.4 deployment
# Removes outdated files from previous versions

import os
import glob
import shutil
from datetime import datetime

def cleanup_legacy(mesh_dir: str = None):
    """
    Clean up legacy artifacts from v7.0-v7.3.
    Run this after deploying v7.4 to ensure no ghost files.
    """
    if mesh_dir is None:
        mesh_dir = os.path.dirname(os.path.abspath(__file__))
    
    print(f"🧹 Atomic Mesh v7.4 Legacy Cleanup")
    print(f"   Directory: {mesh_dir}")
    print(f"   Time: {datetime.now().isoformat()}")
    print()
    
    # Files that are now obsolete or replaced
    legacy_patterns = [
        # Old version markers
        "roadmap_v7.md",
        "roadmap_v7.0.md",
        "roadmap_v7.1.md",
        "roadmap_v7.2.md",
        "roadmap_v7.3.md",
        
        # Temp/debug files
        "temp_*.py",
        "debug_*.py",
        "test_*.log",
        "*_backup.py",
        "*_old.py",
        
        # Old config files
        "config_old.json",
        ".mesh_cache",
    ]
    
    # Directories that should be cleaned
    legacy_dirs = [
        "__pycache__",
        ".pytest_cache",
        "temp",
        "old_versions",
    ]
    
    deleted_files = []
    deleted_dirs = []
    skipped = []
    
    # Clean files
    for pattern in legacy_patterns:
        matches = glob.glob(os.path.join(mesh_dir, pattern))
        for file_path in matches:
            if os.path.isfile(file_path):
                try:
                    os.remove(file_path)
                    deleted_files.append(os.path.basename(file_path))
                    print(f"   ✅ Deleted: {os.path.basename(file_path)}")
                except Exception as e:
                    skipped.append(f"{file_path}: {e}")
    
    # Clean directories
    for dirname in legacy_dirs:
        dir_path = os.path.join(mesh_dir, dirname)
        if os.path.isdir(dir_path):
            try:
                shutil.rmtree(dir_path)
                deleted_dirs.append(dirname)
                print(f"   ✅ Removed dir: {dirname}/")
            except Exception as e:
                skipped.append(f"{dirname}/: {e}")
    
    # Summary
    print()
    print(f"=== Cleanup Summary ===")
    print(f"   Files deleted: {len(deleted_files)}")
    print(f"   Dirs removed: {len(deleted_dirs)}")
    print(f"   Skipped: {len(skipped)}")
    
    if skipped:
        print()
        print("⚠️ Skipped items:")
        for item in skipped:
            print(f"   - {item}")
    
    print()
    print("✅ Cleanup complete. Ready for v7.4 deployment.")
    
    return {
        "deleted_files": deleted_files,
        "deleted_dirs": deleted_dirs,
        "skipped": skipped
    }


def verify_v74_files(mesh_dir: str = None):
    """
    Verify that all v7.4 required files are present.
    """
    if mesh_dir is None:
        mesh_dir = os.path.dirname(os.path.abspath(__file__))
    
    required_files = [
        "router.py",
        "mesh_server.py",
        "librarian_tools.py",
        "control_panel.ps1",
        "worker.ps1",
        "auditor_prompt.md",
        "librarian_prompt.md",
    ]
    
    print(f"🔍 Verifying v7.4 deployment...")
    
    missing = []
    present = []
    
    for filename in required_files:
        file_path = os.path.join(mesh_dir, filename)
        if os.path.exists(file_path):
            size = os.path.getsize(file_path)
            present.append(f"{filename} ({size:,} bytes)")
            print(f"   ✅ {filename}")
        else:
            missing.append(filename)
            print(f"   ❌ MISSING: {filename}")
    
    print()
    if missing:
        print(f"🔴 INCOMPLETE: {len(missing)} files missing")
        return False
    else:
        print(f"✅ COMPLETE: All {len(required_files)} v7.4 files present")
        return True


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "--verify":
        verify_v74_files()
    else:
        cleanup_legacy()
        print()
        verify_v74_files()
