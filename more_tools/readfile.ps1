# ===============================================
# GemmaCLI Tool - readfile.ps1 v0.2.0
# Responsibility: Function to read file content + Metadata for self-registration.
# ===============================================

function Invoke-ReadFileTool {
    param([string]$file_path)
    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    try {
        $fullPath = Resolve-Path -Path $file_path -ErrorAction Stop
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            return "ERROR: Path exists but is not a file: $file_path"
        }
        Get-Content -Path $fullPath -Raw -ErrorAction Stop
    } catch {
        "ERROR: Could not read file '$file_path'. $($_.Exception.Message)"
    }
}
# Standard metadata block for registration
$ToolMeta = @{
    Name        = "readfile"
    RendersToConsole = $false
    Category    = @("System Administration", "Coding/Development", "Memory Management")
    Behavior    = "Use this tool to read the contents of a file. Before using, it is good practice to verify the file exists using the `searchdir` tool."
    Tutorial    = "I can read any text-based file. Use me when you want to see the code or content inside a file. Try: 'Read the README.md file'."
    Description = "Reads the full raw text content of any local file."
    Parameters  = @{
        file_path = "string - absolute or relative path to a file."
    }
    Example     = "<tool_call>{ ""name"": ""readfile"", ""parameters"": { ""file_path"": ""GemmaCLI_043.ps1"" } }</tool_call>"
    FormatLabel = { param($params) "readfile -> $($params.file_path)" }
    Execute     = { param($params) Invoke-ReadFileTool -file_path $params.file_path }
    ToolUseGuidanceMajor = @"
        - When to use 'readfile': Use this tool to inspect the textual content of any local file. It is essential for understanding code, configuration, logs, or any other text-based data within the project.
        - Important parameters for 'readfile': 
            - `file_path`: Provide the absolute or relative path to the file. Always verify the file's existence using `searchdir` before attempting to read it, especially if the user has not provided an explicit path.
        - Output: The tool returns the full raw text content of the file. Be prepared to handle potentially large amounts of text.
        - Error Handling: If the file does not exist, is not a file (e.g., it's a directory), or cannot be accessed, an error message will be returned.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Read the content of a file.
        - Basic use: Give the `file_path` of the file to read.
        - Important: Always check if the file exists first using `searchdir`.
"@
}
