# =============================================================================
# Init Helpers: Project initialization detection and execution
# =============================================================================
# Golden transplant from: golden_control_panel_reference.ps1 lines 2743-2957, 9898-9971
#
# Test-RepoInitialized: 4-tier detection (marker, registry, docs, legacy)
# Invoke-ProjectInit: All file I/O for initialization (templates, registry, marker)
#
# IMPORTANT: Initialization rules are also defined in tools/snapshot.py::check_initialized()
# The Python version is authoritative for snapshot generation. Keep these in sync:
#   - Marker path: control/state/.mesh_initialized
#   - Golden docs: docs/PRD.md, docs/SPEC.md, docs/DECISION_LOG.md
#   - Docs threshold: 2 of 3 required
# =============================================================================

function Test-RepoInitialized {
    <#
    .SYNOPSIS
        Detects if a project is initialized using 4-tier hierarchy.
    .RETURNS
        @{ initialized = $bool; reason = "marker|registry|docs|legacy|none"; details = "..." }
    #>
    param(
        [string]$Path,
        [string]$RepoRoot
    )

    if (-not $Path) { $Path = (Get-Location).Path }
    if (-not $RepoRoot) { $RepoRoot = $Path }

    # Tier A (preferred): Explicit marker file (created by /init)
    $markerPath = Join-Path $Path "control\state\.mesh_initialized"
    if (Test-Path $markerPath) {
        return @{
            initialized = $true
            reason = "marker"
            details = "Found: $markerPath"
        }
    }

    # Tier B: Check projects.json registry
    $projectsFile = Join-Path $RepoRoot "config\projects.json"
    if (Test-Path $projectsFile) {
        try {
            $projects = Get-Content $projectsFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $normalizedPath = $Path.TrimEnd('\', '/')
            $match = $projects | Where-Object {
                $_.path -and $_.path.TrimEnd('\', '/') -eq $normalizedPath
            }
            if ($match) {
                return @{
                    initialized = $true
                    reason = "registry"
                    details = "Project ID: $($match.id)"
                }
            }
        }
        catch {
            # JSON parse error - fall through to Tier C
        }
    }

    # Tier C: Check golden docs presence (2 of 3 required)
    $goldenDocs = @("docs\PRD.md", "docs\SPEC.md", "docs\DECISION_LOG.md")
    $found = @()
    foreach ($doc in $goldenDocs) {
        $docPath = Join-Path $Path $doc
        if (Test-Path $docPath) { $found += $doc }
    }
    if ($found.Count -ge 2) {
        return @{
            initialized = $true
            reason = "docs"
            details = "Found $($found.Count)/3: $($found -join ', ')"
        }
    }

    # Tier D: Legacy layout (old projects with docs/_mesh/ACTIVE_SPEC.md)
    $legacySpecPath = Join-Path $Path "docs\_mesh\ACTIVE_SPEC.md"
    if (Test-Path $legacySpecPath) {
        return @{
            initialized = $true
            reason = "legacy"
            details = "Found: docs/_mesh/ACTIVE_SPEC.md"
        }
    }

    return @{
        initialized = $false
        reason = "none"
        details = "No marker, no registry entry, only $($found.Count)/3 golden docs"
    }
}

function Invoke-ProjectInit {
    <#
    .SYNOPSIS
        Performs project initialization. All file I/O lives here.
    .PARAMETER Path
        Project directory to initialize (where docs/ will be created)
    .PARAMETER TemplateRoot
        Root of the mesh module repo (where library/templates/ lives)
    .PARAMETER Force
        If true, recreate files even if they exist
    .RETURNS
        @{ Success = $bool; Created = @(); Skipped = @(); Error = "" }
    #>
    param(
        [string]$Path,
        [string]$TemplateRoot,
        [switch]$Force
    )

    $result = @{
        Success = $false
        Created = @()
        Skipped = @()
        Error = ""
    }

    try {
        # Validate template root exists - FAIL LOUDLY if missing
        $templatesDir = Join-Path $TemplateRoot "library\templates"
        if (-not (Test-Path $templatesDir)) {
            $result.Error = "Templates directory not found: $templatesDir"
            return $result
        }

        # Ensure docs folder exists
        $docsDir = Join-Path $Path "docs"
        if (-not (Test-Path $docsDir)) {
            New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
        }

        # Template mapping
        $templates = @{
            "PRD.template.md"          = "docs\PRD.md"
            "SPEC.template.md"         = "docs\SPEC.md"
            "DECISION_LOG.template.md" = "docs\DECISION_LOG.md"
            "TECH_STACK.template.md"   = "docs\TECH_STACK.md"
            "ACTIVE_SPEC.template.md"  = "docs\ACTIVE_SPEC.md"
            "INBOX.template.md"        = "docs\INBOX.md"
        }

        $projectName = Split-Path $Path -Leaf
        $today = Get-Date -Format "yyyy-MM-dd"

        # Create templates (idempotent: skip if exists unless Force)
        foreach ($src in $templates.Keys) {
            $srcPath = Join-Path $templatesDir $src
            $dstPath = Join-Path $Path $templates[$src]

            if ((Test-Path $dstPath) -and (-not $Force)) {
                $result.Skipped += $templates[$src]
                continue
            }

            if (Test-Path $srcPath) {
                $content = Get-Content $srcPath -Raw -Encoding UTF8

                # Replace placeholders
                $content = $content -replace '\{\{PROJECT_NAME\}\}', $projectName
                $content = $content -replace '\{\{DATE\}\}', $today
                $content = $content -replace '\{\{AUTHOR\}\}', 'Atomic Mesh'

                # Ensure parent dir exists
                $parentDir = Split-Path $dstPath -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                }

                Set-Content -Path $dstPath -Value $content -Encoding UTF8
                $result.Created += $templates[$src]
            }
            else {
                # Template file missing - FAIL LOUDLY
                $result.Error = "Template file not found: $srcPath"
                return $result
            }
        }

        # Create initialization marker
        $stateDir = Join-Path $Path "control\state"
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        }
        $markerPath = Join-Path $stateDir ".mesh_initialized"
        if (-not (Test-Path $markerPath) -or $Force) {
            "" | Set-Content -Path $markerPath -Encoding UTF8
            $result.Created += "control\state\.mesh_initialized"
        }
        else {
            $result.Skipped += "control\state\.mesh_initialized"
        }

        # Update projects.json registry (merge, don't rewrite)
        $projectsFile = Join-Path $TemplateRoot "config\projects.json"
        if (Test-Path $projectsFile) {
            try {
                $projects = Get-Content $projectsFile -Raw | ConvertFrom-Json
                $normalizedPath = $Path.TrimEnd('\', '/')

                # Find existing entry
                $existing = $projects | Where-Object {
                    $_.path -and $_.path.TrimEnd('\', '/') -eq $normalizedPath
                }

                if (-not $existing) {
                    # Add new entry
                    $maxId = ($projects | Measure-Object -Property id -Maximum).Maximum
                    $newId = if ($maxId) { $maxId + 1 } else { 1 }
                    $newEntry = [PSCustomObject]@{
                        id      = $newId
                        name    = $projectName
                        path    = $Path
                        db      = "mesh.db"
                        profile = "general"
                    }
                    $projects = @($projects) + $newEntry

                    # Atomic write: temp file + replace (crash-safe)
                    $tempFile = "$projectsFile.tmp"
                    $projects | ConvertTo-Json -Depth 4 | Set-Content $tempFile -Encoding UTF8
                    Move-Item -Path $tempFile -Destination $projectsFile -Force
                    $result.Created += "config\projects.json (entry)"
                }
                else {
                    $result.Skipped += "config\projects.json (exists)"
                }
            }
            catch {
                # Registry update failed but continue - not critical
                $result.Skipped += "config\projects.json (error)"
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}
