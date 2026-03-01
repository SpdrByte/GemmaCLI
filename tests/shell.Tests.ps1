# tests/shell.Tests.ps1

Describe "Shell Tool" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../more_tools/shell.ps1")
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
