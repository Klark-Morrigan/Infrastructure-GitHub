# ---------------------------------------------------------------------------
# Invoke-GitHubApi
#   General-purpose GitHub REST API caller. Handles authentication,
#   User-Agent, and JSON serialization in one place so callers only
#   need to supply a token, an endpoint or URI, and an optional body.
#
#   -Endpoint accepts a path relative to https://api.github.com/ and is
#   the preferred form for all standard GitHub REST API calls (keeps the
#   base URL out of call sites). -Uri accepts a full URL and is reserved
#   for cases where the base differs - e.g. pagination next-links.
#   The two parameters are mutually exclusive.
#
#   -Token accepts both PATs and GitHub App installation tokens; both
#   are bearer tokens and are interchangeable at the HTTP level.
#
#   By default it returns the raw Invoke-RestMethod response, and callers
#   extract the fields they need (.token, .runners, .id, etc.).
#
#   -Header and -IncludeResponseDetail exist for conditional (ETag) requests,
#   which a polling caller needs to stay inside the hourly rate limit: a 304
#   Not Modified is not charged against the budget, but observing one requires
#   sending a request header and reading back both the response headers and a
#   non-success status code. Both are opt-in and change nothing for callers
#   that omit them.
#
#   The response detail is RETURNED rather than published through
#   -*Variable out-parameters mirroring Invoke-RestMethod's own. That shape
#   was tried and does not work here: this function ships inside a module, so
#   a function running in module session state cannot write a variable into
#   the scope of a script that imported it. `Set-Variable -Scope 1` lands in
#   the module's own parent scope and $PSCmdlet.SessionState.PSVariable.Set
#   lands in the callee's - both silently, with the caller's variable left
#   untouched. A return value crosses the boundary unambiguously.
# ---------------------------------------------------------------------------

function Invoke-GitHubApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Token,

        # Path relative to https://api.github.com/ - preferred for all standard
        # GitHub REST API calls. Mutually exclusive with -Uri.
        [Parameter()]
        [string] $Endpoint,

        # Full URL - use for pagination next-links or non-api.github.com hosts.
        # Mutually exclusive with -Endpoint.
        [Parameter()]
        [string] $Uri,

        [Parameter()]
        [string] $Method = 'Get',

        [Parameter()]
        [hashtable] $Body,

        # Extra request headers, merged over the three defaults below. Covers
        # per-call concerns the fixed set cannot express - 'If-None-Match' for
        # a conditional GET, or the 'Accept' / 'X-GitHub-Api-Version' pins.
        # A key that collides with a default replaces it, so a caller that
        # must send a different Content-Type still can.
        [Parameter()]
        [hashtable] $Header,

        # Return an object carrying .Content, .Headers, and .StatusCode
        # instead of the bare body.
        #
        # It also disables Invoke-RestMethod's built-in error check: the
        # status this mainly exists to observe - 304 Not Modified - is a
        # non-success code that would otherwise throw before the caller could
        # see it. The trade is that the caller then owns ALL status handling,
        # 4xx and 5xx included; nothing throws on a bad response any more.
        [Parameter()]
        [switch] $IncludeResponseDetail
    )

    $hasEndpoint = $PSBoundParameters.ContainsKey('Endpoint')
    $hasUri      = $PSBoundParameters.ContainsKey('Uri')

    if ($hasEndpoint -and $hasUri) {
        throw '-Endpoint and -Uri are mutually exclusive.'
    }
    if (-not $hasEndpoint -and -not $hasUri) {
        throw 'Either -Endpoint or -Uri must be specified.'
    }

    $resolvedUri = if ($hasEndpoint) { "https://api.github.com/$Endpoint" } else { $Uri }

    $headers = @{
        'Authorization' = "Bearer $Token"
        'User-Agent'    = 'Infrastructure'
        'Content-Type'  = 'application/json'
    }

    if ($PSBoundParameters.ContainsKey('Header')) {
        foreach ($extra in $Header.GetEnumerator()) {
            $headers[$extra.Key] = $extra.Value
        }
    }

    $params = @{
        Uri         = $resolvedUri
        Method      = $Method
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    if (-not $IncludeResponseDetail) {
        return Invoke-RestMethod @params
    }

    # Invoke-RestMethod writes these into the scope of ITS caller, which is
    # this function - a direct, same-session-state hop that does work.
    $localHeadersName = 'gitHubApiResponseHeaders'
    $localStatusName  = 'gitHubApiStatusCode'

    $params['ResponseHeadersVariable'] = $localHeadersName
    $params['StatusCodeVariable']      = $localStatusName
    $params['SkipHttpErrorCheck']      = $true

    $content = Invoke-RestMethod @params

    # Get-Variable rather than a bare reference: a mocked Invoke-RestMethod
    # (the unit suites) never assigns these, and Set-StrictMode -Version
    # Latest makes reading an unassigned variable a terminating error.
    # SilentlyContinue yields $null, the honest answer for "no headers".
    [PSCustomObject]@{
        Content    = $content
        Headers    = Get-Variable -Name $localHeadersName -ValueOnly -ErrorAction SilentlyContinue
        StatusCode = Get-Variable -Name $localStatusName  -ValueOnly -ErrorAction SilentlyContinue
    }
}
