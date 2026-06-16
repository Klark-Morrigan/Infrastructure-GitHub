# Infrastructure.GitHub

PowerShell module providing GitHub API utilities for infrastructure repos.

## Index

- [Overview](#overview)
- [Functions](#functions)
- [Usage](#usage)
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
| `Invoke-GitHubApi` | General-purpose GitHub REST API caller. Handles auth, `User-Agent`, and JSON serialization. Accepts `-Endpoint` (relative path) or `-Uri` (full URL). |
| `Get-GitHubAppToken` | Mints a short-lived installation access token for a GitHub App using RS256 JWT signing. Returns `Token` and `ExpiresAt`. |
| `Get-PendingDeployment` | Returns the oldest non-terminal deployment for a given repo and environment, or `$null` when none is pending. |
| `Set-DeploymentStatus` | Posts a status update (`in_progress`, `success`, `failure`, etc.) to an existing deployment. |
| `Invoke-RunnerTarballEnsure` | Ensures the `actions/runner` tarball for a given version is present in a local cache directory, downloading it if absent. |

## Usage

```powershell
Install-Module -Name Infrastructure.GitHub -MinimumVersion 0.1.0
Import-Module Infrastructure.GitHub
```

## Development

### Prerequisites

Clone `Common-PowerShell` at `.ci-common` once before running any local
test runner:

```powershell
git clone https://github.com/VitaliiAndreev/Common-PowerShell .ci-common
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

Three thin CI workflows delegate to Common's reusable workflows:

| Workflow | Trigger | Calls |
|---|---|---|
| `ci.yml` | PR / manual | `ci-powershell.yml` |
| `ci-docker-host.yml` | PR / manual | `ci-powershell-docker-host.yml` |
| `ci-docker-target.yml` | PR / manual | `ci-powershell-docker-target.yml` |
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
