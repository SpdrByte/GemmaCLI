# tools/readfile.ps1
# Responsibility: Function to read file content + Metadata for self-registration.

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
    Behavior    = "Use this tool to read the contents of a file. Before using, it is good practice to verify the file exists using the `searchdir` tool."
    Description = "Reads the full raw text content of any local file."
    Parameters  = @{
        file_path = "string - absolute or relative path to a file."
    }
    Example     = "<tool_call>{ ""name"": ""readfile"", ""parameters"": { ""file_path"": ""GemmaCLI_043.ps1"" } }</tool_call>"
    FormatLabel = { param($params) "readfile -> $($params.file_path)" }
    Execute     = { param($params) Invoke-ReadFileTool -file_path $params.file_path }
}
