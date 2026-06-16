<#
.SYNOPSIS
    GitHub API utilities for infrastructure repos.

.DESCRIPTION
    Provides GitHub-specific functions extracted from Common.PowerShell
    to keep each module cohesive and single-purpose.

    Current functions:
      - Invoke-GitHubApi          - general-purpose GitHub REST API caller
      - Get-GitHubAppToken        - mints a short-lived GitHub App token
      - Get-PendingDeployment     - polls for the oldest non-terminal deployment
      - Set-DeploymentStatus      - posts a status update to a deployment
      - Invoke-RunnerTarballDeploy  - deploys a runner tarball to a VM's cache
      - Invoke-RunnerTarballEnsure  - caches the actions/runner tarball locally

    Each function lives in its own file under Public\ and is dot-sourced
    below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Invoke-GitHubApi.ps1"
. "$PSScriptRoot\Public\Get-GitHubAppToken.ps1"
. "$PSScriptRoot\Public\Get-PendingDeployment.ps1"
. "$PSScriptRoot\Public\Invoke-RunnerTarballDeploy.ps1"
. "$PSScriptRoot\Public\Invoke-RunnerTarballEnsure.ps1"
. "$PSScriptRoot\Public\Set-DeploymentStatus.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function @(
    'Get-GitHubAppToken',
    'Get-PendingDeployment',
    'Invoke-GitHubApi',
    'Invoke-RunnerTarballDeploy',
    'Invoke-RunnerTarballEnsure',
    'Set-DeploymentStatus'
)
