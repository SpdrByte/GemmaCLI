# tests/shell.Tests.ps1

Describe "Shell Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../tools/shell.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../more_tools/shell.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should execute a simple command and return the output" {
        $result = Invoke-ShellTool -command "echo hello"
        $result | Should Match "hello"
    }

    It "should handle multi-line output" {
        $command = "echo line1 && echo line2"
        $result = Invoke-ShellTool -command $command
        $result | Should Match "line1"
        $result | Should Match "line2"
    }

    It "should block dangerous commands" {
        $result = Invoke-ShellTool -command "rm -rf /"
        $result | Should Be "ERROR: Command blocked by safety filter."
    }

    It "should return a warning for an invalid command" {
        $result = Invoke-ShellTool -command "invalid-cmd-name"
        $result | Should Match "WARN: Command exited with code"
    }
}
