# ---------------------------------------------------------------------------
# Test-GitHubIdempotentMethod
#   Answers "is it safe to re-send this request after a failure whose outcome
#   we could not observe?".
#
#   The question that matters for retry is double-execution, not HTTP
#   idempotency in the RFC sense: a replayed POST to actions/runners/
#   remove-token mints a second token, and a replayed DELETE that already
#   succeeded comes back 404 and reads as a teardown failure. A read carries
#   no such risk, so reads alone get the full transient-failure policy;
#   everything else is restricted to failures that provably never reached
#   GitHub (see New-GitHubWriteRetryStrategy).
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function Test-GitHubIdempotentMethod {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Method
    )

    # -contains is case-insensitive, so 'get', 'Get' and 'GET' all match -
    # callers pass whatever casing reads well at their call site.
    $safeToReplayMethods = @('Get', 'Head', 'Options')

    return ($safeToReplayMethods -contains $Method)
}
