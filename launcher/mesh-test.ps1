<#
    Atomic Mesh - Quick Launch from Current Directory

    Usage:
        cd E:\Code\your-project
        mesh-test

    This passes the current directory as -ProjectPath so the control panel
    shows data from YOUR project, not the module directory.
#>

$RepoRoot = Resolve-Path "$PSScriptRoot\.."
$ControlPanel = "$RepoRoot\control_panel.ps1"

if (-not (Test-Path $ControlPanel)) {
    Write-Error "Control panel not found: $ControlPanel"
    exit 1
}

# Pass current directory as ProjectPath (the fix for wrong DB issue)
& $ControlPanel -ProjectPath $PWD -ProjectName (Split-Path $PWD -Leaf)
