<#
.NOTES
    Dot-sourced by Infrastructure.GitHub.psm1. The consumed surface is
    New-GitHubWriteRetryStrategy; Test-GitHubConnectFailure is a file-private
    helper kept alongside the factory so the classification policy lives next
    to its sole consumer - mirroring the layout of Common.PowerShell's
    New-TransientNetworkRetryStrategy.

    Both are private to the module. If a second caller ever needs this
    classification the pair should move to Common.PowerShell's
    TransientErrorStrategies folder rather than being copied.
#>

# ---------------------------------------------------------------------------
# Test-GitHubConnectFailure (private)
#   Decides whether a failure happened BEFORE the request could reach GitHub.
#   That is a stronger claim than "transient", and it is the only class of
#   failure a write can retry without risking a second execution server-side.
#
#   The evidence is a System.Net.Sockets.SocketException somewhere in the
#   exception chain (HttpClient wraps it in HttpRequestException) whose
#   SocketErrorCode is a name-resolution or connect-establishment error.
#   Either way no request bytes ever left the machine, so a replay cannot
#   duplicate work GitHub has already done.
#
#   Deliberately NARROWER than Common.PowerShell's transient-network policy,
#   which also matches timeouts, mid-flight connection resets and 5xx
#   responses. Each of those can mean GitHub received and acted on the
#   request before the response was lost - safe to replay for a read,
#   not for a write.
# ---------------------------------------------------------------------------

function Test-GitHubConnectFailure {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    # Socket errors raised while resolving the name or establishing the
    # connection. HostNotFound is the DNS case ("No such host is known");
    # the rest are the connect attempt failing outright.
    #
    # TimedOut and ConnectionReset are deliberately absent: both can fire
    # after the request was written to the wire, so the server may have
    # processed it.
    $preRequestSocketErrors = @(
        [System.Net.Sockets.SocketError]::HostNotFound,
        [System.Net.Sockets.SocketError]::TryAgain,
        [System.Net.Sockets.SocketError]::NoData,
        [System.Net.Sockets.SocketError]::ConnectionRefused,
        [System.Net.Sockets.SocketError]::NetworkUnreachable,
        [System.Net.Sockets.SocketError]::HostUnreachable,
        [System.Net.Sockets.SocketError]::NetworkDown
    )

    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        if ($ex -is [System.Net.Sockets.SocketException]) {
            return ($preRequestSocketErrors -contains $ex.SocketErrorCode)
        }

        $ex = $ex.InnerException
    }

    return $false
}

function New-GitHubWriteRetryStrategy {
    <#
    .SYNOPSIS
        Builds a retry strategy hashtable that matches only failures which
        provably never reached GitHub, for use on non-idempotent calls.

    .DESCRIPTION
        Returned shape is the standard retry-strategy contract consumed by
        Invoke-WithRetry:

            @{
                Name        = 'GitHubConnectFailure'
                ShouldRetry = { param($err) <bool> }
            }

        Matches DNS resolution failures and failed connect attempts, and
        nothing else. Timeouts, mid-flight resets and 5xx responses are
        classified as permanent here even though they are genuinely
        transient, because a POST/PATCH/DELETE replayed after one of them
        can double-execute.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock   { Invoke-RestMethod @params } `
            -RetryStrategy (New-GitHubWriteRetryStrategy)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        Name        = 'GitHubConnectFailure'
        ShouldRetry = {
            param([System.Management.Automation.ErrorRecord] $ErrorRecord)
            Test-GitHubConnectFailure -ErrorRecord $ErrorRecord
        }
    }
}
