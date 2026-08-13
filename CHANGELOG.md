# Changelog

All notable changes to `Infrastructure.GitHub` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 0.2.0 live in the git
history and the tag list.

## [Unreleased]

## [1.2.1] - 2026-08-13

### Fixed
- `Invoke-GitHubApi` now retries transient failures instead of surfacing them
  on the first attempt. A DNS hiccup on the host resolver - which arrives as
  `No such host is known. (api.github.com:443)` and killed a whole E2E run
  where the caller's own poll loop only ever retried the *state* it was
  waiting on - is now ridden out.

  The policy is chosen by method, because the two cases are not equally safe
  to replay:
  - Reads (`GET`/`HEAD`/`OPTIONS`) use Common.PowerShell's
    `New-TransientNetworkRetryStrategy`: DNS failures, dropped connections,
    timeouts and 5xx responses.
  - Writes use the new private `New-GitHubWriteRetryStrategy`, which matches
    only failures that provably never reached GitHub (name resolution and
    connect-establishment socket errors). Timeouts and lost 5xx responses are
    treated as permanent there: GitHub may already have minted the
    registration token or removed the runner, and a replay would double-execute.

  4xx stays permanent under both, so a bad token or a mistyped repo still
  fails fast.

### Changed
- `-IncludeResponseDetail` no longer sits outside the retry policy. Because
  `SkipHttpErrorCheck` turns a 5xx into a return value rather than an
  exception, that path silently skipped the retry a plain call received - so
  a transient 502 on the conditional-GET polling path failed hard while the
  same 502 on an ordinary call was retried. Both paths now share one policy.
  The switch's contract is unchanged: it still never throws on a bad status,
  and the caller still owns all status handling.
- `RequiredModules` now declares `Common.PowerShell` (floor 8.1.0), which
  supplies the retry primitives.

## [1.2.0] - 2026-08-06

### Added
- `Get-GitHubRunnerActivity` - returns one row per registered self-hosted
  runner joined to the job it is executing (workflow, job, current step,
  elapsed), plus the jobs queued against that fleet's labels. The GitHub API
  splits this across the runners endpoint (which knows `busy` but not what
  with) and the per-run jobs endpoint (which knows the work but is not
  addressable by runner); the function performs the join so callers do not
  have to. Backs the live runner dashboard in Infrastructure-GitHubRunners.
  Failures degrade the report rather than empty it: an unpollable repository
  and an individual run whose jobs cannot be read both land in `.Failures`,
  and in the latter case the repository still reports every runner row. The
  `.RateLimit` reading accounts for every request made, the uncached per-run
  jobs calls included - on a busy tick those outnumber the list calls.
- `Invoke-GitHubApi` gains `-Header` and `-IncludeResponseDetail`. Together
  they enable conditional (ETag) requests, which a polling caller needs to
  stay inside the hourly rate limit: GitHub does not charge a 304 Not
  Modified, but observing one requires sending a request header and reading
  back both the response headers and a non-success status code. Both are
  opt-in; callers that omit them are unaffected.

### Notes
- `-IncludeResponseDetail` returns `.Content` / `.Headers` / `.StatusCode`
  rather than publishing the latter two through `-*Variable` out-parameters
  mirroring `Invoke-RestMethod`'s own. That shape cannot work from inside a
  module: a function running in module session state cannot write a variable
  into the scope of the script that imported it, and both `Set-Variable
  -Scope 1` and `$PSCmdlet.SessionState.PSVariable.Set` fail silently there.
- `-IncludeResponseDetail` also disables `Invoke-RestMethod`'s built-in error
  check, because 304 would otherwise throw before the caller could see it. The
  caller then owns all status handling, 4xx and 5xx included.

## [1.1.0] - 2026-06-17

### Added
- `Get-PendingDeployment` gains an optional `-CreatedSince` cutoff. Deployments
  created before the cutoff are skipped without a status API call. Defaults to
  `MinValue` (check every deployment), so existing callers are unaffected.

### Fixed
- The polling agent no longer exhausts the GitHub API rate limit. Because GitHub
  never deletes deployments, `Get-PendingDeployment` was fetching statuses for a
  full page of historical, terminal deployments on every tick - an N+1 fan-out
  (~31 calls/poll) that drained the hourly budget and crashed the agent with
  `403 (rate limit exceeded)`. Callers now pass `-CreatedSince` to collapse a
  quiet poll to a single list call.

## [1.0.0] - 2026-06-17

### Changed
- Major version bump; no functional changes (version realignment).

## [0.2.0] - 2026-05-08

### Added
- Baseline changelog. This section pins the current released surface so the
  release pipeline's changelog gate and GitHub Release have notes to anchor
  on; earlier history remains in the git log and tag list.

### Notes
- Public surface: `Get-GitHubAppToken`, `Get-PendingDeployment`,
  `Invoke-GitHubApi`, `Invoke-RunnerTarballDeploy`,
  `Invoke-RunnerTarballEnsure`, `Set-DeploymentStatus` - GitHub App token
  auth, Actions deployment/API helpers, and self-hosted runner tarball
  deploy/ensure used by the infrastructure repos.

[Unreleased]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/1.2.0...HEAD
[1.2.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/0.2.0...1.0.0
[0.2.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/0.1.0...0.2.0
