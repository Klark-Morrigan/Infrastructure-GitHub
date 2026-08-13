BeforeAll {
    . "$PSScriptRoot\..\..\Infrastructure.GitHub\Private\New-GitHubWriteRetryStrategy.ps1"

    # Builds the shape HttpClient actually produces: a SocketException wrapped
    # in an HttpRequestException, wrapped in an ErrorRecord. Pass -Bare to skip
    # the HTTP layer and check the chain walk finds a top-level socket error.
    function New-SocketErrorRecord {
        param(
            [System.Net.Sockets.SocketError] $SocketError,
            [switch] $Bare
        )

        $socketException = [System.Net.Sockets.SocketException]::new([int] $SocketError)
        $exception       = if ($Bare) {
            $socketException
        } else {
            [System.Net.Http.HttpRequestException]::new(
                'No such host is known.', $socketException)
        }

        [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'TestError',
            [System.Management.Automation.ErrorCategory]::NotSpecified,
            $null)
    }

    function Test-StrategyVerdict {
        param([System.Management.Automation.ErrorRecord] $ErrorRecord)

        $strategy = New-GitHubWriteRetryStrategy
        return [bool] (& $strategy.ShouldRetry $ErrorRecord)
    }
}

Describe 'New-GitHubWriteRetryStrategy' {

    # ------------------------------------------------------------------
    Context 'strategy shape' {
    # ------------------------------------------------------------------

        It 'returns the retry-strategy contract Invoke-WithRetry consumes' {
            $strategy = New-GitHubWriteRetryStrategy

            $strategy.Name        | Should -Be 'GitHubConnectFailure'
            $strategy.ShouldRetry | Should -BeOfType [scriptblock]
        }
    }

    # ------------------------------------------------------------------
    Context 'failures that never reached GitHub' {
    # ------------------------------------------------------------------
    # Safe to replay on a write: no request bytes left the machine, so the
    # server cannot have acted on it.

        It 'retries a DNS resolution failure' {
            # The observed E2E failure: "No such host is known.
            # (api.github.com:443)".
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::HostNotFound)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeTrue
        }

        It 'retries a refused connection' {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::ConnectionRefused)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeTrue
        }

        It 'retries an unreachable network' {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::NetworkUnreachable)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeTrue
        }

        # The remaining allowlist entries, so dropping one from the strategy
        # fails a test rather than silently narrowing the policy.
        It 'retries <Name>' -TestCases @(
            @{ Name = 'a retryable DNS failure';  Code = 'TryAgain' }
            @{ Name = 'a name with no data';      Code = 'NoData' }
            @{ Name = 'an unreachable host';      Code = 'HostUnreachable' }
            @{ Name = 'a downed network';         Code = 'NetworkDown' }
        ) {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError] $Code)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeTrue
        }

        It 'finds a socket error that is not wrapped in an HTTP exception' {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::HostNotFound) -Bare

            Test-StrategyVerdict -ErrorRecord $record | Should -BeTrue
        }
    }

    # ------------------------------------------------------------------
    Context 'failures that may have been acted on' {
    # ------------------------------------------------------------------
    # Genuinely transient, but a write replayed after one of these can
    # double-execute - a second registration token, a runner removed twice.

        It 'declines a timeout' {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::TimedOut)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeFalse
        }

        It 'declines a mid-flight connection reset' {
            $record = New-SocketErrorRecord `
                -SocketError ([System.Net.Sockets.SocketError]::ConnectionReset)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeFalse
        }

        It 'declines a task cancellation' {
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.Threading.Tasks.TaskCanceledException]::new('timed out'),
                'TestError',
                [System.Management.Automation.ErrorCategory]::OperationTimeout,
                $null)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeFalse
        }
    }

    # ------------------------------------------------------------------
    Context 'permanent failures' {
    # ------------------------------------------------------------------

        It 'declines an HTTP exception carrying no socket error' {
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.Net.Http.HttpRequestException]::new('bad gateway'),
                'TestError',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeFalse
        }

        It 'declines an ordinary exception' {
            $record = [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new('bad argument'),
                'TestError',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $null)

            Test-StrategyVerdict -ErrorRecord $record | Should -BeFalse
        }
    }
}
