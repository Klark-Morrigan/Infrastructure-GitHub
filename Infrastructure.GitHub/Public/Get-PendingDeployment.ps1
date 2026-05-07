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
        [string] $Environment
    )

    $terminalStatuses = @('success', 'failure', 'error', 'inactive')

    $deployments = Invoke-GitHubApi `
        -Token    $Token `
        -Endpoint "repos/$Owner/$Repo/deployments?environment=$Environment"

    foreach ($deployment in ($deployments | Sort-Object id)) {
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
