# ---------------------------------------------------------------------------
# New-GitHubRequestHeader
#   Builds the per-call request headers every REST read in this module sends
#   on top of Invoke-GitHubApi's fixed auth/User-Agent set: the versioned
#   media type and an explicit API-version pin.
#
#   Pinning X-GitHub-Api-Version matters for a long-lived polling caller -
#   without it GitHub is free to move the default version underneath a
#   dashboard that has been running for weeks, changing response shapes with
#   no deploy on our side.
#
#   A pure in-memory factory: it returns a fresh hashtable each call so the
#   caller can add its own keys (notably 'If-None-Match') without mutating
#   shared state.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function New-GitHubRequestHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # The date-stamped REST API version GitHub documents as current. Bumping
    # it is a deliberate act: read the changelog for the target version first,
    # because response shapes can change between versions.
    $apiVersion = '2022-11-28'

    @{
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = $apiVersion
    }
}
