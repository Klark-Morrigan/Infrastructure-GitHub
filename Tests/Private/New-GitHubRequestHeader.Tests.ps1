BeforeAll {
    Set-StrictMode -Version Latest
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\New-GitHubRequestHeader.ps1"
}

Describe 'New-GitHubRequestHeader' {

    It 'asks for the versioned GitHub media type' {
        (New-GitHubRequestHeader)['Accept'] | Should -Be 'application/vnd.github+json'
    }

    It 'pins the API version explicitly' {
        # Left unpinned, GitHub is free to move the default version underneath
        # a dashboard that has been polling for weeks, changing response shapes
        # with no deploy on our side. Bumping this is a deliberate act, so the
        # value is asserted rather than merely required to be present.
        (New-GitHubRequestHeader)['X-GitHub-Api-Version'] | Should -Be '2022-11-28'
    }

    It 'returns a fresh hashtable on every call' {
        # Invoke-GitHubConditionalGet adds 'If-None-Match' to what it gets back.
        # A shared instance would leak one endpoint's ETag onto the next
        # request, which would then revalidate against the wrong resource.
        $first = New-GitHubRequestHeader
        $first['If-None-Match'] = 'W/"abc"'

        (New-GitHubRequestHeader).ContainsKey('If-None-Match') | Should -BeFalse
    }

    It 'carries no authentication of its own' {
        # Authorization and User-Agent are Invoke-GitHubApi's fixed set. Adding
        # them here would silently override the caller's token.
        $header = New-GitHubRequestHeader

        $header.ContainsKey('Authorization') | Should -BeFalse
        $header.Count                        | Should -Be 2
    }
}
