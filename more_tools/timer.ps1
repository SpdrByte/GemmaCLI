# tools/timer.ps1 v1.1.0
# Responsibility: Simple countdown timer that plays a sound upon completion.
#                 Runs in a loop to keep the GemmaCLI spinner active.

function Invoke-TimerTool {
    param(
        [int]$length_seconds
    )

    if ($length_seconds -le 0) {
        return "ERROR: length_seconds must be a positive integer."
    }

    try {
        $started = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Keep the job alive until the time has passed.
        # This ensures the "Executing timer..." spinner stays visible.
        while ($started.Elapsed.TotalSeconds -lt $length_seconds) {
            Start-Sleep -Milliseconds 250
        }

        # Return with the PLAY_SOUND instruction for the main thread.
        # Alarm01 is a standard Windows timer/alarm sound.
        return "CONSOLE::PLAY_SOUND:Alarm01::END_CONSOLE::OK: Timer for $length_seconds seconds has finished."

    } catch {
        return "ERROR: Timer failed. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "timer"
    Icon             = "⏲️"
    RendersToConsole = $false
    Category         = @("Utility", "Time")
    Behavior         = "Use this tool to set a countdown timer for a specific number of seconds. The CLI will show a spinner until the time is up, then play an alarm sound. Do not call this for durations longer than 300 seconds (5 minutes) unless specifically requested."
    Description      = "Sets a countdown timer for X seconds and plays an alarm sound when finished."
    Parameters       = @{
        length_seconds = "integer - required. The number of seconds to wait before the alarm sounds."
    }
    Example          = "<tool_call>{ ""name"": ""timer"", ""parameters"": { ""length_seconds"": 60 } }</tool_call>"
    FormatLabel      = { param($p) "$($p.length_seconds)s" }
    Execute          = { param($params) Invoke-TimerTool @params }
}
