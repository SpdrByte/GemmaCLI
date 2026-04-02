# GemmaCLI Tool - searchdir.ps1 v0.2.0
# Responsibility: Searches a directory for files/folders matching a pattern.
# ===============================================

function Invoke-SearchDirTool {
    param(
        [string]$dir_path = ".",
        [string]$search_string,
        [switch]$recursive,
        [string]$include = "",
        [string]$exclude
    )

    $dir_path = $dir_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    if ([string]::IsNullOrWhiteSpace($dir_path)) { $dir_path = "." }

    try {
        $params = @{
            Path      = $dir_path
            Filter    = $search_string
            Recurse   = $recursive
            ErrorAction = "Stop"
        }
        if (-not [string]::IsNullOrWhiteSpace($include) -and $include -ne "*") { $params.Include = $include }
        if ($exclude) { $params.Exclude = $exclude }
        
        $results = Get-ChildItem @params
        $fileList = $results | ForEach-Object { $_.FullName }

        if ($fileList.Count -eq 0) {
            return "No files or directories found matching '$search_string' in '$dir_path'."
        }

        return $fileList -join "`n"

    } catch {
        return "ERROR: Could not search directory '$dir_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "searchdir"
    RendersToConsole = $false
    Category    = @("System Administration", "Search and Discover")
    Behavior    = "Use this tool to find files or directories. It is useful for exploring the file system and locating specific files."
    Tutorial    = "I can find files and folders anywhere on your system. Use me to explore before you read or edit. Try: 'Search for all .md files'."
    Description = "Searches a directory for files and folders matching a specific name or wildcard pattern. Can search recursively."
    Parameters  = @{
        dir_path      = "string - the directory to start the search from (default: current directory)"
        search_string = "string - the filename or wildcard pattern ONLY, never include a directory path or backslash here (e.g., 'read.txt', '*.txt', 'project*'). Put the directory in dir_path instead."
        recursive     = "switch - if present, searches all subdirectories"
        include       = "string - wildcard pattern to include in the results (e.g., '*.ps1')"
        exclude       = "string - wildcard pattern to exclude from the results (e.g., '*.log')"
    }
    Example     = "<tool_call>{ ""name"": ""searchdir"", ""parameters"": { ""dir_path"": ""."", ""search_string"": ""*.md"", ""recursive"": true } }</tool_call>"
    FormatLabel = { param($params) "🔍 Searchdir -> $($params.search_string) in $($params.dir_path)" }
    Execute     = { param($params) Invoke-SearchDirTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'searchdir': Use this tool to verify the existence of files or directories before attempting to 'readfile' or 'view_image', especially if the user has not provided an explicit path. This helps adhere to the 'Strict Evidence Policy'.
        - Important parameters for 'searchdir': 
            - `dir_path`: Always specify a directory path. Defaults to the current directory ('.').
            - `search_string`: This parameter MUST ONLY be the filename or a wildcard pattern (e.g., '*.txt', 'config*'). NEVER include a directory path or backslashes within `search_string`. Put the directory part in `dir_path` instead.
        - Post-search action: If 'searchdir' does not return the expected file or directory, always ask the user for the correct path rather than guessing or proceeding with a non-existent path.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Find files or folders by name.
        - Basic use: Provide the directory (`dir_path`) and the exact file name (`search_string`).
        - Important: If the tool doesn't find the file, ask the user for help.
"@
}
