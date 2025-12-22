Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $PSCommandPath

$files = @(
    # Models
    'Private/Models/UiToast.ps1',
    'Private/Models/UiEvent.ps1',
    'Private/Models/UiEventLog.ps1',
    'Private/Models/PlanState.ps1',
    'Private/Models/LaneMetrics.ps1',
    'Private/Models/WorkerInfo.ps1',
    'Private/Models/SchedulerDecision.ps1',
    'Private/Models/UiAlerts.ps1',
    'Private/Models/UiSnapshot.ps1',
    'Private/Models/UiCache.ps1',
    'Private/Models/UiState.ps1',

    # Console + Adapters
    'Private/Render/Console.ps1',
    'Private/Adapters/RepoAdapter.ps1',
    'Private/Adapters/DbAdapter.ps1',
    'Private/Adapters/SnapshotAdapter.ps1',
    'Private/Adapters/RealAdapter.ps1',
    'Private/Adapters/MeshServerAdapter.ps1',

    # Reducers
    'Private/Reducers/ComputePlanState.ps1',
    'Private/Reducers/ComputeLaneMetrics.ps1',
    'Private/Reducers/ComputeNextHint.ps1',
    'Private/Reducers/ComputePipelineStatus.ps1',

    # Guards
    'Private/Guards/CommandGuards.ps1',

    # Helpers
    'Private/Helpers/InitHelpers.ps1',
    'Private/Helpers/LoggingHelpers.ps1',
    'Private/Helpers/Reset-OrphanedTasks.ps1',

    # Layout (GOLDEN TRANSPLANT: lines 4114-4166)
    'Private/Layout/LayoutConstants.ps1',

    # Renderers
    'Private/Render/RenderCommon.ps1',
    'Private/Render/RenderPlan.ps1',
    'Private/Render/RenderGo.ps1',
    'Private/Render/RenderBootstrap.ps1',
    'Private/Render/CommandPicker.ps1',
    'Private/Render/Overlays/RenderHistory.ps1',
    # NON-GOLDEN: RenderStreamDetails and RenderStats removed (F4/F6 not in golden)

    # Routers + entrypoints
    'Public/Invoke-KeyRouter.ps1',
    'Public/Invoke-CommandRouter.ps1',
    'Public/Start-ControlPanel.ps1'
)

foreach ($file in $files) {
    $fullPath = Join-Path -Path $script:ModuleRoot -ChildPath $file
    if (-not (Test-Path $fullPath)) {
        throw "AtomicMesh.UI load failed: missing file $file"
    }
    . $fullPath
}

Export-ModuleMember -Function @(
    'Start-ControlPanel',
    'Invoke-CommandRouter',
    'Invoke-KeyRouter'
)
