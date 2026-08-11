# ---------------------------------------------------------------------------
# Get-GitHubResponseProperty
#   Reads a property off a ConvertFrom-Json response object, returning
#   $Default when the object is $null, the property is absent, or its value
#   is $null.
#
#   Every read of a GitHub API response goes through here for one reason:
#   the module runs under Set-StrictMode -Version Latest, which makes
#   touching a missing property on a PSCustomObject a terminating error, and
#   GitHub omits fields rather than sending nulls. A queued job carries no
#   `runner_name`; a repo with no runners returns a `runners` key that may be
#   absent entirely. Guarding at each call site would bury the logic, so the
#   guard lives here instead.
#
#   Private to the module - not exported.
# ---------------------------------------------------------------------------

function Get-GitHubResponseProperty {
    [CmdletBinding()]
    param(
        # The response object (or any PSObject). $null is accepted and yields
        # $Default, so callers can chain reads off an optional object without
        # a null check of their own.
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Position = 2)]
        [AllowNull()]
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    # A hashtable exposes its entries through Keys, not PSObject.Properties,
    # so handle it explicitly - test fixtures and hand-built payloads use it.
    if ($InputObject -is [System.Collections.IDictionary]) {
        if (-not $InputObject.Contains($Name)) { return $Default }
        $value = $InputObject[$Name]
        if ($null -eq $value) { return $Default }
        return $value
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }

    $property.Value
}
