# tools/remember.ps1
# Responsibility: Appends a single fact (with category and date) to a JSON file
# for long-term memory recall in future sessions.

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
    Behavior    = "Use this tool to memorize a specific piece of information the user tells you. This is for long-term memory across sessions."
    Description = "Remembers a single fact and saves it to a local memory file. Use this when the user explicitly tells you to remember something about them or their preferences."
    Parameters  = @{
        fact     = "string - the specific fact to remember, e.g. 'The user's favorite color is blue.'"
        category = "string - a category for the fact, e.g. 'personal', 'project', 'preference'"
    }
    Example     = "<tool_call>{ ""name"": ""remember"", ""parameters"": { ""fact"": ""The user's favorite programming language is PowerShell."", ""category"": ""preference"" } }</tool_call>"
    FormatLabel = { param($params) "remember -> $($params.fact)" }
    Execute     = { param($params) Invoke-RememberTool -fact $params.fact -category $params.category }
}
