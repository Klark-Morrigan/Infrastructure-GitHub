BeforeAll {
    # Faithful-but-sleepless stand-in for Common.PowerShell's Invoke-WithRetry.
    # It replicates the documented contract this function depends on - run the
    # block, on failure consult RetryStrategy.ShouldRetry, loop up to
    # MaxAttempts, otherwise propagate - without the real backoff sleeps.
    # Retry *mechanics* are covered by Common.PowerShell's own tests; here we
    # exercise the policy selection and the 5xx re-raise this function owns.
    function Invoke-WithRetry {
        param(
            [scriptblock] $ScriptBlock,
            [hashtable[]] $RetryStrategy,
            [hashtable]   $BackoffStrategy,
            [int]         $MaxAttempts = 3,
            [string]      $OperationName
        )
        $script:CapturedStrategies    = $RetryStrategy
        $script:CapturedOperationName = $OperationName
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try { return & $ScriptBlock }
            catch {
                $err     = $_
                $matched = $RetryStrategy |
                    Where-Object { & $_.ShouldRetry $err } |
                    Select-Object -First 1
                if (-not $matched -or $attempt -ge $MaxAttempts) { throw }
            }
        }
    }

    # Stand-ins for the two strategy factories. Their classification logic is
    # tested where it lives (Common.PowerShell's suite, and this repo's
    # New-GitHubWriteRetryStrategy.Tests.ps1); what matters here is only
    # WHICH of them Invoke-GitHubApi hands to the retry loop, so each is
    # reduced to a fixed verdict that makes the selection observable.
    function New-TransientNetworkRetryStrategy {
        @{ Name = 'TransientNetwork'; ShouldRetry = { param($e) $true } }
    }
    function New-GitHubWriteRetryStrategy {
        @{ Name = 'GitHubConnectFailure'; ShouldRetry = { param($e) $false } }
    }

    . "$PSScriptRoot\..\Infrastructure.GitHub\Private\Test-GitHubIdempotentMethod.ps1"
    . "$PSScriptRoot\..\Infrastructure.GitHub\Public\Invoke-GitHubApi.ps1"
}

