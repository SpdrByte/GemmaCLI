# tools/writefile.ps1
# Responsibility: Writes content to a file, creating it if it doesn't exist.

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
    Behavior    = "Use this tool to write content to a file. It can create a new file or overwrite an existing one. This is the primary tool for creating or modifying files."
    Description = "Writes or overwrites the entire content of a file. Creates the file and any necessary parent directories if they do not exist."
    Parameters  = @{
        file_path = "string - the absolute or relative path to the file to write, e.g. './src/new_file.txt' or 'C:/Users/kevin/Documents/output.log'"
        content   = "string - the text content to write to the file"
    }
    Example     = "<tool_call>{ ""name"": ""writefile"", ""parameters"": { ""file_path"": ""hello.txt"", ""content"": ""Hello, World!"" } }</tool_call>"
    FormatLabel = { param($params) "writefile -> $($params.file_path)" }
    Execute     = {
        param($params)
        Invoke-WriteFileTool -file_path $params.file_path -content $params.content
    }
}
