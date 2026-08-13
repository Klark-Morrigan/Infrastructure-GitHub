# ---------------------------------------------------------------------------
# Get-GitHubJobCurrentStep
#   Answers "which step is this job on right now" from a jobs-API job object.
#   Returns $null when the job is $null or carries no usable steps.
#
#   The steps array is the only place the API exposes sub-job progress, and it
#   is what turns a dashboard row from "busy" into something an operator can
#   act on. Two cases have to be handled separately:
#     - one step is 'in_progress' - the normal case, that is the answer.
#     - no step is in progress - the job is between steps (or the runner has
#       not reported yet). The most recently CONCLUDED step is then the truest
#       statement of where the job has got to, so report that rather than
#       showing nothing.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function Get-GitHubJobCurrentStep {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # A job object from /repos/{owner}/{repo}/actions/runs/{id}/jobs.
        # $null is accepted (an idle runner has no job) and yields $null.
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $Job
    )

    $steps = @(Get-GitHubResponseProperty $Job 'steps' @())
    if ($steps.Count -eq 0) { return $null }

    $running = $steps |
        Where-Object { (Get-GitHubResponseProperty $_ 'status') -eq 'in_progress' } |
        Select-Object -First 1
    if ($null -ne $running) { return (Get-GitHubResponseProperty $running 'name') }

    # Steps arrive in execution order, so the last one with a conclusion is
    # the furthest the job has reached.
    $concluded = $steps |
        Where-Object { $null -ne (Get-GitHubResponseProperty $_ 'conclusion') } |
        Select-Object -Last 1
    if ($null -ne $concluded) { return (Get-GitHubResponseProperty $concluded 'name') }

    return $null
}
