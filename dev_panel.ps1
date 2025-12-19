# Atomic Mesh vNext (Dev Launcher)
# Parallel entrypoint for developing the new module without breaking control_panel.ps1
param(
    [string]$ProjectName = "AtomicMesh-Dev"
)

$RepoRoot = $PSScriptRoot

# Force reload to pick up changes immediately
Import-Module "$RepoRoot/src/AtomicMesh.UI/AtomicMesh.UI.psd1" -Force

Start-ControlPanel -ProjectName $ProjectName -ProjectPath $RepoRoot
