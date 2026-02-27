# more_tools/http_get.ps1
# Version 0.1a experimental

function Invoke-HttpGetTool {
    param([string]$url)

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        $content = if ($response -is [PSCustomObject] -or $response -is [hashtable] -or $response -is [System.Collections.IEnumerable] -and $response -isnot [string]) {
            $response | ConvertTo-Json -Depth 10
        } else {
            $response
        }

        if ($null -ne $content -and $content.Length -gt 15000) {
            return $content.Substring(0, 15000) + "`n... [OUTPUT TRUNCATED FOR BREVITY]"
        }
        return $content
    } catch {
        return "ERROR: Failed to get content from URL: $url. Error: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "http_get"
    Behavior    = "Use this tool to make a simple GET request to a URL and retrieve the raw content. For reading web pages, `browse_web` is preferred as it returns cleaner, LLM-ready markdown."
    Description = "Performs an HTTP GET request to a URL, returning the raw content."
    Parameters  = @{
        url = "string - the URL to fetch"
    }
    Example     = "<tool_call>{ ""name"": ""http_get"", ""parameters"": { ""url"": ""https://api.github.com/users/powershell"" } }</tool_call>"
    FormatLabel = { param($params) "http_get -> $($params.url)" }
    Execute     = { param($params) Invoke-HttpGetTool @params }
}
