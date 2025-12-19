function Get-RepoRoot {
    param([string]$HintPath)

    if ($HintPath -and (Test-Path $HintPath)) {
        return (Resolve-Path $HintPath).Path
    }

    $adapterRoot = Split-Path -Parent $PSScriptRoot
    $moduleRoot = Split-Path -Parent $adapterRoot
    $repoRootCandidate = Split-Path -Parent $moduleRoot
    if (Test-Path $repoRootCandidate) {
        return (Resolve-Path $repoRootCandidate).Path
    }

    return (Get-Location).Path
}
