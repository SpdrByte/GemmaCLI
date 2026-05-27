# ===============================================
# GemmaCLI Tool - search_content.ps1 
# Responsibility: Recursively searches for a regex pattern within files with strict limits.
# ===============================================

function Invoke-SearchContentTool {
    param(
        [Parameter(Mandatory=$true)]
        [string]$search_string,
        [string]$dir_path = ".",
        [string]$include = "*",
        [string]$exclude = "",
        [bool]$recursive = $true
    )

    try {
        # Resolve path to absolute
        $rootPath = Resolve-Path $dir_path -ErrorAction Stop
        
        # Define constraints
        $maxDepth = 100
        $maxResults = 100
        $results = @()

        # Gather files with recursion limit
        $gciParams = @{
            Path        = $rootPath.Path
            Recurse     = $recursive
            Depth       = $maxDepth
            File        = $true
            ErrorAction = "SilentlyContinue"
        }
        if ($include) { $gciParams["Include"] = $include }
        if ($exclude) { $gciParams["Exclude"] = $exclude }

        $files = Get-ChildItem @gciParams

        foreach ($file in $files) {
            # Use Select-String for regex search
            # We don't use -AllMatches to keep it simple, one match per line is standard
            $matches = Select-String -Path $file.FullName -Pattern $search_string -ErrorAction SilentlyContinue
            
            foreach ($m in $matches) {
                $results += [PSCustomObject]@{
                    file_path = $m.Path
                    line      = $m.LineNumber
                    column    = $m.Matches[0].Index + 1
                }

                if ($results.Count -ge $maxResults) { break }
            }
            
            if ($results.Count -ge $maxResults) { break }
        }

        $jsonResults = $results | ConvertTo-Json -Compress
        $count = $results.Count
        $status = if ($count -ge $maxResults) { " (Limit of $maxResults reached)" } else { "" }

        return "CONSOLE::Found $count matches in '$($rootPath.Path)'$status.::END_CONSOLE::$jsonResults"

    } catch {
        return "CONSOLE::Error: $($_.Exception.Message)::END_CONSOLE::[]"
    }
}

$ToolMeta = @{
    Name = "search_content"
    Icon = "🔍"
    Version = "1.1.0"
    Description = "Recursively searches for a string or regex within files in a directory (max 100 results)."
    Keywords = @("search", "find", "grep", "regex", "content", "lookup")
    Category = @("Coding")
    RendersToConsole = $false
    RequiresBilling = $false
    RequiresKey = $false
    KeyUrl = ""
    Behavior = "Use this tool to locate specific strings, function definitions, or patterns across a codebase. It honors a 100-level recursion depth and stops after 100 matches to prevent context overflow."
    Parameters = @{
        search_string = "The regular expression or string to search for."
        dir_path      = "The directory to start the search in (defaults to current)."
        include       = "Wildcard pattern for files to include (e.g., '*.ps1')."
        exclude       = "Wildcard pattern for files/folders to exclude (e.g., 'node_modules')."
        recursive     = "Toggle recursion (bool)."
    }
    Example = '<tool_call name="search_content">{"search_string": "function\\s+Get-Data", "dir_path": "./src", "include": "*.js", "recursive": false}</tool_call>'
    FormatLabel = { 
        param($res) 
        "Search: '$($res.search_string)'" 
    }
    Execute = { 
        param($params) 
        Invoke-SearchContentTool @params 
    }
    ToolUseGuidanceMajor = "Search file contents"
    ToolUseGuidanceMinor = "Performs regex search across files with a 100-match safety limit."
}