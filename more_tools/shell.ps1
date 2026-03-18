# GemmaCLI Tool - shell.ps1 v0.1
# WARNING 0.1a experimental (not recommended to enable this tool outside of a test environment)

function Invoke-ShellTool {
    param([string]$command)
    
    # --- START SAFETY FILTER ---
    # Block obviously destructive patterns. Remove or modify these patterns to adjust safety.
    $blocked = @('Format-Volume', 'Clear-Disk', 'Remove-Item.*-Recurse.*C:\\', 'rm -rf /')
    foreach ($pattern in $blocked) {
        if ($command -match $pattern) {
            return "ERROR: Command blocked by safety filter."
        }
    }
    # --- END SAFETY FILTER ---
    
    try {
        # Executes the command via cmd.exe and captures both stdout and stderr
        $result = cmd /c $command 2>&1
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            return "WARN: Command exited with code $LASTEXITCODE.`n$($result -join "`n")"
        }
        
        if ($result -is [array]) {
            return $result -join "`n"
        }
        return $result
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "shell"
    RendersToConsole = $false
    Category    = @("System Administration", "Physical Computing")
    Behavior    = "Use this tool to execute shell commands via cmd.exe. Use with caution as it interacts directly with the system."
    Description = "Executes a shell command via cmd.exe."
    Parameters  = @{
        command = "string - the command to execute"
    }
    Example     = "<tool_call>{ ""name"": ""shell"", ""parameters"": { ""command"": ""dir"" } }</tool_call>"
    FormatLabel = { param($params) "shell -> $($params.command)" }
    Execute     = { param($params) Invoke-ShellTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'shell': Use this tool to execute system commands directly via `cmd.exe`. This tool should be used with extreme caution and only when absolutely necessary for tasks that cannot be accomplished by other, safer tools.
        - Important parameters for 'shell': 
            - `command`: The exact shell command to execute. Always double-check the command for correctness and potential side effects before execution.
        - **CRITICAL CAUTION**: This tool interacts directly with the user's operating system. Malformed or malicious commands can cause irreversible damage to the system or data.
        - Safety Filter: Be aware that a safety filter is in place to block obviously destructive patterns (e.g., `Remove-Item -Recurse C:\`). Do NOT attempt to bypass this filter.
        - User Confirmation: Due to its destructive potential, always seek explicit user confirmation before executing any command that modifies the file system or system configuration.
        - Debugging: If a command fails, inspect the error message carefully.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Run system commands.
        - Basic use: Provide the `command` to execute.
        - **WARNING**: This tool can damage the system. Use with extreme caution.
        - Always ask the user before running commands that change files.
"@
}
