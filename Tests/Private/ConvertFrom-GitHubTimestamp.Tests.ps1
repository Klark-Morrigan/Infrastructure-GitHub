BeforeAll {
    Set-StrictMode -Version Latest
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\ConvertFrom-GitHubTimestamp.ps1"
}

Describe 'ConvertFrom-GitHubTimestamp' {

    # ------------------------------------------------------------------
    Context 'values as ConvertFrom-Json actually delivers them' {
    # ------------------------------------------------------------------
    # The production path never sees a string: ConvertFrom-Json (and so
    # Invoke-RestMethod) recognises ISO-8601 and hands back a DateTime.

        It 'passes a UTC-kind instant straight through' {
            $parsed = '{ "started_at": "2026-08-06T11:58:00Z" }' | ConvertFrom-Json

            ConvertFrom-GitHubTimestamp $parsed.started_at |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }

        It 'converts a local-kind instant to the same UTC point in time' {
            # An offset timestamp arrives as Kind=Local, rebased to the host
            # timezone. Re-rendering it as a string would lose the offset.
            $parsed = '{ "started_at": "2026-08-06T13:58:00+02:00" }' | ConvertFrom-Json

            ConvertFrom-GitHubTimestamp $parsed.started_at |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }

        It 'always yields a UTC-kind result whatever the input kind' {
            $parsed = '{ "started_at": "2026-08-06T13:58:00+02:00" }' | ConvertFrom-Json

            (ConvertFrom-GitHubTimestamp $parsed.started_at).Kind |
                Should -Be ([DateTimeKind]::Utc)
        }

        It 'treats an offset-less instant as the UTC point it claims to be' {
            $unspecified = [DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Unspecified)

            $result = ConvertFrom-GitHubTimestamp $unspecified

            $result      | Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
            $result.Kind | Should -Be ([DateTimeKind]::Utc)
        }

        It 'accepts a DateTimeOffset' {
            ConvertFrom-GitHubTimestamp ([DateTimeOffset]::new(
                2026, 8, 6, 13, 58, 0, [TimeSpan]::FromHours(2))) |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }
    }

    # ------------------------------------------------------------------
    Context 'raw string values' {
    # ------------------------------------------------------------------

        It 'parses a Z-suffixed instant' {
            ConvertFrom-GitHubTimestamp '2026-08-06T11:58:00Z' |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }

        It 'returns a UTC DateTime so callers can subtract UtcNow directly' {
            (ConvertFrom-GitHubTimestamp '2026-08-06T11:58:00Z').Kind |
                Should -Be ([DateTimeKind]::Utc)
        }

        It 'normalises an offset instant to UTC' {
            ConvertFrom-GitHubTimestamp '2026-08-06T13:58:00+02:00' |
                Should -Be ([DateTime]::new(2026, 8, 6, 11, 58, 0, [DateTimeKind]::Utc))
        }
    }

    # ------------------------------------------------------------------
    Context 'absent and malformed values' {
    # ------------------------------------------------------------------

        It 'returns null for an empty string' {
            ConvertFrom-GitHubTimestamp '' | Should -BeNullOrEmpty
        }

        It 'returns null for null' {
            ConvertFrom-GitHubTimestamp $null | Should -BeNullOrEmpty
        }

        It 'returns null rather than throwing on a malformed value' {
            # One unparseable field must not fail a whole poll.
            ConvertFrom-GitHubTimestamp 'not-a-timestamp' | Should -BeNullOrEmpty
        }
    }
}
