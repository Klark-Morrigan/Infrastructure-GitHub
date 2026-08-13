BeforeAll {
    Set-StrictMode -Version Latest
    $privatePath = "$PSScriptRoot\..\..\Infrastructure.GitHub\Private"
    . "$privatePath\Get-GitHubResponseProperty.ps1"
    . "$privatePath\Get-GitHubJobCurrentStep.ps1"
}

Describe 'Get-GitHubJobCurrentStep' {

    It 'returns the step that is in progress' {
        $job = @'
{ "steps": [ { "name": "Set up job", "status": "completed",   "conclusion": "success" },
             { "name": "Run tests",  "status": "in_progress", "conclusion": null },
             { "name": "Cleanup",    "status": "queued",      "conclusion": null } ] }
'@ | ConvertFrom-Json

        Get-GitHubJobCurrentStep $job | Should -Be 'Run tests'
    }

    It 'falls back to the last concluded step when nothing is in progress' {
        # The job is between steps - the furthest point it has reached is a
        # more useful answer than reporting nothing.
        $job = @'
{ "steps": [ { "name": "Set up job", "status": "completed", "conclusion": "success" },
             { "name": "Checkout",   "status": "completed", "conclusion": "success" },
             { "name": "Run tests",  "status": "queued",    "conclusion": null } ] }
'@ | ConvertFrom-Json

        Get-GitHubJobCurrentStep $job | Should -Be 'Checkout'
    }

    It 'returns null when the job has no steps yet' {
        $job = '{ "steps": [] }' | ConvertFrom-Json

        Get-GitHubJobCurrentStep $job | Should -BeNullOrEmpty
    }

    It 'returns null when the job carries no steps key' {
        $job = '{ "name": "build" }' | ConvertFrom-Json

        Get-GitHubJobCurrentStep $job | Should -BeNullOrEmpty
    }

    It 'returns null for a null job' {
        Get-GitHubJobCurrentStep $null | Should -BeNullOrEmpty
    }

    It 'returns null when every step is still queued' {
        $job = @'
{ "steps": [ { "name": "Set up job", "status": "queued", "conclusion": null } ] }
'@ | ConvertFrom-Json

        Get-GitHubJobCurrentStep $job | Should -BeNullOrEmpty
    }
}
