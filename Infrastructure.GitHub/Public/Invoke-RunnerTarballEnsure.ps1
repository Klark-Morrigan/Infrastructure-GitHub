function Invoke-RunnerTarballEnsure {
    <#
    .SYNOPSIS
        Ensures the actions/runner tarball for a specific version is present
        in a local host cache directory.

    .DESCRIPTION
        Constructs the expected tarball path from the version string. If the
        file is already present the function returns immediately (idempotent).
        If absent, any stale actions-runner-*.tar.gz files in the cache
        directory are purged first, then the tarball is downloaded from GitHub.
        The cache directory is created if it does not exist.

        This is shared between register-runners.ps1 (Infrastructure-GitHubRunners)
        and Invoke-RunnerTarballPrefetch (Infrastructure-E2E), which both need
        to stage the binary on the Windows host before serving it to VMs over
        the internal Hyper-V switch.

    .PARAMETER RunnerVersion
        Version string without leading 'v', e.g. '2.317.0'.

    .PARAMETER CacheDir
        Local directory where the tarball is cached (created if absent).

    .OUTPUTS
        [string] - Full path to the cached tarball file.

    .EXAMPLE
        $path = Invoke-RunnerTarballEnsure -RunnerVersion '2.317.0' `
                    -CacheDir 'C:\runner-cache'
        # -> 'C:\runner-cache\actions-runner-linux-x64-2.317.0.tar.gz'
    #>
    [CmdletBinding()]
    param(
        # Version string without leading 'v', e.g. '2.317.0'.
        [Parameter(Mandatory)]
        [string] $RunnerVersion,

        # Local directory where the tarball is cached (created if absent).
        [Parameter(Mandatory)]
        [string] $CacheDir
    )

    $tarName   = "actions-runner-linux-x64-${RunnerVersion}.tar.gz"
    $localPath = Join-Path $CacheDir $tarName

    if (Test-Path $localPath) {
        Write-Host "  Runner tarball already in host cache: $tarName" `
            -ForegroundColor Green
        return $localPath
    }

    $tarUrl = "https://github.com/actions/runner/releases/download/" +
              "v${RunnerVersion}/${tarName}"

    Write-Host "  Downloading runner v${RunnerVersion} tarball to host cache ..." `
        -ForegroundColor Cyan

    # Purge stale versions so the cache does not grow unboundedly.
    Get-ChildItem $CacheDir -Filter 'actions-runner-*.tar.gz' `
        -ErrorAction SilentlyContinue | Remove-Item -Force

    New-Item $CacheDir -ItemType Directory -Force | Out-Null
    Invoke-WebRequest -Uri $tarUrl -OutFile $localPath -UseBasicParsing

    Write-Host "  Runner tarball downloaded to host cache." -ForegroundColor Green
    return $localPath
}
