BeforeAll {
    Set-StrictMode -Version Latest
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\Get-GitHubResponseProperty.ps1"
}

Describe 'Get-GitHubResponseProperty' {

    It 'returns the property value when present' {
        $object = '{ "status": "online" }' | ConvertFrom-Json

        Get-GitHubResponseProperty $object 'status' | Should -Be 'online'
    }

    It 'returns the default when the property is absent' {
        $object = '{ "status": "online" }' | ConvertFrom-Json

        Get-GitHubResponseProperty $object 'busy' 'fallback' | Should -Be 'fallback'
    }

    It 'returns the default when the property is JSON null' {
        $object = '{ "runner_name": null }' | ConvertFrom-Json

        Get-GitHubResponseProperty $object 'runner_name' 'fallback' | Should -Be 'fallback'
    }

    It 'returns the default when the object itself is null' {
        Get-GitHubResponseProperty $null 'status' 'fallback' | Should -Be 'fallback'
    }

    It 'defaults to null when no default is supplied' {
        $object = '{ "status": "online" }' | ConvertFrom-Json

        Get-GitHubResponseProperty $object 'busy' | Should -BeNullOrEmpty
    }

    It 'yields an empty collection for an absent array property' {
        $object = '{}' | ConvertFrom-Json

        @(Get-GitHubResponseProperty $object 'runners' @()) | Should -HaveCount 0
    }

    It 'preserves a false value rather than treating it as absent' {
        $object = '{ "busy": false }' | ConvertFrom-Json

        Get-GitHubResponseProperty $object 'busy' $true | Should -BeFalse
    }

    It 'reads a hashtable through its keys' {
        Get-GitHubResponseProperty @{ status = 'online' } 'status' | Should -Be 'online'
    }

    It 'returns the default for a missing hashtable key' {
        Get-GitHubResponseProperty @{ status = 'online' } 'busy' 'fallback' | Should -Be 'fallback'
    }
}
