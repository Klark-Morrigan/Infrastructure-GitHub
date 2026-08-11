# ---------------------------------------------------------------------------
# ConvertFrom-GitHubTimestamp
#   Normalises a timestamp field from a GitHub API response into a UTC
#   [DateTime]. Returns $null for an absent, empty, or unparseable value.
#
#   Normalising to UTC here (rather than leaving the raw value alone) is what
#   lets callers compute an elapsed duration with a plain [DateTime]::UtcNow
#   subtraction.
#
#   The input is deliberately untyped, because the field does NOT arrive as a
#   string. ConvertFrom-Json - which Invoke-RestMethod uses internally -
#   recognises ISO-8601 values and hands back a [DateTime] already: Kind=Utc
#   for a 'Z' instant, Kind=Local for one with a numeric offset. Declaring the
#   parameter [string] would coerce that object back through ToString() in the
#   local culture, dropping the offset, and the reparse would then shift the
#   instant by the host's UTC offset. Accepting the object and converting by
#   Kind is the only way to stay correct on a host that is not on UTC.
#
#   A malformed value yields $null rather than throwing: it is one field of
#   one row on a status report, and losing the elapsed time for that row is a
#   far better outcome than failing the whole poll.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function ConvertFrom-GitHubTimestamp {
    [CmdletBinding()]
    [OutputType([DateTime])]
    param(
        # A [DateTime] (the normal case, courtesy of ConvertFrom-Json), a
        # [DateTimeOffset], or an ISO-8601 string. $null yields $null.
        [Parameter(Position = 0)]
        [AllowNull()]
        $Timestamp
    )

    if ($null -eq $Timestamp) { return $null }

    if ($Timestamp -is [DateTime]) {
        # Unspecified means the source carried no offset at all. GitHub always
        # sends one, so treat it as the UTC instant it claims to be rather
        # than silently re-interpreting it in the host's timezone.
        if ($Timestamp.Kind -eq [DateTimeKind]::Unspecified) {
            return [DateTime]::SpecifyKind($Timestamp, [DateTimeKind]::Utc)
        }
        return $Timestamp.ToUniversalTime()
    }

    if ($Timestamp -is [DateTimeOffset]) { return $Timestamp.UtcDateTime }

    $text = [string] $Timestamp
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    try {
        return ([DateTimeOffset]::Parse(
            $text, [System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
    }
    catch [System.FormatException] {
        return $null
    }
}
