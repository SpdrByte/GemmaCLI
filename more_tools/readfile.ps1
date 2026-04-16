# ===============================================
# GemmaCLI Tool - readfile.ps1 v1.0.4
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

        $fileInfo = Get-Item $fullPath
        # If file is larger than 1MB, auto-read the first 20,000 characters
        if ($fileInfo.Length -gt 1MB) {
            $reader = [System.IO.StreamReader]::new($fullPath)
            $charBuffer = New-Object char[] 20000
            $charsRead = $reader.Read($charBuffer, 0, 20000)
            $reader.Close()
            $content = New-Object string($charBuffer, 0, $charsRead)
            return "[TRUNCATED: File size exceeds 1MB. Showing first 20,000 characters]`n`n$content"
        } else {
            # Read full content for smaller files
            return Get-Content -Path $fullPath -Raw -ErrorAction Stop
        }
    } catch {
        "ERROR: Could not read file '$file_path'. $($_.Exception.Message)"
    }
}

# Standard metadata block for registration
$ToolMeta = @{
    Name        = "readfile"
    Icon        = "📖"
    RendersToConsole = $false
    Interactive = $false
    Category    = @("System Administration", "Coding/Development", "Memory Management")
    Behavior    = "Use this tool to read the contents of a file. Before using, it is good practice to verify the file exists using the `searchdir` tool."
    Tutorial    = "I can read any text-based file. Use me when you want to see the code or content inside a file. Try: 'Read the README.md file'."
    Description = "Reads the full raw text content of any local file."
    Keywords    = @("Readfile", "Read", "File", "View", "Get")
    Parameters  = @{
        file_path = "string - absolute or relative path to a file."
    }
    Example     = "<tool_call>{ ""name"": ""readfile"", ""parameters"": { ""file_path"": ""GemmaCLI_043.ps1"" } }</tool_call>"
    FormatLabel = { param($params) "$($params.file_path)" }
    Execute     = { param($params) Invoke-ReadFileTool -file_path $params.file_path }
    ToolUseGuidanceMajor = @"
        - When to use 'readfile': Use this tool to inspect the textual content of any local file. It is essential for understanding code, configuration, logs, or any other text-based data within the project.
        - Important parameters for 'readfile': 
            - `file_path`: Provide the absolute or relative path to the file. Always verify the file's existence using `searchdir` before attempting to read it, especially if the user has not provided an explicit path.
        - Output: The tool returns the full raw text content of the file. If the file exceeds 1MB, it will automatically truncate and return the first 20,000 characters to protect context limits.
        - Error Handling: If the file does not exist, is not a file (e.g., it's a directory), or cannot be accessed, an error message will be returned.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Read the content of a file safely.
        - Basic use: Give the `file_path` of the file to read.
        - Important: Always check if the file exists first using `searchdir`.
"@
}