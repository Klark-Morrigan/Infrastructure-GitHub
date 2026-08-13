BeforeAll {
    Set-StrictMode -Version Latest

    $modulePath = "$PSScriptRoot\..\Infrastructure.GitHub"
    . "$modulePath\Private\ConvertFrom-GitHubTimestamp.ps1"
    . "$modulePath\Private\Get-GitHubJobCurrentStep.ps1"
    . "$modulePath\Private\Get-GitHubResponseProperty.ps1"
    . "$modulePath\Private\Get-HttpHeaderValue.ps1"
    . "$modulePath\Private\Invoke-GitHubConditionalGet.ps1"
    . "$modulePath\Private\New-GitHubRequestHeader.ps1"
    . "$modulePath\Public\Invoke-GitHubApi.ps1"
    . "$modulePath\Public\Get-GitHubRunnerActivity.ps1"

    # Payloads go through ConvertFrom-Json rather than being hand-built as
    # hashtables so the tests exercise the same PSCustomObject shape (and the
    # same absent-property behaviour under StrictMode) the real API produces.
    function ConvertTo-ApiPayload {
        param([string] $Json)
        $Json | ConvertFrom-Json
    }
}

Describe 'Get-GitHubRunnerActivity' {

    BeforeEach {
        # Defaults: a two-runner fleet with nothing running and nothing queued.
        # Individual tests overwrite the pieces they care about.
        $script:runnersPayload = ConvertTo-ApiPayload @'
{
  "total_count": 2,
  "runners": [
    { "id": 1, "name": "ubuntu-01-ci-1", "status": "online",  "busy": false,
      "labels": [ { "name": "self-hosted" }, { "name": "linux" } ] },
    { "id": 2, "name": "ubuntu-01-ci-2", "status": "offline", "busy": false,
      "labels": [ { "name": "self-hosted" }, { "name": "linux" } ] }
  ]
}
'@
        $script:queuedRunsPayload     = ConvertTo-ApiPayload '{ "workflow_runs": [] }'
        $script:inProgressRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [] }'
        $script:jobsPayload           = ConvertTo-ApiPayload '{ "jobs": [] }'
        $script:rateLimitPayload      = [PSCustomObject]@{
            Remaining = 4987
            Limit     = 5000
            ResetsAt  = [DateTime]::new(2026, 8, 6, 12, 0, 0, [DateTimeKind]::Utc)
        }
        # A deliberately lower reading for the per-run jobs calls. The list
        # calls all run before the jobs fan-out, so a result still carrying
        # the list reading is proof the jobs calls went unaccounted for.
        $script:jobsRateLimitPayload  = [PSCustomObject]@{
            Remaining = 4000
            Limit     = 5000
            ResetsAt  = [DateTime]::new(2026, 8, 6, 12, 0, 0, [DateTimeKind]::Utc)
        }

        # The two I/O boundaries. Everything below them (parsing, joining,
        # label filtering) is the code under test and stays real.
        Mock Invoke-GitHubConditionalGet {
            $value =
                if     ($Endpoint -match '/actions/runners') { $script:runnersPayload }
                elseif ($Endpoint -match 'status=in_progress') { $script:inProgressRunsPayload }
                elseif ($Endpoint -match 'status=queued') { $script:queuedRunsPayload }
                elseif ($Endpoint -match '/jobs') { $script:jobsPayload }
                else { $null }

            $budget = if ($Endpoint -match '/jobs') {
                $script:jobsRateLimitPayload
            } else {
                $script:rateLimitPayload
            }

            [PSCustomObject]@{ Value = $value; RateLimit = $budget }
        }

        # Every read this function makes goes through the conditional caller,
        # the uncached jobs one included - that is what keeps the budget
        # accounting complete. Fail loudly on a direct call rather than let a
        # regression reach the wire unmocked.
        Mock Invoke-GitHubApi {
            throw "Unexpected direct Invoke-GitHubApi call: $Endpoint"
        }
    }

    # ------------------------------------------------------------------
    Context 'runner rows' {
    # ------------------------------------------------------------------

        It 'returns one row per registered runner' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners.Count | Should -Be 2
            $result.Runners[0].Name | Should -Be 'ubuntu-01-ci-1'
            $result.Runners[1].Name | Should -Be 'ubuntu-01-ci-2'
        }

        It 'stamps each row with the repository it came from' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].Repository | Should -Be 'owner/repo'
        }

        It 'carries the online and offline status through' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].Status | Should -Be 'online'
            $result.Runners[1].Status | Should -Be 'offline'
        }

        It 'flattens runner labels to their names' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].Labels | Should -Be @('self-hosted', 'linux')
        }

        It 'leaves the job fields empty for an idle runner' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].WorkflowName | Should -BeNullOrEmpty
            $result.Runners[0].JobName      | Should -BeNullOrEmpty
            $result.Runners[0].CurrentStep  | Should -BeNullOrEmpty
            $result.Runners[0].StartedAt    | Should -BeNullOrEmpty
        }

        It 'polls every repository it is given' {
            $result = Get-GitHubRunnerActivity -Token 't' `
                          -Repository @('owner/one', 'owner/two')

            $result.Runners.Count | Should -Be 4
            ($result.Runners.Repository | Select-Object -Unique) |
                Should -Be @('owner/one', 'owner/two')
        }
    }

    # ------------------------------------------------------------------
    Context 'joining a job to the runner executing it' {
    # ------------------------------------------------------------------

        BeforeEach {
            $script:runnersPayload = ConvertTo-ApiPayload @'
{
  "runners": [
    { "id": 1, "name": "ubuntu-01-ci-1", "status": "online", "busy": true,
      "labels": [ { "name": "self-hosted" } ] }
  ]
}
'@
            $script:inProgressRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 900 } ] }'
            $script:jobsPayload = ConvertTo-ApiPayload @'
{
  "jobs": [
    {
      "id": 5000,
      "name": "build",
      "status": "in_progress",
      "workflow_name": "CI",
      "runner_name": "ubuntu-01-ci-1",
      "started_at": "2026-08-06T11:58:00Z",
      "html_url": "https://github.com/owner/repo/actions/runs/900/job/5000",
      "steps": [
        { "name": "Set up job",  "status": "completed",   "conclusion": "success" },
        { "name": "Run tests",   "status": "in_progress", "conclusion": null },
        { "name": "Post cleanup","status": "queued",      "conclusion": null }
      ]
    }
  ]
}
'@
        }

        It 'attaches the workflow and job names to the matching runner' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].Busy         | Should -BeTrue
            $result.Runners[0].WorkflowName | Should -Be 'CI'
            $result.Runners[0].JobName      | Should -Be 'build'
        }

        It 'reports the step currently in progress' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].CurrentStep | Should -Be 'Run tests'
        }

        It 'converts the start time to UTC' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].StartedAt.Kind | Should -Be ([DateTimeKind]::Utc)
            $result.Runners[0].StartedAt      |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }

        It 'does not attach a job whose runner name matches no registered runner' {
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 1, "name": "build", "status": "in_progress",
             "workflow_name": "CI", "runner_name": "some-other-runner" } ] }
'@
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].Busy    | Should -BeTrue
            $result.Runners[0].JobName | Should -BeNullOrEmpty
        }

        It 'opens a run appearing under both statuses only once' {
            $script:queuedRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 900 } ] }'

            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            Should -Invoke Invoke-GitHubConditionalGet -Times 1 -Exactly `
                -ParameterFilter { $Endpoint -match '/runs/900/jobs' }
        }
    }

    # ------------------------------------------------------------------
    Context 'rate-limit-aware call pattern' {
    # ------------------------------------------------------------------

        It 'skips the in-progress runs call when no runner is busy' {
            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            Should -Invoke Invoke-GitHubConditionalGet -Times 0 -Exactly `
                -ParameterFilter { $Endpoint -match 'status=in_progress' }
        }

        It 'fetches queued runs even when the whole fleet is idle' {
            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            Should -Invoke Invoke-GitHubConditionalGet -Times 1 -Exactly `
                -ParameterFilter { $Endpoint -match 'status=queued' }
        }

        It 'fetches in-progress runs once a runner reports busy' {
            $script:runnersPayload = ConvertTo-ApiPayload @'
{ "runners": [ { "id": 1, "name": "r1", "status": "online", "busy": true,
                "labels": [ { "name": "self-hosted" } ] } ] }
'@
            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            Should -Invoke Invoke-GitHubConditionalGet -Times 1 -Exactly `
                -ParameterFilter { $Endpoint -match 'status=in_progress' }
        }

        It 'passes the caller cache through to every list call' {
            $cache = @{}

            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo' -Cache $cache

            Should -Invoke Invoke-GitHubConditionalGet -ParameterFilter {
                $null -ne $Cache
            }
        }

        It 'fetches jobs unconditionally so a stepping job is never served from cache' {
            $script:queuedRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 900 } ] }'

            $null = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo' -Cache @{}

            # Withholding the cache - not bypassing the conditional caller - is
            # what keeps the jobs read off the cache, so the budget accounting
            # inside that caller still applies to it.
            Should -Invoke Invoke-GitHubConditionalGet -Times 1 -Exactly `
                -ParameterFilter { $Endpoint -match '/jobs' -and $null -eq $Cache }
        }

        It 'surfaces the rate-limit reading from the responses' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.RateLimit.Remaining | Should -Be 4987
            $result.RateLimit.Limit     | Should -Be 5000
        }

        It 'counts the per-run jobs calls against the reported budget' {
            # The jobs fan-out is the largest consumer on a busy tick - it is
            # never served from cache, so every run costs a request. A budget
            # that reports only the list calls understates consumption exactly
            # when an operator most needs the true number.
            $script:runnersPayload = ConvertTo-ApiPayload @'
{ "runners": [ { "id": 1, "name": "r1", "status": "online", "busy": true,
                "labels": [ { "name": "self-hosted" } ] } ] }
'@
            $script:inProgressRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 900 } ] }'

            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.RateLimit.Remaining | Should -Be 4000
        }
    }

    # ------------------------------------------------------------------
    Context 'queued jobs' {
    # ------------------------------------------------------------------

        BeforeEach {
            $script:queuedRunsPayload = ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 901 } ] }'
        }

        It 'reports a queued job whose labels this fleet can satisfy' {
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 7, "name": "lint", "status": "queued", "workflow_name": "CI",
             "labels": [ "self-hosted", "linux" ],
             "created_at": "2026-08-06T11:59:00Z",
             "html_url": "https://github.com/owner/repo/actions/runs/901/job/7" } ] }
