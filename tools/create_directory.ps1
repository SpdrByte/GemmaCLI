# tools/create_directory.ps1
# Responsibility: Creates a new directory (and parents if needed) at the specified path.

function Invoke-CreateDirectoryTool {
    param(
        [string]$dir_path
    )

    $dir_path = $dir_path.Trim().Trim("'").Trim('"').Replace('\\', '\')

    if ([string]::IsNullOrWhiteSpace($dir_path)) {
        return "ERROR: dir_path cannot be empty."
    }

    try {
        if (Test-Path $dir_path -PathType Container) {
            return "ERROR: Directory already exists: $dir_path"
        }

        if (Test-Path $dir_path -PathType Leaf) {
            return "ERROR: A file already exists at that path: $dir_path"
        }

        New-Item -Path $dir_path -ItemType Directory -Force -ErrorAction Stop | Out-Null

        # Verify creation succeeded and report full resolved path
        $resolved = Resolve-Path $dir_path
        return "OK: Created directory '$resolved'"

    } catch {
        return "ERROR: Could not create directory '$dir_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "create_directory"
    Behavior    = "Use this tool to create a new directory. This is useful for organizing files or preparing for a new project."
    Description = "Creates a new directory at the specified path, including any missing parent directories. Use this before writing files to a location that may not exist yet."
    Parameters  = @{
        dir_path = "string - absolute or relative Windows path to the directory to create, e.g. '.\newfolder' or 'C:\Users\kevin\Documents\project'"
    }
    Example     = "<tool_call>{ ""name"": ""create_directory"", ""parameters"": { ""dir_path"": ""./new_folder"" } }</tool_call>"
    FormatLabel = { param($params) "create_directory -> $($params.dir_path)" }
    Execute     = {
        param($params)
        Invoke-CreateDirectoryTool -dir_path $params.dir_path
    }
}