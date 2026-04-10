# ===============================================
# GemmaCLI Tool - day_of_week.ps1 v1.1.0
# Responsibility: Converts a YYYY-MM-DD date into its corresponding day of the week.
# ===============================================

function Invoke-DayOfWeekTool {
    param (
        [Parameter(Mandatory=$true)]
        [string]$date
    )

    try {
        # Attempt to parse the date specifically in YYYY-MM-DD format to ensure strictness.
        # InvariantCulture ensures culture-independent parsing, preventing locale-specific issues.
        $dt = [DateTime]::ParseExact($date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        $dayName = $dt.DayOfWeek.ToString() # e.g., "Monday", "Tuesday"
        
        # Construct Rich UI output lines for GemmaCLI's console rendering.
        $uiLines = @(
            "Date Processor",
            "----------------",
            "Input Date: $date",
            "Day of Week: $dayName"
        )
        
        # Render to CLI using GemmaCLI helper 'Draw-Box' if it's available.
        # This check is defensive, allowing the tool to run even outside a full GemmaCLI environment.
        if (Get-Command -Name Draw-Box -ErrorAction SilentlyContinue) {
            Draw-Box -Lines $uiLines -Color Green -Title "Day of Week Result"
        }
        
        # Return formatted string with success sound for the primary console output.
        # The 'CONSOLE::' and '::END_CONSOLE::' tags are crucial for GemmaCLI interaction.
        # Fixed: Added $dayName after END_CONSOLE so Gemma can see the result.
        return "CONSOLE::The day of the week for $date is $dayName. PLAY_SOUND:tada::END_CONSOLE::$dayName"
    }
    catch {
        # Define a user-friendly error message.
        $userErrorMsg = "Invalid date format: '$date'. Please use YYYY-MM-DD (e.g., 2025-12-25)."
        
        # Render error to CLI using GemmaCLI helper 'Draw-Box' if available.
        if (Get-Command -Name Draw-Box -ErrorAction SilentlyContinue) {
            Draw-Box -Lines @(
                "Validation Error",
                "----------------",
                $userErrorMsg
            ) -Color Red -Title "Input Error"
        }
        
        # Return error with an alert beep for the primary console output.
        # Fixed: Added error message after END_CONSOLE so Gemma knows why it failed.
        return "CONSOLE::ERROR: $userErrorMsg BEEP:440,200::END_CONSOLE::ERROR: $userErrorMsg"
    }
}

# Metadata for the GemmaCLI tool registration.
# This hash table defines how the tool is presented and executed within the GemmaCLI framework.
$ToolMeta = @{
    Version              = "1.1.0"
    Name                 = "day_of_week"
    Icon                 = "📅"
    Description          = "Get the day of the week (Monday-Sunday) for any given YYYY-MM-DD date."
    Category             = @("Utility", "Calendar", "Time")
    RendersToConsole     = $true # Indicates this tool produces console output via CONSOLE:: tags.
    RequiresBilling      = $false # Set to $true if the tool incurs external costs.
    RequiresKey          = $false # Set to $true if the tool requires an API key.
    KeyUrl               = "" # URL for obtaining an API key, if RequiresKey is $true.
    Behavior             = "This tool performs local .NET DateTime parsing. It validates the input string against the ISO 8601 date format. If parsing fails, it provides a descriptive error instead of crashing."
    Parameters           = @{
        date = @{
            Type        = "string"
            Description = "The date to analyze in YYYY-MM-DD format (e.g., '2025-12-25')."
            Required    = $true
        }
    }
    Example              = "<tool_call>day_of_week(date='2024-02-29')</tool_call>"
    FormatLabel          = { 
        param($params) 
        # Provides a human-readable label for the tool call in the UI.
        "Lookup Day for: $($params.date)" 
    }
    Execute              = { 
        param($params) 
        # The script block that executes the tool's core logic, passing parameters.
        Invoke-DayOfWeekTool -date $params.date 
    }
    ToolUseGuidanceMajor = "Always format the date argument as a string in YYYY-MM-DD format."
    ToolUseGuidanceMinor = "This tool is useful for scheduling queries or verifying historical dates, such as 'What day of the week was my birthday in 1990?'."
}