'@
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.QueuedJobs.Count            | Should -Be 1
            $result.QueuedJobs[0].JobName       | Should -Be 'lint'
            $result.QueuedJobs[0].WorkflowName  | Should -Be 'CI'
            $result.QueuedJobs[0].Repository    | Should -Be 'owner/repo'
            $result.QueuedJobs[0].QueuedAt      |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 59, 0, [DateTimeKind]::Utc))
        }

        It 'matches fleet labels without regard to case' {
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 7, "name": "lint", "status": "queued",
             "labels": [ "Self-Hosted" ] } ] }
'@
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.QueuedJobs.Count | Should -Be 1
        }

        It 'ignores a queued job waiting on a GitHub-hosted image' {
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 8, "name": "windows-build", "status": "queued",
             "labels": [ "windows-latest" ] } ] }
'@
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.QueuedJobs.Count | Should -Be 0
        }

        It 'falls back to started_at when the job carries no created_at' {
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 7, "name": "lint", "status": "queued",
             "labels": [ "self-hosted" ],
             "started_at": "2026-08-06T11:50:00Z" } ] }
'@
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.QueuedJobs[0].QueuedAt |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 50, 0, [DateTimeKind]::Utc))
        }
    }

    # ------------------------------------------------------------------
    Context 'per-repository failure isolation' {
    # ------------------------------------------------------------------

        It 'records the failure instead of throwing' {
            Mock Invoke-GitHubConditionalGet { throw 'HTTP 401' }

            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Failures.Count         | Should -Be 1
            $result.Failures[0].Repository | Should -Be 'owner/repo'
            $result.Failures[0].Message    | Should -Match '401'
        }

        It 'still reports the repositories that did respond' {
            Mock Invoke-GitHubConditionalGet {
                if ($Endpoint -match 'owner/broken') { throw 'HTTP 403' }
                [PSCustomObject]@{
                    Value     = if ($Endpoint -match '/actions/runners') {
                                    $script:runnersPayload
                                } else {
                                    $script:queuedRunsPayload
                                }
                    RateLimit = $script:rateLimitPayload
                }
            }

            $result = Get-GitHubRunnerActivity -Token 't' `
                          -Repository @('owner/broken', 'owner/good')

            $result.Failures.Count | Should -Be 1
            $result.Runners.Count  | Should -Be 2
            $result.Runners[0].Repository | Should -Be 'owner/good'
        }
    }

    # ------------------------------------------------------------------
    Context 'a run whose jobs cannot be read' {
    # ------------------------------------------------------------------

        # The per-run jobs read is the most exposed call in the function: one
        # per open run, never served from cache, so the first to feel a rate
        # limit or a transient 5xx. Losing it costs the detail on that one run
        # - it must not cost the repository its board, because the runners
        # list that produces those rows has already succeeded by then.
        BeforeEach {
            $script:runnersPayload = ConvertTo-ApiPayload @'
{ "runners": [ { "id": 1, "name": "r1", "status": "online", "busy": true,
                "labels": [ { "name": "self-hosted" } ] } ] }
'@
            $script:inProgressRunsPayload =
                ConvertTo-ApiPayload '{ "workflow_runs": [ { "id": 900 }, { "id": 901 } ] }'
            $script:jobsPayload = ConvertTo-ApiPayload @'
{ "jobs": [ { "id": 5000, "name": "build", "status": "in_progress",
             "workflow_name": "CI", "runner_name": "r1" } ] }
'@

            # Run 900 fails, run 901 answers.
            Mock Invoke-GitHubConditionalGet {
                if ($Endpoint -match '/runs/900/jobs') { throw 'HTTP 502 Bad Gateway' }

                $value =
                    if     ($Endpoint -match '/actions/runners') { $script:runnersPayload }
                    elseif ($Endpoint -match 'status=in_progress') { $script:inProgressRunsPayload }
                    elseif ($Endpoint -match 'status=queued') { $script:queuedRunsPayload }
                    elseif ($Endpoint -match '/jobs') { $script:jobsPayload }
                    else { $null }

                [PSCustomObject]@{ Value = $value; RateLimit = $script:rateLimitPayload }
            }
        }

        It 'keeps the runner rows the runners call already produced' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners.Count   | Should -Be 1
            $result.Runners[0].Name | Should -Be 'r1'
            $result.Runners[0].Busy | Should -BeTrue
        }

        It 'opens the remaining runs instead of abandoning the repository' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners[0].JobName | Should -Be 'build'
        }

        It 'records the run it could not open' {
            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Failures.Count         | Should -Be 1
            $result.Failures[0].Repository | Should -Be 'owner/repo'
            $result.Failures[0].Message    | Should -Match '502'
            $result.Failures[0].Message    | Should -Match '900'
        }
    }

    # ------------------------------------------------------------------
    Context 'empty and malformed responses' {
    # ------------------------------------------------------------------

        It 'returns no rows for a repository with no registered runners' {
            $script:runnersPayload = ConvertTo-ApiPayload '{ "total_count": 0, "runners": [] }'

            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners.Count | Should -Be 0
            $result.Failures.Count | Should -Be 0
        }

        It 'tolerates a response body missing the runners key entirely' {
            $script:runnersPayload = ConvertTo-ApiPayload '{ "total_count": 0 }'

            $result = Get-GitHubRunnerActivity -Token 't' -Repository 'owner/repo'

            $result.Runners.Count  | Should -Be 0
            $result.Failures.Count | Should -Be 0
        }
    }
}
