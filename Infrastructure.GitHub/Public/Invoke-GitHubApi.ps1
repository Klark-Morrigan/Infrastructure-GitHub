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
#   Returns the raw Invoke-RestMethod response. Callers extract the
#   fields they need (.token, .runners, .id, etc.).
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
        [hashtable] $Body
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

    $params = @{
        Uri         = $resolvedUri
        Method      = $Method
        Headers     = @{
            'Authorization' = "Bearer $Token"
            'User-Agent'    = 'Infrastructure'
            'Content-Type'  = 'application/json'
        }
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    Invoke-RestMethod @params
}
