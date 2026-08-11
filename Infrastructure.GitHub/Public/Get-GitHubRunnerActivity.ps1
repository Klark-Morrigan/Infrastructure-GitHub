function Get-GitHubRunnerActivity {
    <#
    .SYNOPSIS
        Returns a point-in-time picture of every self-hosted runner registered
        to the given repositories, joined to the job each one is executing.

    .DESCRIPTION
        The GitHub API splits this picture across two unrelated endpoints. The
        runners endpoint knows which runners exist and whether each is `busy`,
        but not what it is busy WITH. The jobs endpoint knows the workflow, the
        job, and the step, but is reachable only per workflow-run. This
        function performs the join - matching a job's `runner_name` back to the
        registered runner - so callers get one row per runner with the work on
        it attached.

        Built to be called repeatedly (a polling dashboard is the intended
        caller), so the call pattern is shaped around the hourly rate limit:

          - The runner list and the run lists are fetched with conditional
            requests. Pass the same -Cache hashtable on every tick and an
            unchanged list answers 304, which GitHub does not charge.
          - The in-progress runs are fetched only when at least one runner
            reports itself busy. A job cannot be on our fleet if no runner is
            executing anything, so an idle repo skips that fan-out entirely.
          - The per-run jobs call is never cached. A job stepping forward does
            not alter the parent run object, so a cached run list would answer
            304 while the step an operator is watching moves on.

        Queued jobs are reported separately, filtered to those whose requested
        labels intersect the labels our runners advertise - a job waiting on a
        GitHub-hosted image is not this fleet's business.

        A repository that fails (auth, rate limit, network) is recorded in
        .Failures and the remaining repositories still report. One bad repo
        must not blank the whole board.

    .PARAMETER Token
        Bearer token (PAT or GitHub App installation token). Needs read access
        to Actions and to self-hosted runner administration on each repo.

    .PARAMETER Repository
        One or more 'owner/repo' slugs to poll.

    .PARAMETER Cache
        Conditional-request cache, MUTATED IN PLACE. Hand the same hashtable
        back on each call to keep repeat polls off the rate limit. Omit it and
        every request is unconditional (correct, just more expensive).

    .OUTPUTS
        [PSCustomObject] with four members:
          .Runners    - one row per registered runner. Repository, Name, Id,
                        Status ('online'/'offline'), Busy, Labels, and - when
                        the runner is executing something - WorkflowName,
                        JobName, CurrentStep, StartedAt (UTC), Url.
          .QueuedJobs - jobs waiting for a runner in this fleet: Repository,
                        WorkflowName, JobName, Labels, QueuedAt (UTC), Url.
          .Failures   - Repository + Message for each repo that could not be
                        polled.
          .RateLimit  - Remaining, Limit, ResetsAt (UTC) from the last response
                        that carried the headers; $null if none did.

    .EXAMPLE
        $cache = @{}
        while ($true) {
            $activity = Get-GitHubRunnerActivity -Token $tok `
                            -Repository 'Klark-Morrigan/Common-Automation' -Cache $cache
            $activity.Runners | Format-Table Name, Status, JobName, CurrentStep
            Start-Sleep -Seconds 10
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Token,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Repository,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Cache
    )

    # GitHub's maximum page size. Every list this function reads (runners per
    # repo, non-terminal runs per repo, jobs per run) is far below it in any
    # realistic fleet, so one page is the whole answer and no pagination loop
    # is warranted. A fleet that outgrows this would silently truncate - the
    # ceiling to revisit if that ever becomes plausible.
    $maxItemsPerPage = 100

    $runnerRows = [System.Collections.Generic.List[object]]::new()
    $queuedRows = [System.Collections.Generic.List[object]]::new()
    $failures   = [System.Collections.Generic.List[object]]::new()
    $rateLimit  = $null

    foreach ($slug in $Repository) {
        try {
            # -- Registered runners ------------------------------------------
            $runnersResponse = Invoke-GitHubConditionalGet `
                -Token    $Token `
                -Cache    $Cache `
                -Endpoint "repos/$slug/actions/runners?per_page=$maxItemsPerPage"
            if ($null -ne $runnersResponse.RateLimit) { $rateLimit = $runnersResponse.RateLimit }

            $repoRunners = @(Get-GitHubResponseProperty $runnersResponse.Value 'runners' @())

            # Union of every label this repo's fleet advertises. Used below to
            # tell a queued job that could land on one of our runners from one
            # waiting on a GitHub-hosted image. Case-insensitive because
            # GitHub matches runner labels that way.
            $fleetLabels = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($runner in $repoRunners) {
                foreach ($label in @(Get-GitHubResponseProperty $runner 'labels' @())) {
                    $labelName = Get-GitHubResponseProperty $label 'name'
                    if ($labelName) { $null = $fleetLabels.Add([string] $labelName) }
                }
            }

            # -- Non-terminal runs worth opening -----------------------------
            # 'queued' is always fetched: a queue with nothing running is
            # precisely the state an operator most needs to see. 'in_progress'
            # is fetched only when a runner is actually busy (see .DESCRIPTION).
            $anyBusy = @($repoRunners | Where-Object {
                Get-GitHubResponseProperty $_ 'busy' $false
            }).Count -gt 0

            $runStatuses = if ($anyBusy) { @('queued', 'in_progress') } else { @('queued') }

            $runs = [System.Collections.Generic.List[object]]::new()
            foreach ($runStatus in $runStatuses) {
                $runsResponse = Invoke-GitHubConditionalGet `
                    -Token    $Token `
                    -Cache    $Cache `
                    -Endpoint "repos/$slug/actions/runs?status=$runStatus&per_page=$maxItemsPerPage"
                if ($null -ne $runsResponse.RateLimit) { $rateLimit = $runsResponse.RateLimit }

                foreach ($run in @(Get-GitHubResponseProperty $runsResponse.Value 'workflow_runs' @())) {
                    $runs.Add($run)
                }
            }

            # -- Open each run's jobs and bucket them ------------------------
            # jobByRunner: runner name -> the job it is executing. Built here
            # and consumed by the runner rows below.
            $jobByRunner = @{}
            $seenRunIds  = [System.Collections.Generic.HashSet[long]]::new()

            foreach ($run in $runs) {
                $runId = Get-GitHubResponseProperty $run 'id'
                # Dedupe defensively: a run that transitions between the two
                # list calls could appear under both statuses.
                if ($null -eq $runId -or -not $seenRunIds.Add([long] $runId)) { continue }

                $jobsBody = Invoke-GitHubApi `
                    -Token    $Token `
                    -Header   (New-GitHubRequestHeader) `
                    -Endpoint "repos/$slug/actions/runs/$runId/jobs?per_page=$maxItemsPerPage"

                foreach ($job in @(Get-GitHubResponseProperty $jobsBody 'jobs' @())) {
                    $jobStatus  = Get-GitHubResponseProperty $job 'status'
                    $runnerName = Get-GitHubResponseProperty $job 'runner_name'

                    if ($jobStatus -eq 'in_progress' -and $runnerName) {
                        $jobByRunner[[string] $runnerName] = $job
                        continue
                    }

                    if ($jobStatus -ne 'queued') { continue }

                    # A queued job names the labels it is waiting for. Report
                    # it only if this fleet could satisfy at least one of them.
                    $jobLabels = @(Get-GitHubResponseProperty $job 'labels' @())
                    $isForThisFleet = @($jobLabels |
                        Where-Object { $fleetLabels.Contains([string] $_) }).Count -gt 0
                    if (-not $isForThisFleet) { continue }

                    # created_at is when the job entered the queue; started_at
                    # is only meaningful once it is picked up. Prefer the
                    # former and fall back for older API responses.
                    $queuedAt = Get-GitHubResponseProperty $job 'created_at'
                    if (-not $queuedAt) { $queuedAt = Get-GitHubResponseProperty $job 'started_at' }

                    $queuedRows.Add([PSCustomObject]@{
                        Repository   = $slug
                        WorkflowName = Get-GitHubResponseProperty $job 'workflow_name'
                        JobName      = Get-GitHubResponseProperty $job 'name'
                        Labels       = $jobLabels
                        QueuedAt     = ConvertFrom-GitHubTimestamp $queuedAt
                        Url          = Get-GitHubResponseProperty $job 'html_url'
                    })
                }
            }

            # -- One row per registered runner -------------------------------
            foreach ($runner in $repoRunners) {
                $runnerName = [string] (Get-GitHubResponseProperty $runner 'name')

                # $null when idle - and also when the runner is busy with work
                # we could not open (a run outside the fetched page). The row
                # then reads BUSY with no detail, which is the honest answer.
                $job = if ($runnerName -and $jobByRunner.ContainsKey($runnerName)) {
                    $jobByRunner[$runnerName]
                } else {
                    $null
                }

                $runnerRows.Add([PSCustomObject]@{
                    Repository   = $slug
                    Name         = $runnerName
                    Id           = Get-GitHubResponseProperty $runner 'id'
                    Status       = Get-GitHubResponseProperty $runner 'status' 'unknown'
                    Busy         = [bool] (Get-GitHubResponseProperty $runner 'busy' $false)
                    Labels       = @(@(Get-GitHubResponseProperty $runner 'labels' @()) |
                                     ForEach-Object { Get-GitHubResponseProperty $_ 'name' })
                    WorkflowName = Get-GitHubResponseProperty $job 'workflow_name'
                    JobName      = Get-GitHubResponseProperty $job 'name'
                    CurrentStep  = Get-GitHubJobCurrentStep $job
                    StartedAt    = ConvertFrom-GitHubTimestamp (
                                       Get-GitHubResponseProperty $job 'started_at')
                    Url          = Get-GitHubResponseProperty $job 'html_url'
                })
            }
        }
        catch {
            $failures.Add([PSCustomObject]@{
                Repository = $slug
                Message    = $_.Exception.Message
            })
        }
    }

    [PSCustomObject]@{
        Runners    = $runnerRows.ToArray()
        QueuedJobs = $queuedRows.ToArray()
        Failures   = $failures.ToArray()
        RateLimit  = $rateLimit
    }
}