Describe 'Invoke-GitHubApi' {

    BeforeAll {
        Mock Invoke-RestMethod { [PSCustomObject]@{} }
    }

    # ------------------------------------------------------------------
    Context 'request headers' {
    # ------------------------------------------------------------------

        It 'sets Authorization as Bearer token' {
            Invoke-GitHubApi -Token 'tok123' -Uri 'https://api.github.com/test'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Headers['Authorization'] -eq 'Bearer tok123'
            }
        }

        It 'sets User-Agent to Infrastructure' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Headers['User-Agent'] -eq 'Infrastructure'
            }
        }

        It 'sets Content-Type to application/json' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Headers['Content-Type'] -eq 'application/json'
            }
        }

        It 'passes -Uri unchanged to Invoke-RestMethod' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/repos/owner/repo/actions/runners'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/owner/repo/actions/runners'
            }
        }

        It 'expands -Endpoint to the full GitHub API base URL' {
            Invoke-GitHubApi -Token 't' -Endpoint 'repos/owner/repo/actions/runners'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/owner/repo/actions/runners'
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'parameter validation' {
    # ------------------------------------------------------------------

        It 'throws when both -Endpoint and -Uri are supplied' {
            {
                Invoke-GitHubApi -Token 't' `
                    -Endpoint 'repos/o/r' `
                    -Uri      'https://api.github.com/repos/o/r'
            } | Should -Throw
        }

        It 'throws when neither -Endpoint nor -Uri is supplied' {
            { Invoke-GitHubApi -Token 't' } | Should -Throw
        }
    }

    # ------------------------------------------------------------------
    Context 'method' {
    # ------------------------------------------------------------------

        It 'defaults to GET' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Method -eq 'Get'
            }
        }

        It 'passes the specified method' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Post'
            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Method -eq 'Post'
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'body' {
    # ------------------------------------------------------------------

        It 'serializes a hashtable body to JSON' {
            $script:_body = $null
            Mock Invoke-RestMethod { $script:_body = $Body }

            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                -Method 'Post' -Body @{ state = 'success' }

            ($script:_body | ConvertFrom-Json).state | Should -Be 'success'
        }

        It 'omits Body when not specified' {
            $script:_params = $null
            Mock Invoke-RestMethod { $script:_params = $PSBoundParameters }

            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $script:_params.ContainsKey('Body') | Should -BeFalse
        }
    }

    # ------------------------------------------------------------------
    Context 'extra request headers' {
    # ------------------------------------------------------------------

        It 'merges the supplied headers alongside the defaults' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                -Header @{ 'If-None-Match' = 'W/"abc"' }

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Headers['If-None-Match'] -eq 'W/"abc"' -and
                $Headers['Authorization'] -eq 'Bearer t'
            }
        }

        It 'lets a supplied header override a default of the same name' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                -Header @{ 'Content-Type' = 'text/plain' }

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $Headers['Content-Type'] -eq 'text/plain'
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'response detail' {
    # ------------------------------------------------------------------
    # The conditional-request surface: a caller cannot act on a 304 without
    # reading back both the headers (for the ETag) and the status code.

        It 'asks Invoke-RestMethod for the headers and the status code' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                -IncludeResponseDetail

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $ResponseHeadersVariable -and $StatusCodeVariable
            }
        }

        It 'disables the built-in error check so a 304 is observable' {
            # 304 Not Modified - the status this exists to observe - is a
            # non-success code and would otherwise throw before the caller
            # could see it.
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                -IncludeResponseDetail

            Should -Invoke Invoke-RestMethod -ParameterFilter {
                $SkipHttpErrorCheck -eq $true
            }
        }

        It 'leaves the built-in error check on for an ordinary call' {
            $script:_params = $null
            Mock Invoke-RestMethod { $script:_params = $PSBoundParameters }

            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $script:_params.ContainsKey('SkipHttpErrorCheck') | Should -BeFalse
        }

        It 'wraps the body in a detail object' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ id = 42 } }

            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                          -IncludeResponseDetail

            $result.Content.id | Should -Be 42
        }

        It 'reports null headers and status when the call produced none' {
            # A mocked or header-less response must not trip StrictMode in the
            # caller reading the detail object back.
            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                          -IncludeResponseDetail

            $result.Headers    | Should -BeNullOrEmpty
            $result.StatusCode | Should -BeNullOrEmpty
        }

        It 'returns the bare body when the detail is not requested' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ id = 42 } }

            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $result.id | Should -Be 42
            $result.PSObject.Properties['Content'] | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    Context 'retry policy selection' {
    # ------------------------------------------------------------------
    # A read may be replayed freely; a write may only be replayed when the
    # request provably never reached GitHub, or a retry double-executes it.

        It 'gives a GET the full transient-network policy' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $script:CapturedStrategies.Name | Should -Be 'TransientNetwork'
        }

        It 'gives a HEAD the full transient-network policy' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Head'

            $script:CapturedStrategies.Name | Should -Be 'TransientNetwork'
        }

        It 'matches the method case-insensitively' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'get'

            $script:CapturedStrategies.Name | Should -Be 'TransientNetwork'
        }

        It 'restricts a POST to the connect-failure policy' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Post'

            $script:CapturedStrategies.Name | Should -Be 'GitHubConnectFailure'
        }

        It 'restricts a DELETE to the connect-failure policy' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Delete'

            $script:CapturedStrategies.Name | Should -Be 'GitHubConnectFailure'
        }

        It 'labels the operation with the method and URI' {
            Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Post'

            $script:CapturedOperationName |
                Should -Be 'GitHub API Post https://api.github.com/test'
        }

        It 'keeps the token out of the operation label' {
            # The label reaches operator-visible logs through the per-attempt
            # retry warning.
            Invoke-GitHubApi -Token 'ghp_secret' -Uri 'https://api.github.com/test'

            $script:CapturedOperationName | Should -Not -Match 'ghp_secret'
        }

        It 'retries a read that fails transiently' {
            $script:_calls = 0
            Mock Invoke-RestMethod {
                $script:_calls++
                if ($script:_calls -lt 3) { throw 'boom' }
                [PSCustomObject]@{ id = 42 }
            }

            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $script:_calls | Should -Be 3
            $result.id     | Should -Be 42
        }

        It 'does not replay a write the policy declines to retry' {
            $script:_calls = 0
            Mock Invoke-RestMethod { $script:_calls++; throw 'boom' }

            {
                Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' -Method 'Post'
            } | Should -Throw

            $script:_calls | Should -Be 1
        }
    }

    # ------------------------------------------------------------------
    Context 'return value' {
    # ------------------------------------------------------------------

        It 'returns the Invoke-RestMethod response' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ id = 42 } }

            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $result.id | Should -Be 42
        }
    }
}

