# ===============================================
# GemmaCLI Tool - remember.ps1 v0.1.1
# Responsibility: Appends a single fact (with category and date) to a JSON file
# for long-term memory recall in future sessions.
# ===============================================

function Invoke-RememberTool {
    param(
        [string]$fact,
        [string]$category
    )

    $fact = $fact.Trim()
    $category = $category.Trim()

    if ([string]::IsNullOrWhiteSpace($fact)) {
        return "ERROR: fact cannot be empty."
    }
    if ([string]::IsNullOrWhiteSpace($category)) {
        return "ERROR: category cannot be empty."
    }

    try {
        $memoryFile = Join-Path $env:APPDATA "GemmaCLI/memory.json"
        $memories = @()
        if (Test-Path $memoryFile) {
            $memories = Get-Content $memoryFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $memories -and $memories -isnot [array]) { $memories = @($memories) }
        }
        if ($null -eq $memories) { $memories = @() }

        # Prevent duplicate entries
        if ($null -ne $memories.fact -and $memories.fact -contains $fact) {
            return "OK: I have already remembered that fact."
        }

        $newMemory = [PSCustomObject]@{
            date     = Get-Date -Format "yyyy-MM-dd HH:mm"
            category = $category
            fact     = $fact
        }
        $memories += $newMemory

        # Sort by date, then category
        $sorted = $memories | Sort-Object -Property date, category
        Set-Content -Path $memoryFile -Value ($sorted | ConvertTo-Json -Depth 3) -Encoding UTF8 -Force

        return "OK: I will remember that. (Category: $category)"
    } catch {
        return "ERROR: Could not remember fact. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "remember"
    RendersToConsole = $false
    Category    = @("Memory Management")
    Behavior    = "Use this tool to memorize a specific piece of information the user tells you. This is for long-term memory across sessions."
    Description = "Remembers a single fact and saves it to a local memory file. Use this when the user explicitly tells you to remember something about them or their preferences."
    Parameters  = @{
        fact     = "string - the specific fact to remember, e.g. 'The user's favorite color is blue.'"
        category = "string - a category for the fact, e.g. 'personal', 'project', 'preference'"
    }
    Example     = "<tool_call>{ ""name"": ""remember"", ""parameters"": { ""fact"": ""The user's favorite programming language is PowerShell."", ""category"": ""preference"" } }</tool_call>"
    FormatLabel = { param($params) "🧠 Remember -> $($params.fact)" }
    Execute     = { param($params) Invoke-RememberTool -fact $params.fact -category $params.category }
    ToolUseGuidanceMajor = @"
        - When to use 'remember': Use this tool to store specific, user-related facts or preferences for long-term recall across sessions. This is critical for personalizing future interactions and streamlining workflows based on user's explicit statements or inferred preferences.
        - Important parameters for 'remember': 
            - `fact`: A concise, self-contained statement of the information to remember. Avoid lengthy descriptions; focus on the core fact.
            - `category`: A relevant category to help organize and retrieve facts (e.g., 'personal', 'project', 'preference', 'configuration').
        - Proactive Use: Do not wait for the user to explicitly ask you to remember something if it's a clear, concise piece of information that would enhance future interactions.
        - Avoid Duplicates: The tool attempts to prevent duplicate entries, but ensure the `fact` is distinct enough.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Save important user facts for later.
        - Basic use: Provide the `fact` and a `category` for it.
        - Important: Only save things the user tells you to remember about them.
"@
}
