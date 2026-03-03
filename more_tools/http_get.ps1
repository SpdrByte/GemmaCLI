# ===============================================
# GemmaCLI Tool - http_get.ps1 v0.1.1
# Responsibility: Get URL
# ===============================================

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

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "http_get"
    Behavior    = "Use this tool to make a simple GET request to a URL and retrieve the raw content. For reading web pages, `browse_web` is preferred as it returns cleaner, LLM-ready markdown."
    Description = "Performs an HTTP GET request to a URL, returning the raw content."
    Parameters  = @{
        url = "string - the URL to fetch"
    }
    Example     = "<tool_call>{ ""name"": ""http_get"", ""parameters"": { ""url"": ""https://api.github.com/users/powershell"" } }</tool_call>"
    FormatLabel = { param($params) "🌐 http_get -> $($params.url)" }
    Execute     = { param($params) Invoke-HttpGetTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'http_get': Use this tool to perform a simple HTTP GET request to a URL and retrieve its raw content. It's suitable for APIs or specific files, but for general web pages, `browse_web` is usually preferred for cleaner, LLM-ready markdown.
        - Important parameters for 'http_get': 
            - `url`: Provide the full and valid URL for the GET request.
        - Output: The tool returns the raw content, which might be JSON, XML, plain text, or other formats. Be prepared to parse or process this raw output. The output might also be truncated for brevity.
        - Error Handling: If the request fails (e.g., network error, invalid URL, HTTP error status), an error message will be returned.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Get raw content from a web address.
        - Basic use: Provide the full web address (`url`).
        - Important: Use `browse_web` for regular web pages, this is for raw data.
"@
}
