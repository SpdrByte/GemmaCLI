# ===============================================
# GemmaCLI Tool - move_file.ps1 v0.2.0
# Responsibility: Move file to different directory
# ===============================================

function Invoke-MoveFileTool {
    param(
        [string]$source,
        [string]$destination
    )

    try {
        if (-not (Test-Path $source)) {
            return "ERROR: Source path '$source' does not exist."
        }
        Move-Item -Path $source -Destination $destination -ErrorAction Stop
        return "OK: Moved file from '$source' to '$destination'"
    } catch {
        return "ERROR: Failed to move file. Error: $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "move_file"
    Icon        = "📂"
    RendersToConsole = $false
    Category    = @("System Administration")
    Behavior    = "Use this tool to move or rename a file. This is the primary tool for file organization."
    Description = "Moves or renames a file."
    Parameters  = @{
        source      = "string - the path to the file to move"
        destination = "string - the new path for the file"
    }
    Example     = '<tool_call>{ "name": "move_file", "parameters": { "source": "./old/file.txt", "destination": "./new/file.txt" } }</tool_call>'
    FormatLabel = { param($params) "$($params.source) to $($params.destination)" }
    Execute     = { param($params) Invoke-MoveFileTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'move_file': Use this tool to relocate a file from a `source` path to a `destination` path, or to rename a file by specifying a new file name in the `destination` path. This is a primary tool for file organization.
        - Important parameters for 'move_file': 
            - `source`: The full path to the file you intend to move or rename. Verify its existence before attempting the move.
            - `destination`: The new full path for the file. This can be a new directory, a new file name, or both. If the destination directory does not exist, an error will occur.
        - Caution: If a file already exists at the `destination` path, it will be overwritten. Confirm this is the desired behavior.
        - Verification: After moving, consider using `searchdir` to confirm the file's new location or absence from the old location.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Move or rename files.
        - Basic use: Provide the `source` file path and the new `destination` path.
        - Important: Can overwrite existing files at the destination.
"@
}
