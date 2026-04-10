# ===============================================
# GemmaCLI Tool - google_search.ps1 v0.2.0
# Responsibility: Provides real-time Google Search results via Gemini API grounding.
# ===============================================

function Invoke-GoogleSearchTool {
    param([string]$query)

    $modelHandle = "gemini-lite"
    $modelId = Resolve-ModelId $modelHandle
    
    # Use dedicated tool key if available, otherwise fallback to main CLI key
    $apiKey = Get-StoredKey -keyName "google_search"
    if (-not $apiKey) { $apiKey = $script:API_KEY }
    
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=$apiKey"

    $tools = @( @{ google_search = @{} } )
    
    $result = Invoke-SingleTurnApi `
        -uri $uri `
        -prompt "Perform a Google Search for: $query`nReturn a detailed answer based on the search results." `
        -spinnerLabel "Searching Google with $modelHandle ($modelId)..." `
        -backend "gemini" `
        -tools $tools

    return $result
}

$ToolMeta = @{
    Name        = "google_search"
    Icon        = "🔍"
    RendersToConsole = $false
    RequiresBilling = $true
    RequiresKey = $true
    KeyUrl      = "https://aistudio.google.com/app/apikey"
    Category    = @("Search and Discover")
    Description = "Performs a real-time Google Search to find current information, facts, or news."
    Parameters  = @{ query = "string - the search query or question" }
    Example     = "<tool_call>{ ""name"": ""google_search"", ""parameters"": { ""query"": ""latest news about Gemma 3 model"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.query)" }
    Execute     = { param($params) Invoke-GoogleSearchTool @params }
}
