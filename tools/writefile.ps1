# ===============================================
# GemmaCLI Tool - writefile.ps1 v0.1.1
# Responsibility: Writes content to a file, creating it if it doesn't exist
# ===============================================

function Invoke-WriteFileTool {
    param(
        [string]$file_path,
        [string]$content
    )

    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    try {
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $file_path -Parent
        if (![string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        Set-Content -Path $file_path -Value $content -Encoding UTF8 -Force -ErrorAction Stop

        $resolved = Resolve-Path $file_path
        $charCount = $content.Length
        return "OK: Wrote $charCount characters to '$resolved'"
    } catch {
        return "ERROR: Could not write to file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "writefile"
    RendersToConsole = $false
    Category    = @("System Administration", "Coding/Development")
    Behavior    = "Use this tool to write content to a file. It can create a new file or overwrite an existing one. This is the primary tool for creating or modifying files."
    Description = "Writes or overwrites the entire content of a file. Creates the file and any necessary parent directories if they do not exist."
    Parameters  = @{
        file_path = "string - the absolute or relative path to the file to write, e.g. './src/new_file.txt' or 'C:/Users/kevin/Documents/output.log'"
        content   = "string - the text content to write to the file"
    }
    Example     = "<tool_call>{ ""name"": ""writefile"", ""parameters"": { ""file_path"": ""hello.txt"", ""content"": ""Hello, World!"" } }</tool_call>"
    FormatLabel = { param($params) "📄Writefile -> $($params.file_path)" }
    Execute     = {
        param($params)
        Invoke-WriteFileTool -file_path $params.file_path -content $params.content
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
