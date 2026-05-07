# ===============================================
# GemmaCLI Tool - get_tool.ps1 v1.3.1
# Responsibility: Searches the reserve (@more_tools) for a tool and activates it.
# Supports semantic search (Name, Description, Keywords) and tool-swapping at the limit.
# ===============================================

# Discover absolute path for clickable link
$toolsWikiPath = Join-Path $scriptDir "TOOLS.html"

function Invoke-GetTool {
    param(
        [string]$keyword,
        [string]$tool_name,
        [string]$swap_tool
    )

    $scriptRootDir = Get-Location
    $moreToolsDir = Join-Path $scriptRootDir "more_tools"
    $toolsDir = Join-Path $scriptRootDir "tools"

    # --- STEP 1: ACTIVATION (If tool_name is provided) ---
    if (-not [string]::IsNullOrWhiteSpace($tool_name)) {
        # Verify the tool exists in more_tools
        if (-not (Test-Path (Join-Path $moreToolsDir "$tool_name.ps1"))) {
            return "ERROR: Tool '$tool_name' not found in the reserve. Use the 'keyword' parameter to search first."
        }

        # Check Tool Limits
        $limit = $script:TOOL_LIMITS[$script:MODEL]
        if ($null -eq $limit) { $limit = 10 }
        $activeCount = $script:TOOLS.Count

        if ($activeCount -ge $limit -and [string]::IsNullOrWhiteSpace($swap_tool)) {
            return "LIMIT_REACHED: I am at my tool limit ($activeCount/$limit). Please call 'get_tool' again with 'tool_name'='$tool_name' AND 'swap_tool'='(name of active tool to disable)'."
        }

        # Handle Swap
        $swapResult = ""
        if (-not [string]::IsNullOrWhiteSpace($swap_tool)) {
            if ($script:TOOLS.ContainsKey($swap_tool)) {
                try {
                    Move-Item -Path (Join-Path $toolsDir "$swap_tool.ps1") -Destination $moreToolsDir -Force
                    $swapResult = " (Swapped out '$swap_tool')"
                } catch {
                    return "ERROR: Failed to swap out tool '$swap_tool': $($_.Exception.Message)"
                }
            } else {
                return "ERROR: Tool '$swap_tool' is not currently active. I cannot swap it out."
            }
        }

        # Activate
        try {
            $meta = $script:TOOL_CACHE[$tool_name]
            Draw-Box @(
                "Acquiring Capability...",
                "Tool:    $($meta.Icon) $tool_name",
                "Status:  Refreshing system prompt..."
            ) -Title "Gemma Expansion" -Color Cyan

            Move-Item -Path (Join-Path $moreToolsDir "$tool_name.ps1") -Destination $toolsDir -Force
            Update-SystemPrompt
            
            return "CONSOLE::$($meta.Icon) ACTIVATED: $tool_name::END_CONSOLE::OK: Tool '$tool_name' has been activated$swapResult. It is now available in your system prompt. Proceed with user request."
        } catch {
            return "ERROR: Failed to activate tool '$tool_name': $($_.Exception.Message)"
        }
    }

    # --- STEP 2: SEARCH (If only keyword is provided) ---
    if (-not [string]::IsNullOrWhiteSpace($keyword)) {
        $matches = @()
        # Split keyword into terms (e.g., "file write" -> "file", "write")
        $terms = $keyword -split '\s+' | Where-Object { $_.Length -gt 1 }
        
        foreach ($name in $script:TOOL_CACHE.Keys) {
            if (-not (Test-Path (Join-Path $moreToolsDir "$name.ps1"))) { continue }
            
            $meta = $script:TOOL_CACHE[$name]
            $score = 0
            
            # Exact name match is highest priority
            if ($name -ieq $keyword) { $score += 100 }
            
            foreach ($term in $terms) {
                if ($name -ilike "*$term*") { $score += 40 }
                if ($meta.Description -ilike "*$term*") { $score += 20 }
                if ($meta.Keywords) {
                    foreach ($kw in $meta.Keywords) {
                        if ($kw -ilike "*$term*") { $score += 30 }
                    }
                }
            }

            if ($score -gt 0) {
                # Cap score at 100
                $finalScore = [math]::Min($score, 100)
                $matches += [PSCustomObject]@{ Name = $name; Score = $finalScore; Icon = $meta.Icon; Desc = $meta.Description }
            }
        }

        if ($matches.Count -eq 0) {
            return "NOT_FOUND: No tools in the reserve match '$keyword'. Call 'get_tool' again with different keywords or check TOOLS.html."
        }

        $results = @("RESERVE SEARCH RESULTS FOR '$keyword':", "")
        foreach ($m in ($matches | Sort-Object Score -Descending | Select-Object -First 5)) {
            $results += "$($m.Icon) $($m.Name) ($($m.Score)%)"
            $results += "   > $($m.Desc)"
            $results += ""
        }
        $results += "STEP 2: ACTIVATE. Once you identify the correct tool, call 'get_tool' again with the 'tool_name' parameter to enable it. (e.g., tool_name='writefile')."
        $results += "LIMITS: If you are at your tool limit, you MUST also provide 'swap_tool' with the name of an active tool to disable."

        return $results -join "`n"
    }

    return "ERROR: You must provide either a 'keyword' to search or a 'tool_name' to activate."
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "get_tool"
    Icon        = "✨"
    Interactive = $true
    Behavior    = "Use this tool to discover and activate capabilities from the reserve (@more_tools). 
    CRITICAL: If you need a capability (like writing a file, searching the web, or any other task) and you do not see a SPECIFIC tool for it in your prompt, you MUST search for it here. DO NOT attempt to guess parameters for unrelated tools (e.g., do not use resize_image to write text).
    
    To begin, call with 'keyword' (e.g. 'file write', 'web search') to find matching tools.
    
    WIKI: If the user asks for a full list of all 60+ tools or a wiki, you MUST provide this exact absolute path as a clickable link: $toolsWikiPath"
    
    Description = "Searches for and activates tools from the reserve (more_tools)."
    Keywords    = @("activate", "enable", "upgrade", "capability", "skill", "plugin", "module", "find", "search")
    Parameters  = @{
        keyword   = "string - optional. Keywords to search the reserve for (Step 1)."
        tool_name = "string - optional. The exact name of the tool to activate (Step 2)."
        swap_tool = "string - optional. The name of an active tool to disable if the limit is reached (Step 2)."
    }
    Example     = "STEP 1: <tool_call>{ ""name"": ""get_tool"", ""parameters"": { ""keyword"": ""audio"" } }</tool_call>`nSTEP 2: <tool_call>{ ""name"": ""get_tool"", ""parameters"": { ""tool_name"": ""audioedit"" } }</tool_call>"
    FormatLabel = { param($p) if($p.tool_name){ "✨ activate -> $($p.tool_name)" } else { "🔍 search -> $($p.keyword)" } }
    Execute     = { param($params) Invoke-GetTool @params }
}
