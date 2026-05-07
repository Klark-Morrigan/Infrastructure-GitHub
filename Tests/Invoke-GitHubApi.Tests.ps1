BeforeAll {
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
    Context 'return value' {
    # ------------------------------------------------------------------

        It 'returns the Invoke-RestMethod response' {
            Mock Invoke-RestMethod { [PSCustomObject]@{ id = 42 } }

            $result = Invoke-GitHubApi -Token 't' -Uri 'https://api.github.com/test'

            $result.id | Should -Be 42
        }
    }
}
