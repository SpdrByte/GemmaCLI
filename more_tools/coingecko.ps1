# ===============================================
# GemmaCLI Tool - coingecko.ps1 v0.2.0
# Responsibility: Fetch coin data
# ===============================================

function Invoke-CoinGeckoTool {
    param([string]$coin)

    try {
        $coinId = $coin.ToLower().Trim()
        $uri = "https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd"
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
        
        if ($null -ne $response -and $null -ne $response.$coinId -and $null -ne $response.$coinId.usd) {
            return "The current price of $coinId is $($response.$coinId.usd) USD."
        } else {
            return "ERROR: Could not retrieve price for '$coinId'. It may be an invalid coin name."
        }
    } catch {
        return "ERROR: Failed to contact CoinGecko API. Error: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "coingecko"
    Icon        = "🦎"
    RendersToConsole = $false
    Category    = @("Search and Discover")
    Behavior    = "Use this tool to get the current price of a cryptocurrency. It is the best tool for financial data."
    Description = "Fetches cryptocurrency prices from the CoinGecko API."
    Parameters  = @{
        coin = "string - the ID of the cryptocurrency (e.g., bitcoin, ethereum)"
    }
    Example     = "<tool_call>{ ""name"": ""coingecko"", ""parameters"": { ""coin"": ""bitcoin"" } }</tool_call>"
    FormatLabel = { param($params) "$($params.coin)" }
    Execute     = { param($params) Invoke-CoinGeckoTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'coingecko': Use this tool to retrieve the current price of a specific cryptocurrency in USD. This is useful for answering questions about crypto market values.
        - Important parameters for 'coingecko': 
            - `coin`: Provide the exact ID of the cryptocurrency (e.g., 'bitcoin', 'ethereum'). It must be a valid CoinGecko ID.
        - Error Handling: If the tool returns an error or "Could not retrieve price", it likely means the provided `coin` ID is incorrect or not supported. Inform the user.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Get cryptocurrency prices.
        - Basic use: Provide the exact name of the `coin` (e.g., 'bitcoin').
        - Important: The coin name must be correct for the tool to work.
"@
}
