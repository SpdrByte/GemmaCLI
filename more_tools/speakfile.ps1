# ===============================================
# GemmaCLI Tool - speakfile.ps1 v0.3.0
# Responsibility: Reads a file aloud using Windows TTS (SAPI.SpVoice).
#                 Auto-calculates a safe timeout from word count so Gemma
#                 never needs to guess. Exposes a rate param (-10..10) so
#                 long files can be read faster. Spinner runs throughout.
# ===============================================

function Invoke-SpeakFileTool {
    param(
        [string]$file_path,
        [string]$rate = "0"        # SAPI rate: -10 (slowest) to 10 (fastest). Default 0 ≈ 150 wpm.
    )

    # ── Sanitize inputs ──────────────────────────────────────────────────────
    $file_path  = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    $rateInt    = [Math]::Max(-10, [Math]::Min(10, [int]$rate))

    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    try {
        $fullPath = (Resolve-Path -Path $file_path -ErrorAction Stop).Path
    } catch {
        return "ERROR: File not found: '$file_path'"
    }

    if (-not (Test-Path $fullPath -PathType Leaf)) {
        return "ERROR: Path is not a file: '$fullPath'"
    }

    try {
        $fileName = Split-Path $fullPath -Leaf

        # ── Read file content ────────────────────────────────────────────────
        $content = Get-Content -Path $fullPath -Raw -Encoding UTF8 -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($content)) {
            return "ERROR: File '$fileName' is empty — nothing to read."
        }

        $charCount = $content.Length

        # ── Estimate duration & auto-set timeout ─────────────────────────────
        # SAPI rate is a logarithmic scale. Each +1 step adds roughly 10% speed.
        # Base rate (0) ≈ 150 wpm. Model: wpm = 150 * 1.1^rate
        # estimatedSeconds = (wordCount / wpm) * 60
        # Timeout = estimate * 1.5 safety margin, minimum 30s.
        $wordCount        = ($content -split '\s+' | Where-Object { $_ -ne '' }).Count
        $wpm              = 150 * [Math]::Pow(1.1, $rateInt)
        $estimatedSeconds = ($wordCount / $wpm) * 60
        $timeout          = [Math]::Max(30, [int]([Math]::Ceiling($estimatedSeconds * 1.5)))
        $estimatedMin     = [Math]::Round($estimatedSeconds / 60, 1)

        # ── Speak via SAPI.SpVoice ───────────────────────────────────────────
        # SVSFlagsAsync (1) — speaks asynchronously so we can poll for timeout.
        # Polling loop keeps the job process alive, which keeps the spinner alive.
        $voice       = New-Object -ComObject SAPI.SpVoice -ErrorAction Stop
        $voice.Rate  = $rateInt

        $voice.Speak($content, 1) | Out-Null  # 1 = SVSFlagsAsync

        # Poll until finished or auto-timeout
        $started = [System.Diagnostics.Stopwatch]::StartNew()
        $pollMs  = 250

        while ($voice.Status.RunningState -ne 1) {   # 1 = SRSEDone
            if ($started.Elapsed.TotalSeconds -ge $timeout) {
                $voice.Speak("", 3) | Out-Null  # 3 = SVSFPurgeBeforeSpeak (stop)
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($voice) | Out-Null
                return "ERROR: Timed out after ${timeout}s (estimated ${estimatedMin} min) reading '$fileName'. The file may be longer than the word-count estimate predicted (e.g. dense code or symbols). Try again with a higher rate (e.g. rate=3) to reduce actual playback time."
            }
            Start-Sleep -Milliseconds $pollMs
        }

        $elapsed = [Math]::Round($started.Elapsed.TotalSeconds)
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($voice) | Out-Null

        return "OK: Read '$fileName' aloud. Words: $wordCount | Chars: $charCount | Rate: $rateInt | Estimated: ${estimatedMin} min | Actual: ${elapsed}s."

    } catch {
        return "ERROR: speakfile failed on '$file_path'. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "speakfile"
    Icon             = "🔊"
    RendersToConsole = $false
    Category         = @("Accessibility", "File Management")
    Behavior         = "Use this tool to read a file aloud using Windows TTS. The timeout is calculated automatically from the file's word count — you do not need to pass timeout_seconds. Use the 'rate' parameter to control speed: 0 is natural pace (~150 wpm), 3-4 is comfortably faster for long files, up to 10 for maximum speed. After the tool returns, only briefly acknowledge completion — do not repeat or summarise the content, as the user has already heard it."
    Description      = "Reads a local file aloud using Windows TTS (SAPI.SpVoice). Auto-calculates a safe timeout from word count — no manual timeout needed. Accepts a rate param (-10 to 10) to control speed. Returns word count, char count, estimated vs actual duration."
    Parameters       = @{
        file_path = "string - required. Absolute or relative path to the file to read aloud."
        rate      = "string - optional. SAPI voice rate from -10 (slowest) to 10 (fastest). Default: 0 (≈150 wpm, natural pace). Use 3-4 for long documents, up to 10 for maximum speed."
    }
    Example          = "<tool_call>{ ""name"": ""speakfile"", ""parameters"": { ""file_path"": ""notes.txt"", ""rate"": ""0"" } }</tool_call>"
    FormatLabel      = { param($p)
        $rateLabel = if ($p.rate -and $p.rate -ne "0") { " @ rate $($p.rate)" } else { "" }
        "$($p.file_path)$rateLabel"
    }
    Execute          = { param($params) Invoke-SpeakFileTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'speakfile':
            - Use when the user asks you to read a file aloud, speak a file, or use TTS on a file.
            - Uses the Windows default voice (SAPI.SpVoice) — no external dependencies.

        - Timeout is automatic — do NOT pass timeout_seconds:
            - The tool estimates reading time from word count using: wpm = 150 * 1.1^rate
              and sets its own timeout at 1.5x the estimate. You never need to calculate or pass a timeout.
            - If the file is code-heavy or symbol-dense, the word-count estimate may be too short because
              SAPI vocalises symbols and punctuation that aren't counted as words. In that case,
              re-call with a higher rate (e.g. rate=3) to reduce actual playback time.

        - Choosing a rate:
            - 0  : Natural conversational pace (~150 wpm). Best for prose, notes, documentation.
            - 3–4: Noticeably faster, still intelligible. Recommended default for long documents.
            - 7–10: Very fast. Useful if the user just wants to skim by ear or verify content.
            - Negative values slow speech down — use only if the user explicitly asks.

        - During playback:
            - The spinner runs for the full duration. This is expected behaviour.
            - ESC cancels the job and stops speech immediately. An absent result = cancellation.
              You may call speakfile again freely after a cancellation.

        - After playback:
            - You receive: word count, char count, rate, estimated time, and actual elapsed seconds.
            - Do NOT repeat, quote, or summarise the file content — the user has already heard it.
            - A brief acknowledgement is sufficient: "Done — finished reading ZLLM_DESIGN_v0.2.md (took 4m 12s)."
            - Comparing estimated vs actual helps calibrate future calls on similar files — if actual
              ran significantly over estimate, the file is symbol-dense; suggest a higher rate next time.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Read a file aloud with Windows TTS. Spinner runs during playback.
        - Timeout is set automatically — do not pass timeout_seconds.
        - Use rate=3 or higher for long files to reduce playback time.
        - After the tool returns, only briefly acknowledge completion — do not summarise the file.
        - No result back = job was cancelled — call again freely.
"@
}