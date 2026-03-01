# tests/custom_command.Tests.ps1

Describe "Custom Command Expansion" {
    $script:customCommands = @{
        "/poem" = "write a short poem about PowerShell"
    }

    It "should expand a known custom command" {
        $userInput = "/poem"
        if ($script:customCommands.ContainsKey($userInput)) {
            $userInput = $script:customCommands[$userInput]
        }
        $userInput | Should Be "write a short poem about PowerShell"
    }

    It "should not modify a regular command" {
        $userInput = "/help"
        if ($script:customCommands.ContainsKey($userInput)) {
            $userInput = $script:customCommands[$userInput]
        }
        $userInput | Should Be "/help"
    }
}
