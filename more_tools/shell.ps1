# more_tools/shell.ps1
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
    Behavior    = "Use this tool to execute shell commands via cmd.exe. Use with caution as it interacts directly with the system."
    Description = "Executes a shell command via cmd.exe."
    Parameters  = @{
        command = "string - the command to execute"
    }
    Example     = "<tool_call>{ ""name"": ""shell"", ""parameters"": { ""command"": ""dir"" } }</tool_call>"
    FormatLabel = { param($params) "shell -> $($params.command)" }
    Execute     = { param($params) Invoke-ShellTool @params }
}
