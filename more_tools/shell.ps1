# GemmaCLI Tool - shell.ps1 v0.4.0
# WARNING 0.3 experimental (not recommended to enable this tool outside of a test environment)

function Invoke-ShellTool {
    param([string]$command)
    
    # --- START SAFETY FILTER ---
    # Segmented Permission Checks (#8)
    # Detects destructive commands hidden within pipe chains or compound commands
    # Split by common shell operators: | & && || ;
    $commandSegments = $command -split '\|\||&&|[|&;]'
    
    foreach ($segment in $commandSegments) {
        $trimmedSegment = $segment.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedSegment)) { continue }

        # Block obviously destructive patterns
        $blocked = @('Format-Volume', 'Clear-Disk', 'Remove-Item.*-Recurse.*C:\\', 'rm -rf /')
        
        # Obfuscation Detection (#7)
        # Detects common tricks used to bypass security filters via shell quoting/escaping
        $obfuscationPatterns = @(
            '["'']{2}-',           # Empty quotes before a dash (e.g. ""-f)
            '["'']{3,}',           # 3+ consecutive quotes (e.g. """flag")
            '\\[ \t]',             # Backslash escaped whitespace (Bash style)
            '\^[ \t]',             # Caret escaped whitespace (CMD style)
            '\\{2,}'               # Excessive backslashes (Potential path/escape obfuscation)
        )

        foreach ($pattern in $blocked) {
            if ($trimmedSegment -match $pattern) {
                return "ERROR: Command blocked by safety filter (segment: $trimmedSegment)."
            }
        }

        foreach ($pattern in $obfuscationPatterns) {
            if ($trimmedSegment -match $pattern) {
                return "ERROR: Potential command obfuscation detected in segment: $trimmedSegment."
            }
        }
    }
    # --- END SAFETY FILTER ---

    # Semantic Exit Codes (#1)
    # Maps specific exit codes to human-readable context rather than generic warnings
    $SEMANTIC_EXIT_CODES = @{
        "grep"    = @{ 1 = "No matches found." }
        "findstr" = @{ 1 = "No matches found." }
        "rg"      = @{ 1 = "No matches found." }
        "fc"      = @{ 1 = "Files differ." }
        "diff"    = @{ 1 = "Files differ." }
        "test"    = @{ 1 = "Condition is false." }
        "find"    = @{ 1 = "No matches found." } # Windows find.exe exit code 1
    }
    
    try {
        # Executes the command via cmd.exe and captures both stdout and stderr
        $result = cmd /c $command 2>&1
        $exitCode = $LASTEXITCODE
        
        # Extract base command for semantic check (simple heuristic)
        # Handle pipes and separators by taking the last segment from the same split logic
        $segments = $command -split '\|\||&&|[|&;]'
        $lastSegment = $segments[-1].Trim()
        $baseCmd = ($lastSegment -split '\s+')[0].Replace(".exe", "").ToLower()

        if ($null -ne $exitCode -and $exitCode -ne 0) {
            # Check for semantic meaning
            if ($SEMANTIC_EXIT_CODES.ContainsKey($baseCmd) -and $SEMANTIC_EXIT_CODES[$baseCmd].ContainsKey($exitCode)) {
                $semanticMsg = $SEMANTIC_EXIT_CODES[$baseCmd][$exitCode]
                $output = if ($result -is [array]) { $result -join "`n" } else { $result }
                return "INFO: $semanticMsg`n$output"
            }
            
            return "WARN: Command exited with code $exitCode.`n$($result -join "`n")"
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
    Icon        = "🐚"
    RendersToConsole = $false
    Category    = @("System Administration", "Physical Computing")
    Behavior    = "Use this tool to execute shell commands via cmd.exe. Use with caution as it interacts directly with the system."
    Description = "Executes a shell command via cmd.exe."
    Parameters  = @{
        command = "string - the command to execute"
    }
    Example     = "<tool_call>{ ""name"": ""shell"", ""parameters"": { ""command"": ""dir"" } }</tool_call>"
    FormatLabel = { param($params) "$($params.command)" }
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
