# GemmaCLI Tool - writefile.ps1 v0.3.0
# Responsibility: Writes content to a file. Includes overwrite protection.
# ===============================================

function Invoke-WriteFileTool {
    param(
        [string]$file_path,
        [string]$content,
        [bool]$overwrite = $false
    )

    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    # ── Overwrite Protection ─────────────────────────────────────────────────
    if (Test-Path $file_path -PathType Leaf) {
        if (-not $overwrite) {
            return "ERROR: File '$file_path' already exists. Overwrite protection is ACTIVE. You MUST ask the user: 'The file already exists, do you want to overwrite it?' If they say yes, call this tool again with 'overwrite': true."
        }
    }

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $file_path -Parent
        if (![string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        # Use -Force only if $overwrite is true to handle read-only files
        $scParams = @{
            Path     = $file_path
            Value    = $content
            Encoding = "UTF8"
            ErrorAction = "Stop"
        }
        if ($overwrite) { $scParams.Force = $true }

        Set-Content @scParams

        $resolved = Resolve-Path $file_path
        $charCount = $content.Length
        $status = if ($overwrite) { "Overwrote" } else { "Wrote" }
        return "OK: $status $charCount characters to '$resolved'"
    } catch {
        return "ERROR: Could not write to file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "writefile"
    Icon        = "📄"
    RendersToConsole = $false
    Category    = @("System Administration", "Coding/Development")
    Behavior    = "Use this tool to write content to a file. It has overwrite protection. If the file exists, the tool will fail and tell you to ask the user for permission. Once permission is granted, set 'overwrite' to true."
    Tutorial    = "I can create files for you. If a file already exists, I'll protect it and ask you to get the user's permission before I overwrite it! Try: 'Write 'Hello' to test.txt'."
    Description = "Writes or overwrites a file. Includes safety protection to prevent accidental data loss."
    Parameters  = @{
        file_path = "string - the path to the file to write."
        content   = "string - the text content to write."
        overwrite = "boolean - set to true ONLY after the user has explicitly given permission to overwrite an existing file. Default: false."
    }
    Example     = "<tool_call>{ ""name"": ""writefile"", ""parameters"": { ""file_path"": ""hello.txt"", ""content"": ""Hello!"", ""overwrite"": false } }</tool_call>"
    FormatLabel = { param($params) 
        $warn = if ($params.overwrite) { " (OVERWRITE)" } else { "" }
        "$($params.file_path)$warn" 
    }
    Execute     = {
        param($params)
        Invoke-WriteFileTool @params
    }
    ToolUseGuidanceMajor = @"
        - When to use 'writefile': Use this tool to write a file. Verify the existence of directory attempting to writefile, especially if the user has not provided an explicit path. This helps adhere to the 'Strict Evidence Policy'.
        - Important parameters for 'writefile': 
        - `file_path`: Always specify a file path.  ('.') Defaults to the current directory.
        - `content`: The exact text to be written into the file. 
        - Caution: This tool will overwrite a file if it already exists. Ensure this is the intended action. 
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Create or update a file.                                                                                                                                         │
        - Basic use: Provide the file's path (`file_path`) and the text (`content`) to write.
        - Important: Caution! This tool will overwrite existing files. 
"@

}
