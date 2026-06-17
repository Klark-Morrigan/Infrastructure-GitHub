# ---------------------------------------------------------------------------
# Get-PendingDeployment
#   Returns the oldest deployment for the given repo and environment that
#   has not yet reached a terminal status. Terminal statuses are:
#   success, failure, error, inactive.
#
#   Returns $null when there is no pending deployment, so callers can
#   use a simple null-check to decide whether to wait and poll again.
#
#   The polling agent calls this on each tick. When a deployment is
#   returned the agent posts an 'in_progress' status, runs the tests,
#   then calls Set-DeploymentStatus with the final result.
#
#   Cost note: GitHub never deletes deployments, so an environment's list
#   endpoint keeps returning a full page of historical, already-terminal
#   deployments. Fetching every one's statuses on every poll is an
#   N+1 fan-out that exhausts the API rate limit. -CreatedSince lets the
#   caller skip the status fetch for deployments older than the cutoff,
#   collapsing a quiet poll to a single list call.
# ---------------------------------------------------------------------------

function Get-PendingDeployment {
    [CmdletBinding()]
    param(
        # Bearer token (PAT or GitHub App installation token).
        [Parameter(Mandatory)]
        [string] $Token,

        # GitHub organisation or user that owns the repo.
        [Parameter(Mandatory)]
        [string] $Owner,

        # Repository name (without the owner prefix).
        [Parameter(Mandatory)]
        [string] $Repo,

        # The deployment environment name to filter by.
        # Must match the 'environment' field on the deployment exactly.
        [Parameter(Mandatory)]
        [string] $Environment,

        # Skip the per-deployment status fetch for any deployment created
        # before this UTC instant. A pending deployment is always recent, so
        # anything older than the cutoff cannot be the work we are waiting
        # for - and historical deployments are all terminal anyway. Default
        # MinValue checks every returned deployment (the prior behaviour);
        # the polling agent passes a recent cutoff to stop the N+1 fan-out
        # over months of accumulated history from exhausting the rate limit.
        [Parameter()]
        [DateTime] $CreatedSince = [DateTime]::MinValue
    )

    $terminalStatuses = @('success', 'failure', 'error', 'inactive')

    $deployments = Invoke-GitHubApi `
        -Token    $Token `
        -Endpoint "repos/$Owner/$Repo/deployments?environment=$Environment"

    foreach ($deployment in ($deployments | Sort-Object id)) {
        # Cheap, call-free skip of stale deployments before spending an API
        # call on their statuses. Property access is guarded so callers (and
        # tests) whose deployment objects omit created_at keep working; an
        # absent timestamp is treated as in-window so we never skip a real
        # pending deployment just because the field was missing.
        if ($CreatedSince -ne [DateTime]::MinValue -and
            $deployment.PSObject.Properties['created_at'] -and
            $deployment.created_at) {
            $createdAt = [DateTimeOffset] $deployment.created_at
            if ($createdAt.UtcDateTime -lt $CreatedSince) { continue }
        }

        $statuses = Invoke-GitHubApi `
            -Token    $Token `
            -Endpoint "repos/$Owner/$Repo/deployments/$($deployment.id)/statuses"

        # A deployment with no statuses at all is pending. A deployment
        # whose most-recent status is non-terminal is still in flight.
        # The statuses endpoint returns them newest-first.
        $statusArray = ConvertTo-Array $statuses
        $latestState = if ($statusArray.Count -gt 0) { $statusArray[0].state } else { $null }

        if ($latestState -notin $terminalStatuses) {
            return $deployment
        }
    }

    return $null
}
