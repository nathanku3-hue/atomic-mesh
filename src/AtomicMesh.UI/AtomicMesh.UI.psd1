@{
    RootModule        = 'AtomicMesh.UI.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'c9c46522-33ab-4d98-8e90-9d1fa4efa37c'
    Author            = 'Atomic Mesh'
    CompanyName       = 'Atomic Mesh'
    Description       = 'UI loop + rendering module for the Atomic Mesh control panel.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-ControlPanel', 'Invoke-CommandRouter', 'Invoke-KeyRouter')
    CmdletsToExport   = @()
    AliasesToExport   = @()
    PrivateData       = @{}
}
