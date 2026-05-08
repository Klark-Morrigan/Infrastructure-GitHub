# ---------------------------------------------------------------------------
# Invoke-RunnerTarballDeploy
#   Ensures a GitHub Actions runner tarball is present in the runner user's
#   cache directory on a remote Linux host.
#
#   Idempotent: returns immediately if the expected file is already present.
#   If absent, any stale actions-runner-*.tar.gz files are purged first so
#   the cache never accumulates old versions, then the tarball is fetched
#   via curl from $TarUrl.
#
#   All SSH commands run as $RunnerUser (via sudoers-permitted
#   'sudo -u $RunnerUser'), so the service user owns the cached file
#   without a separate chown step.
#
#   $CacheDir defaults to /home/$RunnerUser/cache when not supplied.
#   $TarPath  is always derived as $CacheDir/<filename from $TarUrl>.
#
#   $Label is an optional string prepended to log and error messages
#   (e.g. the VM name) so callers can identify which host is being
#   addressed when running against multiple VMs.
#
#   Complement to Invoke-RunnerTarballEnsure, which stages the tarball on
#   the Windows host. This function places it on the Linux VM.
# ---------------------------------------------------------------------------

function Invoke-RunnerTarballDeploy {
    [CmdletBinding()]
    param(
        # Connected SSH.NET SshClient. Caller owns the lifecycle.
        [Parameter(Mandatory)]
        [object] $SshClient,

        # Full download URL of the tarball
        # (e.g. 'https://github.com/.../actions-runner-linux-x64-2.317.0.tar.gz'
        # or 'http://10.10.0.1:8745/actions-runner-linux-x64-2.317.0.tar.gz').
        [Parameter(Mandatory)]
        [string] $TarUrl,

        # Username of the runner service account that will own the cached
        # tarball (e.g. 'u-actions-runner').
        [Parameter(Mandatory)]
        [string] $RunnerUser,

        # Remote cache directory. Defaults to /home/$RunnerUser/cache.
        [Parameter()]
        [string] $CacheDir = '',

        # Optional prefix for log and error messages, e.g. a VM name.
        [Parameter()]
        [string] $Label = ''
    )

    $tarName   = $TarUrl.Split('/')[-1]
    if (-not $CacheDir) { $CacheDir = "/home/${RunnerUser}/cache" }
    $tarPath   = "${CacheDir}/${tarName}"
    $prefix    = if ($Label) { "[$Label] " } else { '' }

    $r = Invoke-SshClientCommand `
             -SshClient $SshClient `
             -Command   "sudo -u $RunnerUser mkdir -p '$CacheDir'" `
             -ErrorAction Stop
    if ($r.ExitStatus -ne 0) {
        throw "${prefix}Failed to create cache directory: $($r.Error)"
    }

    $check = Invoke-SshClientCommand `
                 -SshClient $SshClient `
                 -Command   "sudo -u $RunnerUser test -f '$tarPath'" `
                 -ErrorAction Stop
    if ($check.ExitStatus -eq 0) {
        Write-Host "${prefix}Tarball already cached: $tarName" -ForegroundColor Green
        return
    }

    Write-Host "${prefix}Downloading tarball: $tarName ..." -ForegroundColor Cyan

    # Purge stale versions before downloading so the cache directory does
    # not accumulate old binaries.
    $purge = Invoke-SshClientCommand `
                 -SshClient $SshClient `
                 -Command   "sudo -u $RunnerUser rm -f '$CacheDir'/actions-runner-*.tar.gz" `
                 -ErrorAction Stop
    if ($purge.ExitStatus -ne 0) {
        throw "${prefix}Failed to purge stale tarballs: $($purge.Error)"
    }

    # --connect-timeout: fail fast if TCP handshake stalls (e.g. firewall
    #   drop with no RST).
    # --retry 3: covers transient connection failures.
    # --max-time absent: transfer duration is unpredictable for external
    #   downloads (GitHub); for local file-server downloads the small size
    #   makes it irrelevant.
    $dl = Invoke-SshClientCommand `
              -SshClient $SshClient `
              -Command   ("sudo -u $RunnerUser curl -fsSL " +
                          "--connect-timeout 15 --retry 3 --retry-delay 5 " +
                          "-o '$tarPath' '$TarUrl'") `
              -ErrorAction Stop
    if ($dl.ExitStatus -ne 0) {
        throw "${prefix}curl download failed: $($dl.Error)"
    }

    Write-Host "${prefix}Tarball downloaded: $tarName" -ForegroundColor Green
}
