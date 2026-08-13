<#
.SYNOPSIS
    GitHub API utilities for infrastructure repos.

.DESCRIPTION
    Provides GitHub-specific functions extracted from Common.PowerShell
    to keep each module cohesive and single-purpose.

    Current functions:
      - Invoke-GitHubApi          - general-purpose GitHub REST API caller
      - Get-GitHubAppToken        - mints a short-lived GitHub App token
      - Get-GitHubRunnerActivity  - self-hosted runners joined to their jobs
      - Get-PendingDeployment     - polls for the oldest non-terminal deployment
      - Set-DeploymentStatus      - posts a status update to a deployment
      - Invoke-RunnerTarballDeploy  - deploys a runner tarball to a VM's cache
      - Invoke-RunnerTarballEnsure  - caches the actions/runner tarball locally

    Each function lives in its own file under Public\ and is dot-sourced
    below so diffs stay focused on a single function per commit.

    Private\ holds the same one-function-per-file layout for helpers that are
    implementation detail rather than public surface: response parsing under
    StrictMode, header reads, the conditional-GET wrapper that keeps a
    polling caller off the rate limit, and the retry-policy pair that decides
    what Invoke-GitHubApi may safely re-send. They are dot-sourced FIRST so
    the Public functions can call them, and are deliberately absent from both
    export lists - adding one is not a public contract change.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Private\ConvertFrom-GitHubTimestamp.ps1"
. "$PSScriptRoot\Private\Get-GitHubJobCurrentStep.ps1"
. "$PSScriptRoot\Private\Get-GitHubResponseProperty.ps1"
. "$PSScriptRoot\Private\Get-HttpHeaderValue.ps1"
. "$PSScriptRoot\Private\Invoke-GitHubConditionalGet.ps1"
. "$PSScriptRoot\Private\New-GitHubRequestHeader.ps1"
. "$PSScriptRoot\Private\New-GitHubWriteRetryStrategy.ps1"
. "$PSScriptRoot\Private\Test-GitHubIdempotentMethod.ps1"

. "$PSScriptRoot\Public\Invoke-GitHubApi.ps1"
. "$PSScriptRoot\Public\Get-GitHubAppToken.ps1"
. "$PSScriptRoot\Public\Get-GitHubRunnerActivity.ps1"
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
    'Get-GitHubRunnerActivity',
    'Get-PendingDeployment',
    'Invoke-GitHubApi',
    'Invoke-RunnerTarballDeploy',
    'Invoke-RunnerTarballEnsure',
    'Set-DeploymentStatus'
)
