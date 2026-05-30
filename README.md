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

This module is extracted from `PowerShell.Common` to give GitHub-specific
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

Clone `PowerShell-Common` at `.ci-common` once before running any local
test runner:

```powershell
git clone https://github.com/VitaliiAndreev/PowerShell-Common .ci-common
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

### CI

Three thin CI workflows delegate to Common's reusable workflows:

| Workflow | Trigger | Calls |
|---|---|---|
| `ci.yml` | PR / manual | `ci-powershell.yml` |
| `ci-docker-host.yml` | PR / manual | `ci-powershell-docker-host.yml` |
| `ci-docker-target.yml` | PR / manual | `ci-powershell-docker-target.yml` |

### Release

Pushing a change to `Infrastructure.GitHub/Infrastructure.GitHub.psd1` on
`master` with a new `ModuleVersion` triggers `release.yml`, which:

1. Checks the version is new.
2. Runs all three CI workflows.
3. Tags the commit via Common's `tag.yml`.
4. Publishes to PSGallery via Common's `publish.yml`.
