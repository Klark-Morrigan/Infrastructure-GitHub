BeforeAll {
    function Invoke-GitHubApi { param($Token, $Endpoint, $Uri, $Method, $Body) }

    # ConvertTo-Array lives in Common.PowerShell; stub it here so this
    # unit test has no cross-module file-system dependency. The stub matches
    # the real function's contract: wraps the input in an array, returning
    # @() for $null.
    function ConvertTo-Array {
        [OutputType([object[]])]
        param([AllowNull()] $InputObject)
        if ($null -eq $InputObject) { return , @() }
        , @($InputObject)
    }

    . "$PSScriptRoot\..\Infrastructure.GitHub\Public\Get-PendingDeployment.ps1"
}

Describe 'Get-PendingDeployment' {

    # ------------------------------------------------------------------
    Context 'no deployments' {
    # ------------------------------------------------------------------

        It 'returns null when the deployments list is empty' {
            Mock Invoke-GitHubApi { @() }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    Context 'all deployments terminal' {
    # ------------------------------------------------------------------

        It 'returns null when every deployment has a terminal status' {
            # Note: PowerShell -like treats '?' as a single-char wildcard, so
            # '*/deployments?*' would incorrectly match '*/deployments/1/statuses'
            # (the '?' matching '/'). Check '*/statuses' first to route correctly.
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/deployments/1/statuses') {
                    return @([PSCustomObject]@{ state = 'success' })
                }
                if ($Endpoint -like '*/deployments/2/statuses') {
                    return @([PSCustomObject]@{ state = 'failure' })
                }
                return @(
                    [PSCustomObject]@{ id = 1 },
                    [PSCustomObject]@{ id = 2 }
                )
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result | Should -BeNullOrEmpty
        }

        It 'treats error as terminal' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    return @([PSCustomObject]@{ state = 'error' })
                }
                return @([PSCustomObject]@{ id = 1 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result | Should -BeNullOrEmpty
        }

        It 'treats inactive as terminal' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    return @([PSCustomObject]@{ state = 'inactive' })
                }
                return @([PSCustomObject]@{ id = 1 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result | Should -BeNullOrEmpty
        }

        It 'skips a deployment whose latest status is terminal even if an older status was non-terminal' {
            # GitHub returns statuses newest-first. Only [0] should be checked.
            # A bug that tests any or all statuses for terminality would pass
            # the single-status tests above but fail here.
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    return @(
                        [PSCustomObject]@{ state = 'success' },    # newest - terminal
                        [PSCustomObject]@{ state = 'in_progress' } # older  - non-terminal
                    )
                }
                return @([PSCustomObject]@{ id = 1 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    Context 'pending deployment exists' {
    # ------------------------------------------------------------------

        It 'returns a deployment with no statuses yet' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') { return @() }
                return @([PSCustomObject]@{ id = 10 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result.id | Should -Be 10
        }

        It 'returns a deployment whose latest status is in_progress' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    # newest-first: in_progress is non-terminal
                    return @([PSCustomObject]@{ state = 'in_progress' })
                }
                return @([PSCustomObject]@{ id = 20 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result.id | Should -Be 20
        }

        It 'returns a deployment whose latest status is queued' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    return @([PSCustomObject]@{ state = 'queued' })
                }
                return @([PSCustomObject]@{ id = 30 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result.id | Should -Be 30
        }

        It 'returns a deployment whose latest status is pending' {
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') {
                    return @([PSCustomObject]@{ state = 'pending' })
                }
                return @([PSCustomObject]@{ id = 40 })
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result.id | Should -Be 40
        }

        It 'returns the oldest pending deployment when multiple deployments exist' {
            # id=1 is terminal (success), id=2 and id=3 are pending (no statuses).
            # Sorted by id ascending, id=2 is returned first.
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/deployments/1/statuses') {
                    return @([PSCustomObject]@{ state = 'success' })
                }
                if ($Endpoint -like '*/statuses') {
                    # id=2 and id=3 have no statuses yet
                    return @()
                }
                # Deployments list - intentionally out-of-order to verify sorting
                return @(
                    [PSCustomObject]@{ id = 3 },
                    [PSCustomObject]@{ id = 1 },
                    [PSCustomObject]@{ id = 2 }
                )
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $result.id | Should -Be 2
        }
    }

    # ------------------------------------------------------------------
    Context 'API calls' {
    # ------------------------------------------------------------------

        It 'requests the correct environment filter' {
            Mock Invoke-GitHubApi { @() }

            Get-PendingDeployment `
                -Token 'tok' -Owner 'myorg' -Repo 'myrepo' -Environment 'staging'

            Should -Invoke Invoke-GitHubApi -ParameterFilter {
                $Endpoint -eq 'repos/myorg/myrepo/deployments?environment=staging'
            }
        }

        It 'passes the token to all API calls' {
            $script:_tokens = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-GitHubApi {
                $script:_tokens.Add($Token)
                if ($Endpoint -like '*/statuses') { return @() }
                return @([PSCustomObject]@{ id = 1 })
            }

            Get-PendingDeployment `
                -Token 'bearer_tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation'

            $script:_tokens | Should -Not -Contain $null
            $script:_tokens | ForEach-Object { $_ | Should -Be 'bearer_tok' }
        }
    }

    # ------------------------------------------------------------------
    Context 'CreatedSince cutoff' {
    # ------------------------------------------------------------------
        # GitHub never deletes deployments, so the list endpoint keeps
        # returning a page of historical, terminal deployments. -CreatedSince
        # skips the per-deployment status fetch for stale ones; that single
        # change is what stops the N+1 fan-out from exhausting the rate limit.

        It 'does not fetch statuses for a deployment created before the cutoff' {
            $recentIso = [DateTimeOffset]::UtcNow.ToString('o')
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') { return @() }
                return @(
                    [PSCustomObject]@{ id = 1; created_at = '2020-01-01T00:00:00Z' },
                    [PSCustomObject]@{ id = 2; created_at = $recentIso }
                )
            }

            Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation' `
                -CreatedSince ([DateTime]::UtcNow.AddHours(-1))

            # Only the recent deployment (id=2) is worth a status call.
            Should -Invoke Invoke-GitHubApi -Times 0 -ParameterFilter {
                $Endpoint -like '*/deployments/1/statuses'
            }
            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $Endpoint -like '*/deployments/2/statuses'
            }
        }

        It 'returns the recent pending deployment and skips the stale ones' {
            $recentIso = [DateTimeOffset]::UtcNow.ToString('o')
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') { return @() }   # id=2 is pending
                return @(
                    [PSCustomObject]@{ id = 1; created_at = '2020-01-01T00:00:00Z' },
                    [PSCustomObject]@{ id = 2; created_at = $recentIso }
                )
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation' `
                -CreatedSince ([DateTime]::UtcNow.AddHours(-1))

            $result.id | Should -Be 2
        }

        It 'returns null when every in-window deployment is terminal even if a stale one looks pending' {
            $recentIso = [DateTimeOffset]::UtcNow.ToString('o')
            Mock Invoke-GitHubApi {
                # id=2 (recent) is terminal; id=1 (stale) would be pending but
                # must never be reached because the cutoff skips it.
                if ($Endpoint -like '*/deployments/2/statuses') {
                    return @([PSCustomObject]@{ state = 'success' })
                }
                if ($Endpoint -like '*/statuses') { return @() }
                return @(
                    [PSCustomObject]@{ id = 1; created_at = '2020-01-01T00:00:00Z' },
                    [PSCustomObject]@{ id = 2; created_at = $recentIso }
                )
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation' `
                -CreatedSince ([DateTime]::UtcNow.AddHours(-1))

            $result | Should -BeNullOrEmpty
        }

        It 'still checks a deployment whose created_at is missing (never skipped on absent timestamp)' {
            # Guarded property access must treat an absent created_at as
            # in-window, so a deployment is never skipped just because the
            # field was missing from the payload.
            Mock Invoke-GitHubApi {
                if ($Endpoint -like '*/statuses') { return @() }
                return @([PSCustomObject]@{ id = 5 })   # no created_at
            }

            $result = Get-PendingDeployment `
                -Token 'tok' -Owner 'org' -Repo 'repo' -Environment 'e2e-workstation' `
                -CreatedSince ([DateTime]::UtcNow.AddHours(-1))

            $result.id | Should -Be 5
        }
    }
}
