# more_tools/brave_search.ps1
# Version 0.1a exoerimental

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
    FormatLabel = { param($params) "brave_search -> $($params.query)" }
    Execute     = { param($params) Invoke-BraveSearchTool @params }
}
