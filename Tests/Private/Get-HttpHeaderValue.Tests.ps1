BeforeAll {
    Set-StrictMode -Version Latest
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\Get-HttpHeaderValue.ps1"
}

Describe 'Get-HttpHeaderValue' {

    It 'returns the first element of the value array' {
        # Invoke-RestMethod's response dictionary maps each header to a string
        # array, one entry per repetition of the header.
        Get-HttpHeaderValue @{ 'ETag' = @('W/"abc"') } 'ETag' | Should -Be 'W/"abc"'
    }

    It 'matches the header name without regard to case' {
        Get-HttpHeaderValue @{ 'etag' = @('W/"abc"') } 'ETag' | Should -Be 'W/"abc"'
    }

    It 'returns null for an absent header' {
        Get-HttpHeaderValue @{ 'ETag' = @('W/"abc"') } 'X-RateLimit-Remaining' |
            Should -BeNullOrEmpty
    }

    It 'returns null when the dictionary itself is null' {
        Get-HttpHeaderValue $null 'ETag' | Should -BeNullOrEmpty
    }

    It 'accepts a bare string value as well as an array' {
        Get-HttpHeaderValue @{ 'ETag' = 'W/"abc"' } 'ETag' | Should -Be 'W/"abc"'
    }
}
