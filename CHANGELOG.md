# Changelog

All notable changes to `Infrastructure.GitHub` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 0.2.0 live in the git
history and the tag list.

## [Unreleased]

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

[Unreleased]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/1.1.0...HEAD
[1.1.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/0.2.0...1.0.0
[0.2.0]: https://github.com/Klark-Morrigan/Infrastructure-GitHub/compare/0.1.0...0.2.0
