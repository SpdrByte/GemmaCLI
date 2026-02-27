# more_tools/move_file.ps1

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
    Behavior    = "Use this tool to move or rename a file. This is the primary tool for file organization."
    Description = "Moves or renames a file."
    Parameters  = @{
        source      = "string - the path to the file to move"
        destination = "string - the new path for the file"
    }
    Example     = "<tool_call>{ ""name"": ""move_file"", ""parameters"": { ""source"": ""./old/file.txt"", ""destination"": ""./new/file.txt"" } }</tool_call>"
    FormatLabel = { param($params) "move_file -> $($params.source) to $($params.destination)" }
    Execute     = { param($params) Invoke-MoveFileTool @params }
}
