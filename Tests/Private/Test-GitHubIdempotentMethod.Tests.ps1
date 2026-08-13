BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\Test-GitHubIdempotentMethod.ps1"
}

Describe 'Test-GitHubIdempotentMethod' {

    # ------------------------------------------------------------------
    Context 'methods safe to replay' {
    # ------------------------------------------------------------------

        It 'accepts GET' {
            Test-GitHubIdempotentMethod -Method 'Get' | Should -BeTrue
        }

        It 'accepts HEAD' {
            Test-GitHubIdempotentMethod -Method 'Head' | Should -BeTrue
        }

        It 'accepts OPTIONS' {
            Test-GitHubIdempotentMethod -Method 'Options' | Should -BeTrue
        }

        It 'ignores casing' {
            # Call sites pass whatever casing reads well; Invoke-RestMethod
            # itself is indifferent, so this must be too.
            Test-GitHubIdempotentMethod -Method 'get' | Should -BeTrue
            Test-GitHubIdempotentMethod -Method 'GET' | Should -BeTrue
        }
    }

    # ------------------------------------------------------------------
    Context 'methods that can double-execute' {
    # ------------------------------------------------------------------

        It 'rejects POST' {
            Test-GitHubIdempotentMethod -Method 'Post' | Should -BeFalse
        }

        It 'rejects PATCH' {
            Test-GitHubIdempotentMethod -Method 'Patch' | Should -BeFalse
        }

        It 'rejects PUT' {
            Test-GitHubIdempotentMethod -Method 'Put' | Should -BeFalse
        }

        It 'rejects DELETE' {
            # DELETE is idempotent per RFC, but a replay of one that already
            # succeeded answers 404 and reads as a teardown failure upstream.
            Test-GitHubIdempotentMethod -Method 'Delete' | Should -BeFalse
        }
    }
}
