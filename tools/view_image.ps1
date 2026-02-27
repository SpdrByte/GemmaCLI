# tools/view_image.ps1
# Responsibility: Encodes an image to base64 and returns it in a format
# that can be injected into the LLM's multimodal history.

function Invoke-ViewImageTool {
    param(
        [string]$file_path,
        [string]$prompt
    )

    $file_path = $file_path.Trim().Trim("'").Trim('"')
    if (-not (Test-Path $file_path -PathType Leaf)) {
        return "ERROR: File not found at '$file_path'"
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $file_path))
        $base64 = [System.Convert]::ToBase64String($bytes)
        $ext = [System.IO.Path]::GetExtension($file_path).ToLower()
        $mime = switch ($ext) {
            ".png"  { "image/png" }
            ".jpg"  { "image/jpeg" }
            ".jpeg" { "image/jpeg" }
            ".gif"  { "image/gif" }
            ".webp" { "image/webp" }
            default { "application/octet-stream" }
        }
        # Special format to be caught by the main script's response handler
        return "IMAGE_DATA::$mime::$base64::$prompt"
    } catch {
        return "ERROR: Could not read or encode image file. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "view_image"
    Behavior    = "Use this tool to analyze an image provided by the user. It is the only way to 'see' an image."
    Description = "Loads a local image file (PNG, JPG, GIF, WEBP) and allows the LLM to 'view' it, enabling multimodal analysis. Use this when the user asks a question about an image."
    Parameters  = @{
        file_path = "string - the path to the image file to view"
        prompt    = "string - the user's question or instruction about the image"
    }
    Example     = "<tool_call>{ ""name"": ""view_image"", ""parameters"": { ""file_path"": ""./images/chart.png"", ""prompt"": ""What does this chart show?"" } }</tool_call>"
    FormatLabel = { param($params) "view_image -> $($params.file_path)" }
    Execute     = { param($params) Invoke-ViewImageTool -file_path $params.file_path -prompt $params.prompt }
}
