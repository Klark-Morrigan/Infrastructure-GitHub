# Infrastructure.GitHub

PowerShell module providing GitHub API utilities for infrastructure repos.

## Index

- [Overview](#overview)
- [Functions](#functions)
- [Usage](#usage)
  - [Retry behaviour](#retry-behaviour)
  - [Polling without exhausting the rate limit](#polling-without-exhausting-the-rate-limit)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Running Tests](#running-tests)
  - [CI](#ci)
  - [Release](#release)

## Overview

This module is extracted from `Common.PowerShell` to give GitHub-specific
functions their own cohesion boundary. It is published to PSGallery and
consumed by other repos.

## Functions

| Function | Description |
|---|---|
| `Invoke-GitHubApi` | General-purpose GitHub REST API caller. Handles auth, `User-Agent`, JSON serialization, and [transient-failure retry](#retry-behaviour). Accepts `-Endpoint` (relative path) or `-Uri` (full URL). `-IncludeResponseDetail` returns headers and status code for conditional (ETag) requests. |
| `Get-GitHubAppToken` | Mints a short-lived installation access token for a GitHub App using RS256 JWT signing. Returns `Token` and `ExpiresAt`. |
| `Get-GitHubRunnerActivity` | One row per registered self-hosted runner, joined to the job it is executing (workflow, job, current step, elapsed), plus the jobs queued against that fleet. Built for repeated polling. |
| `Get-PendingDeployment` | Returns the oldest non-terminal deployment for a given repo and environment, or `$null` when none is pending. |
| `Set-DeploymentStatus` | Posts a status update (`in_progress`, `success`, `failure`, etc.) to an existing deployment. |
| `Invoke-RunnerTarballEnsure` | Ensures the `actions/runner` tarball for a given version is present in a local cache directory, downloading it if absent. |
| `Invoke-RunnerTarballDeploy` | Ensures the `actions/runner` tarball is present in the runner user's cache directory on a remote Linux host, fetching it with `curl` over SSH and purging stale versions first. The Linux-side complement to `Invoke-RunnerTarballEnsure`. |

Helpers under `Infrastructure.GitHub\Private\` (response parsing under
`StrictMode`, header reads, the conditional-GET wrapper, the retry-policy
pair) are implementation detail: they follow the same one-function-per-file
layout but are absent from both export lists, so adding one is not a public
contract change.

## Usage

```powershell
Install-Module -Name Infrastructure.GitHub -MinimumVersion 0.1.0
Import-Module Infrastructure.GitHub
```

`Common.PowerShell` (>= 8.1.0) is declared in `RequiredModules` and comes down
with the install - `Invoke-GitHubApi` uses its retry primitives. Nothing to
import by hand.

### Retry behaviour

`Invoke-GitHubApi` retries transient failures on its own, so callers do not
wrap it. The policy is chosen by HTTP method, because replaying a read and
replaying a write are not equally safe:

| Method | Policy | Retried |
|---|---|---|
| `GET` / `HEAD` / `OPTIONS` | `Common.PowerShell`'s `New-TransientNetworkRetryStrategy` | DNS failures, dropped connections, timeouts, 5xx |
| everything else | private `New-GitHubWriteRetryStrategy` | Only failures that provably never reached GitHub - name resolution and connect-establishment socket errors |

A write is held to the narrower bar because a timeout or a lost 5xx can mean
GitHub already acted on the request; replaying one would mint a second
registration token or remove a runner twice. `4xx` is permanent under both,
so a bad token or a mistyped repo fails fast rather than sleeping through the
attempt budget.

Attempts and pacing come from `Invoke-WithRetry`'s defaults: three attempts,
exponential backoff. A caller that needs a longer horizon - waiting for a
runner to come online, say - should keep its own poll loop; that loop is
waiting on *state*, which is a separate concern from surviving a flaky hop.

`-IncludeResponseDetail` follows the same policy. Its `SkipHttpErrorCheck`
means a 5xx arrives as a return value rather than an exception, so the
function re-raises it internally to keep both paths on one policy, then
returns the final response once the attempts are spent. The switch still
never throws on a bad status: the caller owns all status handling.

### Polling without exhausting the rate limit

`Get-GitHubRunnerActivity` is designed to be called on a loop. Hand it the
same `-Cache` hashtable every tick: it stores each list response's ETag and
re-sends it as `If-None-Match`, so an unchanged runner list or queue answers
`304 Not Modified` - which GitHub does not charge against the hourly budget.
The remaining budget comes back in `.RateLimit` on every call.

```powershell
$cache = @{}
while ($true) {
    $activity = Get-GitHubRunnerActivity -Token $token `
                    -Repository 'Klark-Morrigan/Common-Automation' -Cache $cache

    $activity.Runners | Format-Table Name, Status, Busy, WorkflowName, JobName, CurrentStep
    "queued: $($activity.QueuedJobs.Count)   budget: $($activity.RateLimit.Remaining)"

    Start-Sleep -Seconds 10
}
```

A repository that cannot be polled (auth, rate limit, network) lands in
`.Failures` instead of throwing, so one bad repo does not blank the rest.

## Development

### Prerequisites

Clone `Common-PowerShell` at `.ci-common` once before running any local
test runner:

```powershell
git clone https://github.com/Klark-Morrigan/Common-PowerShell .ci-common
```

### Running Tests

```powershell
# Unit tests
.\scripts\Run-Tests.ps1

# Integration tests (Docker host)
.\scripts\Run-IntegrationTests-InDocker.ps1

# Integration tests (Docker SSH target)
.\scripts\Run-IntegrationTests-AgainstDockerTarget.ps1
```

The local CI checks run via three sibling shims (Git Bash and Docker). Each shims
to `Common-Automation`'s engine - pointed at this repo through
`COMMON_AUTOMATION_TARGET_REPO` - so that repo must be a sibling checkout
(`..\Common-Automation`), and local cannot drift from CI:

```bash
# PRIMARY local entry: full lint suite AND bats tests
# (local equivalent of ci-yaml.yml + ci-bash.yml).
scripts/run-ci-yaml-and-bash.sh

# Or run a single half:
scripts/run-lint-yaml-and-bash.sh   # LINT half (shellcheck/actionlint/action-validator/yamllint/ansible-lint)
scripts/run-tests-bash.sh           # bats TEST half
```

### CI

Thin local CI workflows delegate to the shared reusable workflows:

| Workflow | Trigger | Calls |
|---|---|---|
| `ci-powershell.yml` | PR / manual | Common-PowerShell `ci-powershell.yml` (unit job, then a Docker integration job gated behind it) |
| `ci-yaml.yml` | PR / manual | Common-Automation `ci-yaml.yml` (actionlint, action-validator, yamllint, ansible-lint) |
| `ci-bash.yml` | PR / manual | Common-Automation `ci-bash.yml` (shellcheck on `scripts\` shims, check-sh-executable, bats) |

### Release

Releases are CHANGELOG.md-driven. To ship a version: promote the
[`[Unreleased]`](CHANGELOG.md) section in [CHANGELOG.md](CHANGELOG.md) to the
new version + date, bump `ModuleVersion` in
`Infrastructure.GitHub/Infrastructure.GitHub.psd1` to match, and merge to
`master`. The manifest change triggers `release.yml`, which:

1. Checks the version is new (`check-version-is-new`).
2. Asserts the manifest version matches the top CHANGELOG.md section
   (`assert-changelog-version`) - the release fails here if notes are
   missing, so they can never lag the release.
3. Runs all three CI workflows.
4. Tags, publishes to PSGallery, and cuts a GitHub Release (with notes
   from CHANGELOG.md) via Common's `release-tail.yml`.
