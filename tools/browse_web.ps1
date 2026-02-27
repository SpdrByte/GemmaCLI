# tools/browse_web.ps1
# Responsibility: Fetches clean, LLM-ready markdown content from any URL using
# Jina Reader (r.jina.ai), which handles JavaScript, paywalls, and bot protection.
# No API key required for basic use.

function Invoke-BrowseWebTool {
    param(
        [string]$url
    )

    $url = $url.Trim().Trim("'").Trim('"')

    if ([string]::IsNullOrWhiteSpace($url)) {
        return "ERROR: url cannot be empty."
    }

    # Normalize URL
    if (-not $url.StartsWith("http://") -and -not $url.StartsWith("https://")) {
        $url = "https://" + $url
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Wikipedia URLs — use their official REST API instead of Jina
        if ($url -match "wikipedia\.org/wiki/(.+)") {
            $article  = $matches[1]
            $apiUrl   = "https://en.wikipedia.org/api/rest_v1/page/summary/$article"
            $response = Invoke-WebRequest -Uri $apiUrl `
                -UseBasicParsing `
                -Headers @{ "Accept" = "application/json" } `
                -TimeoutSec 30 -ErrorAction Stop
            $data    = $response.Content | ConvertFrom-Json
            $content = "TITLE: $($data.title)`n`nSUMMARY:`n$($data.extract)"
            return "URL: $url`n$("=" * 60)`n$content"
        }

        # Jina Reader prepend — returns clean markdown optimized for LLM consumption
        $encodedUrl = [System.Uri]::EscapeDataString($url)
        $jinaUrl = "https://r.jina.ai/$encodedUrl"

        $response = Invoke-WebRequest `
        -Uri $jinaUrl `
        -UseBasicParsing `
        -Headers @{ 
            "Accept" = "text/markdown" 
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            "Referer" = "https://www.google.com/"} `
        -TimeoutSec 30 `
        -ErrorAction Stop

        if ($response.StatusCode -ne 200) {
            return "ERROR: HTTP $($response.StatusCode) returned for '$url'"
        }

        $content = $response.Content.Trim()

        if ([string]::IsNullOrWhiteSpace($content)) {
            return "ERROR: No content returned for '$url'. The page may be empty or blocked."
        }

        # Hard cap to protect token budget
        $maxChars = 15000
        $truncated = $false
        if ($content.Length -gt $maxChars) {
            $content   = $content.Substring(0, $maxChars)
            $truncated = $true
        }

        $truncNote = if ($truncated) { "`n`n[TRUNCATED: content exceeded $maxChars characters]" } else { "" }

        return "URL: $url`n$("=" * 60)`n$content$truncNote"

    } catch {
        $errDetails = $_.Exception.Message
        $errType    = $_.Exception.GetType().FullName
        $errInner   = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { "none" }
        return "ERROR: Could not browse '$url'. Message: $errDetails | Type: $errType | Inner: $errInner"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "browse_web"
    Behavior    = "Use this tool to access content from a web URL. If the user provides a URL, use this tool to read its content. It is a good first step for research tasks."
    Description = "Fetches clean readable content from any URL using Jina Reader. Returns LLM-optimized markdown. Works on most sites including those with JavaScript and bot protection. Use this to read web pages, articles, or documentation when given a URL."
    Parameters  = @{
        url = "string - the full URL to browse, e.g. 'https://example.com/article'"
    }
    Example     = "<tool_call>{ ""name"": ""browse_web"", ""parameters"": { ""url"": ""https://en.wikipedia.org/wiki/PowerShell"" } }</tool_call>"
    FormatLabel = { param($params) "browse_web -> $($params.url)" }
    Execute     = {
        param($params)
        Invoke-BrowseWebTool -url $params.url
    }
}