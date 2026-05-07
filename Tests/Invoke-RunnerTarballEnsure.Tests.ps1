BeforeAll {
    . "$PSScriptRoot\..\Infrastructure.GitHub\Public\Invoke-RunnerTarballEnsure.ps1"

    # Real temp directories so file-system operations work correctly.
    $script:cacheDir = Join-Path ([System.IO.Path]::GetTempPath()) `
        "InvokeRunnerTarballEnsure-Tests-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:cacheDir -Force | Out-Null

    $script:version  = '2.317.0'
    $script:tarName  = "actions-runner-linux-x64-$($script:version).tar.gz"
    $script:tarPath  = Join-Path $script:cacheDir $script:tarName
}

AfterAll {
    Remove-Item -Recurse -Force -LiteralPath $script:cacheDir -ErrorAction SilentlyContinue
}

Describe 'Invoke-RunnerTarballEnsure' {

    Context 'tarball already cached' {
        BeforeEach {
            # Place a sentinel file so the download branch is not taken.
            [System.IO.File]::WriteAllBytes($script:tarPath, [byte[]](1..8))
            Mock Invoke-WebRequest {}
        }

        AfterEach {
            Remove-Item -LiteralPath $script:tarPath -ErrorAction SilentlyContinue
        }

        It 'does not call Invoke-WebRequest when the tarball is present' {
            Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            Should -Invoke Invoke-WebRequest -Times 0
        }

        It 'returns the local path when the tarball is already cached' {
            $result = Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            $result | Should -Be $script:tarPath
        }
    }

    Context 'tarball absent' {
        BeforeEach {
            # Ensure the target file is absent before each test.
            Remove-Item -LiteralPath $script:tarPath -ErrorAction SilentlyContinue

            # Simulate a successful download by writing a stub file.
            Mock Invoke-WebRequest {
                param($Uri, $OutFile)
                [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1..8))
            }
        }

        AfterEach {
            Remove-Item -Path "$script:cacheDir\*" -Force -ErrorAction SilentlyContinue
        }

        It 'calls Invoke-WebRequest with the correct GitHub URL' {
            Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            $expectedUrl = "https://github.com/actions/runner/releases/download/" +
                           "v$($script:version)/$($script:tarName)"
            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq $expectedUrl
            }
        }

        It 'writes the tarball to the cache directory' {
            Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            $script:tarPath | Should -Exist
        }

        It 'returns the local path after downloading' {
            $result = Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            $result | Should -Be $script:tarPath
        }

        It 'purges stale tarballs before downloading' {
            # Place a stale tarball from an older version.
            $stalePath = Join-Path $script:cacheDir 'actions-runner-linux-x64-2.300.0.tar.gz'
            [System.IO.File]::WriteAllBytes($stalePath, [byte[]](1..4))

            Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $script:cacheDir

            $stalePath | Should -Not -Exist
        }

        It 'creates the cache directory when it does not exist' {
            $newDir = Join-Path $script:cacheDir 'subdir'

            Invoke-RunnerTarballEnsure `
                -RunnerVersion $script:version `
                -CacheDir      $newDir

            $newDir | Should -Exist
            Remove-Item -Recurse -Force -LiteralPath $newDir -ErrorAction SilentlyContinue
        }
    }
}
