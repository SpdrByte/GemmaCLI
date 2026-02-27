# more_tools/coingecko.ps1
# Version 0.1a experimental

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
    Behavior    = "Use this tool to get the current price of a cryptocurrency. It is the best tool for financial data."
    Description = "Fetches cryptocurrency prices from the CoinGecko API."
    Parameters  = @{
        coin = "string - the ID of the cryptocurrency (e.g., bitcoin, ethereum)"
    }
    Example     = "<tool_call>{ ""name"": ""coingecko"", ""parameters"": { ""coin"": ""bitcoin"" } }</tool_call>"
    FormatLabel = { param($params) "coingecko -> $($params.coin)" }
    Execute     = { param($params) Invoke-CoinGeckoTool @params }
}
