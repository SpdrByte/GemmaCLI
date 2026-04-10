# more_tools/voice_chat.ps1 v1.1.0
# Responsibility: High-fidelity two-way voice conversation with Gemini 3.1 Flash.
# Workflow: PowerShell (Setup/Key) -> Node.js (Live Voice Engagement)

function Invoke-VoiceChatTool {
    param(
        [string]$action = "start", # "start" | "stop"
        [string]$mic_name = "",    # Optional: Specific microphone name
        [string]$voice = "Puck"    # Optional: Specific voice name (Puck, Charon, Kore, Fenrir, Aoede)
    )

    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "C:\Users\kevin\Documents\AI\GemmaCLI" }
    $sidecarPath = Join-Path $scriptRootDir "lib/voice_live.js"
    $apiKey = Get-StoredKey -keyName "gemini_api_key"
    if (-not $apiKey) { $apiKey = $script:API_KEY }

    if ($action -eq "stop") {
        Stop-Process -Name ffmpeg, ffplay, node -ErrorAction SilentlyContinue
        return "OK: Voice chat processes stopped."
    }

    if ($action -eq "start") {
        if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) { return "ERROR: FFmpeg is required." }
        if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) { return "ERROR: Node.js is required." }

        # Auto-detect microphone name if not provided
        if ([string]::IsNullOrWhiteSpace($mic_name)) {
            Write-Host "[VOICE] Identifying audio devices..." -ForegroundColor Gray
            $ffmpegOutput = ffmpeg -list_devices true -f dshow -i dummy 2>&1
            $ffmpegLines = $ffmpegOutput | ForEach-Object { $_.ToString() }
            # Look for audio devices
            $micMatch = $ffmpegLines | Select-String -Pattern '"([^"]+)" \(audio\)'
            if ($micMatch) {
                $mic_name = $micMatch[0].Matches[0].Groups[1].Value
                Write-Host "[VOICE] Auto-detected Mic: $mic_name" -ForegroundColor Cyan
            } else {
                $mic_name = "Microphone Array (Realtek(R) Audio)" # Common fallback
                Write-Host "[VOICE] No audio devices found. Falling back to default: $mic_name" -ForegroundColor Yellow
            }
        }

        # Safety: Kill any lingering processes before starting
        Stop-Process -Name ffmpeg, ffplay, node -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        Write-Host "[VOICE] Starting two-way conversation session (Voice: $voice)..." -ForegroundColor Green
        Write-Host "[VOICE] Talk into your mic. Press ESC to end chat." -ForegroundColor Gray
        
        # We call node directly so it takes over the console for the interactive session
        # This allows the user to see the [GEMINI] text and the audio indicators (< >)
        try {
            # Pass the API Key, Model, Mic Name, and Voice to the Node.js sidecar
            $nodeArgs = "`"$sidecarPath`" `"$apiKey`" `"gemini-3.1-flash-live-preview`" `"$mic_name`" `"$voice`""
            
            # Since we want the user to see the output, we don't redirect here.
            # However, if we run it via Start-Process -NoNewWindow, it stays in this shell.
            Start-Process node -ArgumentList $nodeArgs -NoNewWindow -Wait
            
            return "OK: Voice chat session ended."
        } catch {
            return "ERROR: Failed to launch voice sidecar. $($_.Exception.Message)"
        }
    }

    return "ERROR: Unknown action '$action'."
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "voice_chat"
    Icon        = "🎙"
    Interactive = $true
    Category    = @("Communication", "AI")
    Behavior    = "Starts a real-time, two-way voice conversation with Gemini. It uses your microphone for input and plays Gemini's voice via your speakers. Available voices: Puck, Charon, Kore, Fenrir, Aoede."
    Description = "Live voice conversation with Gemini."
    Parameters  = @{
        action   = "string - 'start' (default) or 'stop'."
        mic_name = "string - optional. Specific microphone name to use."
        voice    = "string - optional. Voice name to use. Options: Puck, Charon, Kore, Fenrir, Aoede. Default is Puck."
    }
    Example     = '<tool_call>{ "name": "voice_chat", "parameters": { "action": "start", "voice": "Aoede" } }</tool_call>'
    FormatLabel = { param($p) "$($p.action) (Voice: $($p.voice))" }
    Execute     = { param($params) Invoke-VoiceChatTool @params }
}