# ----------------------------------------------------------------------
# Separate Describe with no Mock in scope. Harvesting Invoke-RestMethod's
# -*Variable outputs is the one behaviour a Pester mock cannot stand in for:
# the mock body executes inside Pester's own wrapper, so a `Set-Variable
# -Scope 1` in it lands there rather than in Invoke-GitHubApi's frame, and
# the harvest under test never happens. A plain function shadowing the
# cmdlet runs in the real call frame, which is what makes it meaningful.
#
# This is worth its own harness rather than trusting the parameter-passing
# tests above, because the plumbing between Invoke-RestMethod and the
# returned detail object is exactly where a silent drop would hide.
# ----------------------------------------------------------------------
Describe 'Invoke-GitHubApi response detail harvesting' {

    BeforeAll {
        # Deliberately NOT [CmdletBinding()]: the shadow has to accept the
        # ErrorAction the caller splats in as an ordinary parameter, and an
        # advanced function reserves that name.
        #
        # Suppressed inline (not fleet-wide) so the rule keeps guarding
        # production code against clobbering a built-in.
        function Invoke-RestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Intentional in-scope test double for Invoke-RestMethod.')]
            param(
                $Uri, $Method, $Headers, $Body, $ErrorAction,
                [string] $ResponseHeadersVariable,
                [string] $StatusCodeVariable,
                [switch] $SkipHttpErrorCheck
            )
            if ($ResponseHeadersVariable) {
                Set-Variable -Name $ResponseHeadersVariable -Scope 1 `
                    -Value @{ 'ETag' = @('W/"abc"') }
            }
            if ($StatusCodeVariable) {
                Set-Variable -Name $StatusCodeVariable -Scope 1 -Value 304
            }
            [PSCustomObject]@{ id = 42 }
        }
    }

    It 'carries the response headers through to the detail object' {
        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $result.Headers['ETag'] | Should -Be @('W/"abc"')
    }

    It 'carries the status code through to the detail object' {
        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $result.StatusCode | Should -Be 304
    }

    It 'carries the body alongside them' {
        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $result.Content.id | Should -Be 42
    }
}

# ----------------------------------------------------------------------
# -IncludeResponseDetail turns SkipHttpErrorCheck on, so a 5xx arrives as a
# return value rather than an exception and would otherwise never reach the
# retry classifier - the asymmetry this Describe pins down. Needs the same
# shadow-function harness as the block above, because the behaviour under
# test is driven entirely by the harvested status code, which a Pester mock
# cannot write into the caller's frame.
# ----------------------------------------------------------------------
Describe 'Invoke-GitHubApi response detail retry' {

    BeforeAll {
        # Serves one status per call from a queue, so a test can express
        # "502 then 200" and assert the retry actually happened.
        function Invoke-RestMethod {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSAvoidOverwritingBuiltInCmdlets', '',
                Justification = 'Intentional in-scope test double for Invoke-RestMethod.')]
            param(
                $Uri, $Method, $Headers, $Body, $ErrorAction,
                [string] $ResponseHeadersVariable,
                [string] $StatusCodeVariable,
                [switch] $SkipHttpErrorCheck
            )
            $script:DetailCalls++
            $status = if ($script:StatusQueue.Count -gt 0) {
                $script:StatusQueue.Dequeue()
            } else {
                $script:LastStatus
            }
            $script:LastStatus = $status
            if ($StatusCodeVariable) {
                Set-Variable -Name $StatusCodeVariable -Scope 1 -Value $status
            }
            [PSCustomObject]@{ id = 42 }
        }
    }

    BeforeEach {
        $script:DetailCalls = 0
        $script:LastStatus  = 200
        $script:StatusQueue = [System.Collections.Queue]::new()
    }

    It 'retries a 5xx observed on a read and returns the eventual success' {
        $script:StatusQueue.Enqueue(502)
        $script:StatusQueue.Enqueue(200)

        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $script:DetailCalls   | Should -Be 2
        $result.StatusCode    | Should -Be 200
        $result.Content.id    | Should -Be 42
    }

    It 'returns the final response rather than throwing when the retries run out' {
        # The no-throw contract of -IncludeResponseDetail survives a 5xx that
        # never recovers: the caller still owns status handling.
        $script:StatusQueue.Enqueue(503)

        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $result.StatusCode | Should -Be 503
        $result.Content.id | Should -Be 42
    }

    It 'does not retry a 5xx on a write' {
        $script:StatusQueue.Enqueue(503)

        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -Method 'Post' -IncludeResponseDetail

        $script:DetailCalls | Should -Be 1
        $result.StatusCode  | Should -Be 503
    }

    It 'does not retry a 304' {
        $script:StatusQueue.Enqueue(304)

        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $script:DetailCalls | Should -Be 1
        $result.StatusCode  | Should -Be 304
    }

    It 'does not retry a 4xx' {
        $script:StatusQueue.Enqueue(404)

        $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test' `
                      -IncludeResponseDetail

        $script:DetailCalls | Should -Be 1
        $result.StatusCode  | Should -Be 404
    }
}
