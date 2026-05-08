BeforeAll {
    function Invoke-SshClientCommand { param($SshClient, $Command) }

    . "$PSScriptRoot\..\Infrastructure.GitHub\Public\Invoke-RunnerTarballDeploy.ps1"

    $Script:FakeSsh    = [PSCustomObject] @{}
    $Script:TarUrl     = 'http://10.10.0.1:8745/actions-runner-linux-x64-2.317.0.tar.gz'
    $Script:TarName    = 'actions-runner-linux-x64-2.317.0.tar.gz'
    $Script:RunnerUser = 'u-actions-runner'
    $Script:DefaultCacheDir = '/home/u-actions-runner/cache'
    $Script:DefaultTarPath  = '/home/u-actions-runner/cache/actions-runner-linux-x64-2.317.0.tar.gz'
}

Describe 'Invoke-RunnerTarballDeploy' {

    # ------------------------------------------------------------------
    Context 'cache directory creation' {
    # ------------------------------------------------------------------

        It 'creates the cache directory as the runner user' {
            Mock Invoke-SshClientCommand { [PSCustomObject] @{ ExitStatus = 0; Error = '' } }

            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -eq "sudo -u u-actions-runner mkdir -p '$Script:DefaultCacheDir'"
            }
        }

        It 'uses explicit CacheDir when provided' {
            Mock Invoke-SshClientCommand { [PSCustomObject] @{ ExitStatus = 0; Error = '' } }

            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser `
                -CacheDir   '/custom/cache'

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -eq "sudo -u u-actions-runner mkdir -p '/custom/cache'"
            }
        }

        It 'throws when cache directory cannot be created' {
            Mock Invoke-SshClientCommand {
                [PSCustomObject] @{ ExitStatus = 1; Error = 'permission denied' }
            }

            { Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser
            } | Should -Throw '*Failed to create cache directory*'
        }

        It 'includes Label in the error when mkdir fails' {
            Mock Invoke-SshClientCommand {
                [PSCustomObject] @{ ExitStatus = 1; Error = 'permission denied' }
            }

            { Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser `
                -Label      'vm-01'
            } | Should -Throw '*vm-01*'
        }
    }

    # ------------------------------------------------------------------
    Context 'tarball already cached' {
    # ------------------------------------------------------------------

        It 'skips purge and download when the tarball is present' {
            Mock Invoke-SshClientCommand { [PSCustomObject] @{ ExitStatus = 0; Error = '' } }

            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser

            Should -Invoke Invoke-SshClientCommand -Times 0 -ParameterFilter {
                $Command -like '*curl*'
            }
            Should -Invoke Invoke-SshClientCommand -Times 0 -ParameterFilter {
                $Command -like '*rm -f*'
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'tarball absent' {
    # ------------------------------------------------------------------

        BeforeEach {
            Mock Invoke-SshClientCommand {
                param($SshClient, $Command)
                $exit = if ($Command -like 'sudo -u * test -f*') { 1 } else { 0 }
                [PSCustomObject] @{ ExitStatus = $exit; Error = '' }
            }
        }

        It 'purges stale tarballs before downloading' {
            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -like "*sudo -u u-actions-runner rm -f '$Script:DefaultCacheDir'/actions-runner-*.tar.gz"
            }
        }

        It 'downloads the tarball from TarUrl' {
            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -like "*curl*'$Script:TarUrl'*"
            }
        }

        It 'downloads the tarball to the derived cache path' {
            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -like "*-o '$Script:DefaultTarPath'*"
            }
        }

        It 'downloads to an explicit CacheDir' {
            Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser `
                -CacheDir   '/custom/cache'

            Should -Invoke Invoke-SshClientCommand -Times 1 -ParameterFilter {
                $Command -like "*-o '/custom/cache/$Script:TarName'*"
            }
        }

        It 'throws when purge fails' {
            Mock Invoke-SshClientCommand {
                param($SshClient, $Command)
                $exit = if     ($Command -like 'sudo -u * test -f*') { 1 }
                        elseif ($Command -like '*rm -f*')             { 1 }
                        else                                          { 0 }
                [PSCustomObject] @{ ExitStatus = $exit; Error = 'permission denied' }
            }

            { Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser
            } | Should -Throw '*Failed to purge stale tarballs*'
        }

        It 'throws when curl fails' {
            Mock Invoke-SshClientCommand {
                param($SshClient, $Command)
                $exit = if     ($Command -like 'sudo -u * test -f*') { 1 }
                        elseif ($Command -like '*curl*')              { 1 }
                        else                                          { 0 }
                [PSCustomObject] @{ ExitStatus = $exit; Error = 'network error' }
            }

            { Invoke-RunnerTarballDeploy `
                -SshClient  $Script:FakeSsh `
                -TarUrl     $Script:TarUrl `
                -RunnerUser $Script:RunnerUser
            } | Should -Throw '*curl download failed*'
        }
    }
}
