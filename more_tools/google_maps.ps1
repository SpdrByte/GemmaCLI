# ===============================================
# GemmaCLI Tool - google_maps.ps1 v0.2.0
# Responsibility: Provides real-time Google Maps data and location discovery via Gemini API.
# ===============================================

function Invoke-GoogleMapsTool {
    param(
        [string]$query,
        [string]$location_context = ""
    )

    $modelHandle = "gemini-lite"
    $modelId = Resolve-ModelId $modelHandle

    # Use dedicated tool key if available, otherwise fallback to main CLI key
    $apiKey = Get-StoredKey -keyName "google_maps"
    if (-not $apiKey) { $apiKey = $script:API_KEY }

    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=$apiKey"

    # Enable Google Maps tool
    $tools = @( @{ googleMaps = @{} } )
    
    $prompt = "Use Google Maps to answer the following query: $query"
    if ($location_context) {
        $prompt += "`nUser provided location context: $location_context"
    } else {
        $prompt += "`nNote: If the query is relative (e.g., 'near me'), and you do not have the user's location, ask for it."
    }

    $result = Invoke-SingleTurnApi `
        -uri $uri `
        -prompt $prompt `
        -spinnerLabel "Consulting Google Maps with $modelHandle ($modelId)..." `
        -backend "gemini" `
        -tools $tools

    return $result
}

$ToolMeta = @{
    Name        = "google_maps"
    Icon        = "📍"
    RendersToConsole = $false
    RequiresBilling = $true
    RequiresKey = $true
    KeyUrl      = "https://aistudio.google.com/app/apikey"
    Category    = @("Search and Discover")
    Description = "Discovers places, businesses, and points of interest using real-time Google Maps data. Use for 'near me' or specific location searches."
    Parameters  = @{ 
        query = "string - what you are looking for (e.g. 'best pizza', 'nearest park')"
        location_context = "string - optional specific city or address to center the search"
    }
    Example     = "<tool_call>{ ""name"": ""google_maps"", ""parameters"": { ""query"": ""highly rated sushi"", ""location_context"": ""Austin, TX"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.query) [$($p.location_context)]" }
    Execute     = { param($params) Invoke-GoogleMapsTool @params }
    Behavior    = "When using Google Maps, if you need the user's current location to provide an accurate 'near me' result, politely ask them for their city or zip code first."
}
