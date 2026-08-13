# ---------------------------------------------------------------------------
# Get-HttpHeaderValue
#   Reads a single header value out of the dictionary Invoke-RestMethod hands
#   back through -ResponseHeadersVariable. Returns $null when the header is
#   absent.
#
#   Two shape details make a plain indexer lookup wrong, hence this helper:
#   the dictionary's values are string ARRAYS (one entry per repeated header),
#   and its key comparer is not guaranteed to be case-insensitive even though
#   HTTP header names are. So the lookup is a case-insensitive scan and the
#   result is the first element of whatever it finds.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function Get-HttpHeaderValue {
    [CmdletBinding()]
    param(
        # The response header dictionary. $null is accepted (a mocked or
        # header-less call) and yields $null.
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $Headers,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Headers) { return $null }

    foreach ($key in $Headers.Keys) {
        if ($key -ine $Name) { continue }

        $value = $Headers[$key]
        if ($null -eq $value) { return $null }
        return (@($value) | Select-Object -First 1)
    }

    return $null
}
