@{
    ModuleVersion        = '0.0.0'
    GUID                 = 'f02caa94-35f8-42c4-a477-d8199cd23c2e'
    Author               = 'Vitaly Andrev'
    Description          = 'GitHub API utilities for infrastructure repos.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Infrastructure.GitHub.psm1'
    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
    FunctionsToExport = @()
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
