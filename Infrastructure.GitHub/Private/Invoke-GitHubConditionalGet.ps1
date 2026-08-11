# ---------------------------------------------------------------------------
# Invoke-GitHubConditionalGet
#   A single GET issued as a conditional request: sends the cached ETag as
#   'If-None-Match', replays the cached payload when GitHub answers 304 Not
#   Modified, and refreshes the cache entry when it answers 200.
#
#   This exists to make polling affordable. GitHub does not charge a 304
#   against the hourly rate limit, so a dashboard watching an idle fleet -
#   where the runner list and the queue are identical tick after tick - costs
#   effectively nothing, and the budget stays available for the ticks where
#   something is actually happening.
#
#   Returns an object with two members so a caller gets the data and the
#   budget reading from one call site:
#     .Value     - the parsed response body (cached payload on a 304)
#     .RateLimit - the X-RateLimit-* reading, or $null if GitHub sent none
#
#   Only responses that carry an ETag are cached: without one the entry could
#   never be revalidated, and a payload that can never be proven current is
#   worse than no cache at all.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function Invoke-GitHubConditionalGet {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Token,

        # Path relative to https://api.github.com/. Doubles as the cache key,
        # so two calls that differ only by query string cache independently.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Endpoint,

        # Conditional-request cache, MUTATED IN PLACE. Omit it (or pass $null)
        # to make every call unconditional.
        [Parameter()]
        [AllowNull()]
        [hashtable] $Cache
    )

    $httpNotModified   = 304
    $httpLowestSuccess = 200
    $httpLowestFailure = 300

    $requestHeader = New-GitHubRequestHeader

    $cached = if ($null -ne $Cache -and $Cache.ContainsKey($Endpoint)) {
        $Cache[$Endpoint]
    } else {
        $null
    }
    if ($null -ne $cached) { $requestHeader['If-None-Match'] = $cached.ETag }

    $response = Invoke-GitHubApi `
        -Token                 $Token `
        -Endpoint              $Endpoint `
        -Header                $requestHeader `
        -IncludeResponseDetail

    $body           = $response.Content
    $responseHeader = $response.Headers
    $statusCode     = $response.StatusCode

    # Read the budget before any early return - a 304 reports it too, and it
    # is the reading a caller most wants when it is polling hard.
    $remaining = Get-HttpHeaderValue $responseHeader 'X-RateLimit-Remaining'
    $rateLimit = if ($null -ne $remaining) {
        $limit = Get-HttpHeaderValue $responseHeader 'X-RateLimit-Limit'
        $reset = Get-HttpHeaderValue $responseHeader 'X-RateLimit-Reset'
        [PSCustomObject]@{
            Remaining = [int] $remaining
            Limit     = if ($null -ne $limit) { [int] $limit } else { 0 }
            ResetsAt  = if ($null -ne $reset) {
                [DateTimeOffset]::FromUnixTimeSeconds([long] $reset).UtcDateTime
            } else {
                $null
            }
        }
    } else {
        $null
    }

    if ($statusCode -eq $httpNotModified) {
        # Only reachable when we sent an If-None-Match, so $cached is set. The
        # guard covers a server that returns 304 unbidden - replaying a
        # payload we do not have would surface as a confusing null downstream.
        if ($null -eq $cached) {
            throw "GitHub API GET $Endpoint returned HTTP $httpNotModified with no cached payload to replay."
        }
        return [PSCustomObject]@{ Value = $cached.Payload; RateLimit = $rateLimit }
    }

    # -StatusCodeVariable turns off Invoke-RestMethod's own error check, so
    # every non-success status has to be raised here instead.
    if ($statusCode -lt $httpLowestSuccess -or $statusCode -ge $httpLowestFailure) {
        throw "GitHub API GET $Endpoint failed with HTTP $statusCode."
    }

    $etag = Get-HttpHeaderValue $responseHeader 'ETag'
    if ($null -ne $Cache -and $etag) {
        $Cache[$Endpoint] = [PSCustomObject]@{ ETag = $etag; Payload = $body }
    }

    [PSCustomObject]@{ Value = $body; RateLimit = $rateLimit }
}
