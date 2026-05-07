# ===============================================
# GemmaCLI Tool - launch_gemini.ps1 v1.0.0
# Responsibility: Launches the Gemini CLI in a new terminal window at a specific directory.
# ===============================================

function Invoke-LaunchGeminiTool {
    param (
        [Parameter(Mandatory = $true)]
        [string]$directory,

        [Parameter(Mandatory = $false)]
        [ValidateSet("cmd", "ps", "wt")]
        [string]$terminal = "ps"
    )

    # 1. Verify directory exists
    if (-not (Test-Path -Path $directory)) {
        $errorMsg = "The directory '$directory' does not exist."
        Draw-Box -Title "Launch Error" -Content $errorMsg -Color Red
        return "CONSOLE::ERROR: $errorMsg::END_CONSOLE::Error: DirectoryNotFound ($directory)"
    }

    # Resolve to absolute path to ensure child process finds it correctly
    $absPath = (Resolve-Path -Path $directory).Path
    
    try {
        switch ($terminal.ToLower()) {
            "cmd" {
                # /k keeps the window open, cd /d handles drive changes, && runs the next command
                Start-Process "cmd.exe" -ArgumentList "/k cd /d `"$absPath`" && gemini"
            }
            "ps" {
                # -NoExit keeps the window open
                Start-Process "powershell.exe" -ArgumentList "-NoExit -Command `"Set-Location -Path '$absPath'; gemini`""
            }
            "wt" {
                # -d specifies the starting directory for Windows Terminal
                Start-Process "wt.exe" -ArgumentList "-d `"$absPath`" cmd /k gemini"
            }
        }

        $successMsg = "Successfully launched Gemini CLI in $terminal.`nPath: $absPath"
        Draw-Box -Title "Gemini Launcher" -Content $successMsg -Color Green
        
        return "CONSOLE::PLAY_SOUND:tada::$successMsg::END_CONSOLE::Success: Launched gemini in $terminal at $absPath"
    }
    catch {
        $exMsg = $_.Exception.Message
        Draw-Box -Title "Execution Error" -Content "Failed to start process: $exMsg" -Color Red
        return "CONSOLE::BEEP:200,200 Error: $exMsg::END_CONSOLE::Error: ProcessStartFailed - $exMsg"
    }
}

$ToolMeta = @{
    Name = "launch_gemini"
    Icon = "🚀"
    Description = "Opens a new terminal (CMD, PS, or WT) in a target directory and starts the gemini CLI."
    Category = @("System", "CLI", "Automation")
    Keywords = @("launch", "terminal", "gemini", "directory", "shell")
    RendersToConsole = $true
    Interactive = $false
    RequiresBilling = $false
    RequiresKey = $false
    Behavior = "This tool uses Start-Process to spawn a new shell environment. It handles path quoting for directories with spaces and uses specific flags to ensure the terminal remains open after the initial command."
    Parameters = @{
        directory = @{
            Type = "string"
            Description = "The absolute or relative path to the directory where GeminiCLI should be launched."
            Required = $true
        }
        terminal = @{
            Type = "string"
            Description = "The terminal emulator to use: 'cmd' (Command Prompt), 'ps' (PowerShell), or 'wt' (Windows Terminal)."
            Default = "ps"
        }
    }
    Example = '<tool_call name="launch_gemini">{"directory": "C:\\Projects\\MyGeminiApp", "terminal": "wt"}</tool_call>'
    FormatLabel = {
        param($p)
        "🚀 Launching Gemini in $($p.terminal) at $($p.directory)"
    }
    Execute = {
        param($params)
        Invoke-LaunchGeminiTool @params
    }
    ToolUseGuidanceMajor = "Use this tool when the user wants to interact with Gemini in a dedicated local shell or start a project session."
    ToolUseGuidanceMinor = "Ensure the 'gemini' command is in the system PATH before calling, otherwise the new terminal will show a 'command not found' error."
}