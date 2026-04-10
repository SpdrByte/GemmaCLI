# ===============================================
# GemmaCLI Tool - lyria_music.ps1 v0.2.0
# Responsibility: Generates high-fidelity music and lyrics via Google Lyria models.
# ===============================================

function Invoke-LyriaMusicTool {
    param(
        [string]$prompt,
        [string]$mode = "fast" # "fast" (short clips) or "pro" (full songs)
    )

    # Validate mode and map to handles
    $validModes = @{
        "fast" = "music-fast"
        "clip" = "music-fast"
        "pro"  = "music-pro"
        "full" = "music-pro"
    }
    
    $cleanMode = $mode.ToLower().Trim()
    if (-not $validModes.ContainsKey($cleanMode)) {
        return "ERROR: Invalid mode '$mode'. Valid options: fast, pro."
    }

    $modelHandle = $validModes[$cleanMode]
    $modelId = Resolve-ModelId $modelHandle
    
    # Use dedicated tool key if available, otherwise fallback to main CLI key
    $apiKey = Get-StoredKey -keyName "lyria_music"
    if (-not $apiKey) { $apiKey = $script:API_KEY }
    
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=$apiKey"

    # Multi-modal config for Lyria
    $config = @{
        maxOutputTokens = 4096
        temperature = 0.7
        response_modalities = @("AUDIO", "TEXT")
    }

    $resp = Invoke-SingleTurnApi `
        -uri $uri `
        -prompt $prompt `
        -spinnerLabel "Lyria is composing your music ($cleanMode)..." `
        -backend "gemini" `
        -configOverride $config

    if ($resp -is [string]) { return $resp } # Error string

    # Process Multi-modal Response
    $lyrics = ""
    $audioData = $null
    
    foreach ($part in $resp.candidates[0].content.parts) {
        if ($part.text) {
            $lyrics += $part.text
        }
        if ($part.inlineData) {
            $audioData = $part.inlineData.data
            $mime = $part.inlineData.mimeType
        }
    }

    if (-not $audioData) {
        return "ERROR: Lyria did not return any audio data. Lyrics generated: $lyrics"
    }

    # Save Audio to assets/music
    $musicDir = Join-Path $scriptDir "assets/music"
    if (-not (Test-Path $musicDir)) { New-Item -Path $musicDir -ItemType Directory -Force | Out-Null }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ext = if ($mime -match "mp3") { "mp3" } else { "wav" }
    $filename = "lyria_${cleanMode}_$timestamp.$ext"
    $filePath = Join-Path $musicDir $filename
    
    [System.IO.File]::WriteAllBytes($filePath, [System.Convert]::FromBase64String($audioData))

    # Create a proper file link for the CLI
    $fileLink = Convert-ToHyperlink -Text $filePath

    $result = "CONSOLE::PLAY_SOUND:tada::END_CONSOLE::OK: Lyria has finished your composition!`n`n"
    $result += "🎵 File saved to: $fileLink`n"
    if ($lyrics) {
        $result += "`nGenerated Lyrics/Structure:`n$lyrics"
    }

    return $result
}

$ToolMeta = @{
    Name        = "lyria_music"
    Icon        = "🎹"
    RendersToConsole = $false
    RequiresBilling = $true
    RequiresKey = $true
    KeyUrl      = "https://aistudio.google.com/app/apikey"
    Category    = @("Creative/Media")
    Description = "Generates high-fidelity music and lyrics using Google DeepMind Lyria. Supports short clips or full professional songs."
    Parameters  = @{
        prompt = "string - Detailed description of the song style, mood, and instruments."
        mode   = "string - optional. Use 'fast' for 30s snippets or 'pro' for full structural songs (up to 3 mins)."
    }
    Example     = "<tool_call>{ `"name`": `"lyria_music`", `"parameters`": { `"prompt`": `"upbeat 80s synthwave with a catchy bassline`", `"mode`": `"pro`" } }</tool_call>"
    FormatLabel = { param($p) "$($p.prompt.Substring(0, [math]::Min(25, $p.prompt.Length)))... [$($p.mode)]" }
    Execute     = { param($params) Invoke-LyriaMusicTool @params }
    Behavior    = "Use this tool to generate music or songs. Use 'pro' mode for complete songs with lyrics and structure. Use 'fast' mode for quick background clips or loops."
}
