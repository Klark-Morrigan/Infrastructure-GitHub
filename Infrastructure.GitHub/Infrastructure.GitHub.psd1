@{
    ModuleVersion        = '1.2.0'
    GUID                 = 'f02caa94-35f8-42c4-a477-d8199cd23c2e'
    Author               = 'Klark Morrigan'
    Description          = 'GitHub API utilities for infrastructure repos.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Infrastructure.GitHub.psm1'
    # RequiredModules declares load-time dependencies so consumers do not
    # have to Import-Module them by hand. Common.PowerShell supplies
    # Invoke-WithRetry and New-TransientNetworkRetryStrategy, which
    # Invoke-GitHubApi uses to ride out transient network failures.
    # Floor 8.1.0 matches the ecosystem-wide pin.
    RequiredModules = @(
        @{
            ModuleName    = 'Common.PowerShell'
            ModuleVersion = '8.1.0'
        }
    )
    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
    FunctionsToExport = @(
        'Get-GitHubAppToken',
        'Get-GitHubRunnerActivity',
        'Get-PendingDeployment',
        'Invoke-GitHubApi',
        'Invoke-RunnerTarballDeploy',
        'Invoke-RunnerTarballEnsure',
        'Set-DeploymentStatus'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    # PSData surfaces the project/license links and release notes on the
    # PowerShell Gallery package page, giving the listing a link back to
    # the source repository.
    PrivateData = @{
        PSData = @{
            ProjectUri   = 'https://github.com/Klark-Morrigan/Infrastructure-GitHub'
            LicenseUri   = 'https://github.com/Klark-Morrigan/Infrastructure-GitHub/blob/master/LICENSE'
            ReleaseNotes = 'https://github.com/Klark-Morrigan/Infrastructure-GitHub/releases'
        }
    }
}
