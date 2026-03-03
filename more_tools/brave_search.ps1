# ===============================================
# GemmaCLI Tool - brave_search.ps1 v0.1.1
# Responsibility: Web search using Brave search engine
# ===============================================

function Invoke-BraveSearchTool {
    param([string]$query)

    if (-not $env:BRAVE_API_KEY) {
        return "ERROR: Brave API key not found in environment variable `$env:BRAVE_API_KEY`."
    }

    try {
        $headers = @{
            "Accept" = "application/json"
            "X-Subscription-Token" = $env:BRAVE_API_KEY
        }
        $encodedQuery = [uri]::EscapeDataString($query)
        $uri = "https://api.search.brave.com/res/v1/web/search?q=$encodedQuery"
        
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
        
        if ($null -eq $response.web -or $null -eq $response.web.results) {
            return "No search results found for: $query"
        }

        $results = @()
        foreach ($res in $response.web.results) {
            $results += "TITLE: $($res.title)`nURL: $($res.url)`nDESCRIPTION: $($res.description)`n---"
        }

        return $results -join "`n"
    } catch {
        return "ERROR: Failed to perform Brave search. Error: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "brave_search"
    Behavior    = "Use this tool for in-depth web research. It provides a list of search results with summaries."
    Description = "A privacy-first web search using the Brave Search API."
    Parameters  = @{
        query = "string - the search query"
    }
    Example     = "<tool_call>{ ""name"": ""brave_search"", ""parameters"": { ""query"": ""latest features in PowerShell 7"" } }</tool_call>"
    FormatLabel = { param($params) "🦁 Brave Search -> $($params.query)" }
    Execute     = { param($params) Invoke-BraveSearchTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'brave_search': Use this tool for general web searches, especially when current information or external knowledge is required. It provides a list of search results including titles, URLs, and descriptions.
        - Important parameters for 'brave_search': 
            - `query`: Provide a clear and concise search query that directly addresses the information needed.
        - Integration with other tools: The URLs retrieved from `brave_search` can be used as input for the `browse_web` tool to fetch the content of specific pages.
        - If no results are found: Refine the `query` and try again, or inform the user.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Search the web for information.
        - Basic use: Provide a simple, direct question or keywords as the `query`.
        - Important: This tool connects to the internet to find information.
"@
}
