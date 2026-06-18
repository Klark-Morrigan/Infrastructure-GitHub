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
#   GitHub never deletes deployments, so the list endpoint returns a full
#   page of historical, terminal deployments. -CreatedSince lets the caller
#   skip the status fetch for ones older than the cutoff, keeping a quiet
#   poll to a single list call instead of an N+1 fan-out.
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
        # older ones cannot be the work we are waiting for (and are terminal
        # anyway). Default MinValue checks every deployment; the polling
        # agent passes a recent cutoff to keep each poll a single list call.
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
