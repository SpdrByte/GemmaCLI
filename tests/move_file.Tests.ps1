# tests/move_file.Tests.ps1

Describe "Move File Tool" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../more_tools/move_file.ps1")
        $script:sourceFile = New-TemporaryFile
        $script:destPath = Join-Path $env:TEMP "moved_test_file.tmp"
    }

    AfterAll {
        if ($script:sourceFile) { Remove-Item $script:sourceFile.FullName -Force -ErrorAction SilentlyContinue }
        if (Test-Path $script:destPath) { Remove-Item $script:destPath -Force -ErrorAction SilentlyContinue }
    }

    It "should move the file to the destination" {
        Invoke-MoveFileTool -source $script:sourceFile.FullName -destination $script:destPath
        (Test-Path $script:destPath) | Should Be $true
        (Test-Path $script:sourceFile.FullName) | Should Be $false
    }
}
