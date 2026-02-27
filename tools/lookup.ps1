# tools/lookup.ps1
# Responsibility: Query the DuckDuckGo Instant Answer API for current real-world
# facts that may have changed since the model's training cutoff.
# Best used for: software versions, political leaders, current record holders,
# CEO/leadership of major organizations, and other "what is current X" queries.
# NOT suitable for: recent news, sports scores, stock prices, or niche topics.

function Invoke-LookupTool {
    param([string]$query)

    $query = $query.Trim().Trim("'").Trim('"')

    if ([string]::IsNullOrWhiteSpace($query)) {
        return "ERROR: query cannot be empty."
    }

    try {
        $encoded  = [System.Uri]::EscapeDataString($query)
        $url      = "https://api.duckduckgo.com/?q=$encoded&format=json&no_redirect=1&no_html=1&skip_disambig=1"

        $response = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop

        $lines = @()
        $lines += "LOOKUP QUERY: $query"
        $lines += "=" * 60

        # -- Direct answer: best signal for version numbers, conversions, simple facts --
        if ($response.Answer) {
            $lines += ""
            $lines += "DIRECT ANSWER:"
            $lines += "  $($response.Answer)"
        }

        # -- Abstract: Wikipedia summary, good for current leadership / org facts --
        if ($response.AbstractText) {
            $lines += ""
            $lines += "SUMMARY ($($response.AbstractSource)):"
            $lines += "  $($response.AbstractText)"
            if ($response.AbstractURL) {
                $lines += "  Source: $($response.AbstractURL)"
            }
        }

        # -- Infobox: structured key/value, often has version, DOB, title, founded etc --
        if ($response.Infobox.content -and $response.Infobox.content.Count -gt 0) {
            $lines += ""
            $lines += "CURRENT FACTS:"
            $shown = 0
            foreach ($item in $response.Infobox.content) {
                if ($shown -ge 10) { break }
                if ($item.label -and $item.value) {
                    $lines += "  $($item.label): $($item.value)"
                    $shown++
                }
            }
        }

        # -- Related topics: supporting context, capped at 3 to avoid noise --
        if ($response.RelatedTopics -and $response.RelatedTopics.Count -gt 0) {
            $topicsAdded = 0
            $topicLines  = @()
            foreach ($topic in $response.RelatedTopics) {
                if ($topicsAdded -ge 3) { break }
                if ($topic.Text) {
                    $topicLines += "  - $($topic.Text)"
                    $topicsAdded++
                }
            }
            if ($topicLines.Count -gt 0) {
                $lines += ""
                $lines += "RELATED:"
                $lines += $topicLines
            }
        }

        # -- Definition fallback --
        if ($response.Definition) {
            $lines += ""
            $lines += "DEFINITION ($($response.DefinitionSource)):"
            $lines += "  $($response.Definition)"
        }

        # -- Nothing useful returned --
        if ($lines.Count -le 2) {
            return "LOOKUP: No current data found for '$query'. This query may be too recent, too niche, or not well-represented in public knowledge bases. Rely on training knowledge and note uncertainty to the user."
        }

        return $lines -join "`n"

    } catch {
        return "ERROR: Lookup failed. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "lookup"
    Behavior    = "Use this tool for quick lookups of factual, time-sensitive information. It's best for questions about current events, versions, or leaders. For in-depth research, prefer `brave_search`."
    Description = "Looks up current real-world facts that may have changed since training. Use when the user asks about 'latest', 'current', 'newest', 'who is the president/CEO of', or any versioned or time-sensitive fact. Not suitable for recent news, sports scores, or financial data."
    Parameters  = @{
        query = "string - the factual question to look up, e.g. 'latest Python version' or 'current Prime Minister of UK'"
    }
    Example     = "<tool_call>{ ""name"": ""lookup"", ""parameters"": { ""query"": ""latest Python version"" } }</tool_call>"
    FormatLabel = { param($params) "lookup -> $($params.query)" }
    Execute     = {
        param($params)
        Invoke-LookupTool -query $params.query
    }
}