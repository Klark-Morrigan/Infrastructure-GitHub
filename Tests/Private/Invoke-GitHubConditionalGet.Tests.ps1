BeforeAll {
    Set-StrictMode -Version Latest

    $modulePath = "$PSScriptRoot\..\..\Infrastructure.GitHub"
    . "$modulePath\Private\Get-HttpHeaderValue.ps1"
    . "$modulePath\Private\New-GitHubRequestHeader.ps1"
    . "$modulePath\Private\Invoke-GitHubConditionalGet.ps1"

    # Stands in for Invoke-GitHubApi under -IncludeResponseDetail. A function
    # rather than a Pester mock so the stub can also record the request header
    # it was handed, which several assertions below inspect.
    function Invoke-GitHubApi {
        [CmdletBinding()]
        param(
            [string] $Token,
            [string] $Endpoint,
            [string] $Uri,
            [string] $Method = 'Get',
            [hashtable] $Body,
            [hashtable] $Header,
            [switch] $IncludeResponseDetail
        )
        $script:stubRequestHeader = $Header
        [PSCustomObject]@{
            Content    = $script:stubBody
            Headers    = $script:stubHeaders
            StatusCode = $script:stubStatus
        }
    }
}

Describe 'Invoke-GitHubConditionalGet' {

    BeforeEach {
        $script:stubStatus  = 200
        $script:stubBody    = [PSCustomObject]@{ runners = @('a') }
        $script:stubHeaders = @{
            'ETag'                  = @('W/"abc123"')
            'X-RateLimit-Remaining' = @('4990')
            'X-RateLimit-Limit'     = @('5000')
            'X-RateLimit-Reset'     = @('1786000000')
        }
        $script:stubRequestHeader = $null
    }

    # ------------------------------------------------------------------
    Context 'first call for an endpoint' {
    # ------------------------------------------------------------------

        It 'sends no If-None-Match when the cache holds nothing for it' {
            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache @{}

            $script:stubRequestHeader.ContainsKey('If-None-Match') | Should -BeFalse
        }

        It 'returns the response body' {
            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache @{}

            $result.Value.runners | Should -Be @('a')
        }

        It 'stores the ETag and payload against the endpoint' {
            $cache = @{}

            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $cache['repos/o/r'].ETag         | Should -Be 'W/"abc123"'
            $cache['repos/o/r'].Payload.runners | Should -Be @('a')
        }

        It 'caches nothing when the response carries no ETag' {
            $script:stubHeaders = @{ 'X-RateLimit-Remaining' = @('4990') }
            $cache = @{}

            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $cache.Count | Should -Be 0
        }

        It 'works without a cache at all' {
            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r'

            $result.Value.runners | Should -Be @('a')
        }
    }

    # ------------------------------------------------------------------
    Context 'revalidating a cached endpoint' {
    # ------------------------------------------------------------------

        It 'sends the cached ETag as If-None-Match' {
            $cache = @{ 'repos/o/r' = [PSCustomObject]@{ ETag = 'W/"old"'; Payload = 'cached' } }

            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $script:stubRequestHeader['If-None-Match'] | Should -Be 'W/"old"'
        }

        It 'replays the cached payload on 304' {
            $script:stubStatus = 304
            $script:stubBody   = $null
            $cache = @{ 'repos/o/r' = [PSCustomObject]@{ ETag = 'W/"old"'; Payload = 'cached' } }

            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $result.Value | Should -Be 'cached'
        }

        It 'leaves the cache entry intact on 304' {
            $script:stubStatus = 304
            $cache = @{ 'repos/o/r' = [PSCustomObject]@{ ETag = 'W/"old"'; Payload = 'cached' } }

            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $cache['repos/o/r'].ETag | Should -Be 'W/"old"'
        }

        It 'replaces the cache entry on a fresh 200' {
            $cache = @{ 'repos/o/r' = [PSCustomObject]@{ ETag = 'W/"old"'; Payload = 'cached' } }

            $null = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $cache['repos/o/r'].ETag | Should -Be 'W/"abc123"'
        }

        It 'keys the cache by endpoint so query strings cache independently' {
            $cache = @{}

            $null = Invoke-GitHubConditionalGet -Token 't' `
                        -Endpoint 'repos/o/r/actions/runs?status=queued' -Cache $cache
            $null = Invoke-GitHubConditionalGet -Token 't' `
                        -Endpoint 'repos/o/r/actions/runs?status=in_progress' -Cache $cache

            $cache.Count | Should -Be 2
        }
    }

    # ------------------------------------------------------------------
    Context 'rate limit' {
    # ------------------------------------------------------------------

        It 'reads the budget off the response headers' {
            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r'

            $result.RateLimit.Remaining | Should -Be 4990
            $result.RateLimit.Limit     | Should -Be 5000
        }

        It 'converts the reset stamp to a UTC instant' {
            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r'

            $result.RateLimit.ResetsAt.Kind | Should -Be ([DateTimeKind]::Utc)
        }

        It 'reports the budget on a 304 as well' {
            $script:stubStatus = 304
            $cache = @{ 'repos/o/r' = [PSCustomObject]@{ ETag = 'W/"old"'; Payload = 'cached' } }

            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' -Cache $cache

            $result.RateLimit.Remaining | Should -Be 4990
        }

        It 'returns a null budget when the headers carry none' {
            $script:stubHeaders = @{ 'ETag' = @('W/"abc123"') }

            $result = Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r'

            $result.RateLimit | Should -BeNullOrEmpty
        }
    }

    # ------------------------------------------------------------------
    Context 'error statuses' {
    # ------------------------------------------------------------------
    # -StatusCodeVariable suppresses Invoke-RestMethod's own error check, so
    # these have to be raised by the function itself.

        It 'throws on a client error' {
            $script:stubStatus = 401

            { Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' } |
                Should -Throw '*401*'
        }

        It 'throws on a server error' {
            $script:stubStatus = 502

            { Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' } |
                Should -Throw '*502*'
        }

        It 'throws on a 304 it has no cached payload to replay' {
            $script:stubStatus = 304

            { Invoke-GitHubConditionalGet -Token 't' -Endpoint 'repos/o/r' } |
                Should -Throw '*no cached payload*'
        }
    }
}
