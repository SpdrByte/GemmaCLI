# ===============================================
# GemmaCLI Tool - write_script.ps1 v0.4.0
# Responsibility: Sends conversation history to Gemini Stable Fast (2.5 Flash)
#                 and writes a structured, narration-heavy screenplay.
# ===============================================

function Invoke-WriteScriptTool {
    param(
        [string]$topic = ""
    )

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "[SYSTEM] ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Build output file path (script.txt, script(1).txt, script(2).txt ...) ---
    $workDir   = Get-Location
    $outPath   = Join-Path $workDir "script.txt"
    $counter   = 1
    while (Test-Path $outPath) {
        $outPath = Join-Path $workDir "script($counter).txt"
        $counter++
    }

    # --- Build conversation summary from history (SCRUBBED) ---
    $historySummary = ""
    if ($script:history -and $script:history.Count -gt 0) {
        $lines = foreach ($entry in $script:history) {
            $role = $entry.role
            $text = ($entry.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " "
            
            # 1. Strip Technical Artifacts (Regex)
            # Remove <tool_call> blocks
            $text = $text -replace '<tool_call>.*?</tool_call>', ''
            
            # Robust JSON scrubbing (multi-pass to handle nested structures)
            $oldLen = 0
            while ($text.Length -ne $oldLen) {
                $oldLen = $text.Length
                $text = $text -replace '\{[^{}]*\}', ''
            }
            
            # Remove CONSOLE and SYSTEM prefixes
            $text = $text -replace 'CONSOLE::.*?::END_CONSOLE::', ''
            $text = $text -replace '(?m)^\[SYSTEM\].*$', ''
            $text = $text -replace '(?m)^\[DEBUG\].*$', ''
            
            # 2. Character normalization
            $text = $text.Replace([char]0x201C, "'").Replace([char]0x201D, "'").Replace([char]0x2018, "'").Replace([char]0x2019, "'")
            $text = $text.Replace('\\n', ' ').Replace('\\r', ' ').Replace('\\t', ' ')
            
            # 3. Clean up extra whitespace
            $text = $text.Trim()
            
            if ($text -and $text.Length -gt 10) { # Skip very short/empty lines after scrubbing
                "[$($role.ToUpper())]: $text"
            }
        }
        $historySummary = $lines -join "`n"
    }

    # --- Guard: Empty History ---
    if ([string]::IsNullOrWhiteSpace($historySummary)) {
        return "[SYSTEM] ERROR: No usable conversation history found (everything was scrubbed or the session is empty). Please interact with the adventure more before generating a script."
    }

    # --- Build the prompt ---
    $scriptPrompt = @"
You are a professional creative scriptwriter and cinematic architect. Your goal is to write a detailed, well-structured screenplay based on the provided conversation history.

STRUCTURE AND FORMATTING:
1. [CHARACTER & LOCATION MANIFEST]: Start the file with this block. List every character and location with a concise, highly visual physical description (e.g. "CHARACTER: ELARA - A young woman in leather armor with a glowing blue crystal pendant."). These descriptions will be used as prompts for image generation.
2. SCRIPT HEADER: Title and Author.
3. SCENE DELIMITERS: Begin every new scene with a line formatted exactly as: "SCENE [N]: [CREATIVE TITLE] [TAG]" (e.g. "SCENE 1: THE HAN-SOLO-SIZED TAB [MOTION]"). Replace generic slugs with witty, unique, and context-aware titles that reflect the scene's content. Use the tag [MOTION] if the scene involves movement or travel, and [STATIC] if it is dialogue-heavy or a still shot. This is critical for machine parsing.
4. PROPER SCRIPT FORMAT: Use standard industry formatting (ACTION LINES for descriptions, CHARACTER NAMES in CAPS above their dialogue).
5. NARRATION HEAVY: To ensure production length, prioritize long stretches of "NARRATOR (V.O.)" and detailed, atmospheric ACTION lines. Describe every visual beat extensively.
6. NO TECHNICAL TEXT: Do NOT include any mentions of dice rolls, tool calls, JSON, or system errors in the final script. Transform these into narrative events.

$(if ($topic) { "ADDITIONAL FOCUS: $topic`n" })

--- CONVERSATION HISTORY (SCRUBBED) ---
$historySummary
--- END OF HISTORY ---

Write the complete, professionally formatted, and narration-heavy screenplay now.
"@

    # --- API Call ---
    try {
        $model = Resolve-ModelId "gemini-stable-fast" # Upgrade to 2.5 Flash
        $uri   = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$script:API_KEY"

        $body = @{
            contents = @(
                @{
                    parts = @(
                        @{ text = $scriptPrompt }
                    )
                }
            )
            generationConfig = @{
                maxOutputTokens = 16384 # Increased for long narration
                temperature     = 0.9
                topP            = 0.95
            }
        }

        $jsonBody = $body | ConvertTo-Json -Compress -Depth 6
        $jsonBody = $jsonBody.TrimStart([char]0xFEFF)
        $rawResponse = Invoke-WebRequest -Uri $uri -Method Post -Body $jsonBody `
                           -ContentType "application/json" -UseBasicParsing -ErrorAction Stop
        $response    = $rawResponse.Content | ConvertFrom-Json

        $scriptText = $response.candidates[0].content.parts[0].text

        if ([string]::IsNullOrWhiteSpace($scriptText)) {
            return "[SYSTEM] ERROR: Gemini returned an empty script. Try again or refine the conversation context."
        }

        # --- Write to file ---
        Set-Content -Path $outPath -Value $scriptText -Encoding UTF8 -Force
        $charCount = $scriptText.Length
        $fileName  = Split-Path $outPath -Leaf

        return "[SYSTEM] OK: Script written to '$outPath' ($charCount characters). File: $fileName"

     } catch {
        $errorBody = ""
        try {
            $response = $_.Exception.Response
            if ($response) {
                $stream = $null
                $reader = $null
                try {
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader $stream
                    $errorBody = $reader.ReadToEnd()
                } finally {
                    if ($reader) { $reader.Close(); $reader.Dispose() }
                    if ($stream) { $stream.Close(); $stream.Dispose() }
                }
            }
        } catch {}
        if (-not $errorBody) { $errorBody = $_.ErrorDetails.Message }
        if (-not $errorBody) { $errorBody = $_.Exception.Message }
        return "[SYSTEM] ERROR: Gemini API call failed.`nStatus: $($_.Exception.Response.StatusCode)`nBody: $errorBody`nPrompt length: $($scriptPrompt.Length) chars`nJSON length: $($jsonBody.Length) chars"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "write_script"
    Icon        = "📖"
    RendersToConsole = $false
    Category    = @("Digital Media Production")
    Behavior    = "Generates a creative, narration-heavy screenplay based on the current conversation history using Gemini Stable Fast (2.5 Flash), then saves it as a .txt file."
    Description = "Sends the scrubbed conversation history to Gemini Stable Fast (2.5 Flash) and instructs it to write a structured script with an Asset Manifest. Saves the output to script.txt (with auto-incrementing filename)."
    Parameters  = @{
        topic = "string - (optional) An additional focus, theme, or instruction to guide the script. Leave empty to let the model derive everything from context."
    }
    Example     = "<tool_call>{ ""name"": ""write_script"", ""parameters"": { ""topic"": ""focus on the mystery elements"" } }</tool_call>"
    FormatLabel = { param($p) "$(if ($p.topic) { $p.topic } else { '' })" }
    Execute     = {
        param($params)
        $topic = if ($params.topic) { $params.topic } else { "" }
        Invoke-WriteScriptTool -topic $topic
    }
    ToolUseGuidanceMajor = @"
        - When to use 'write_script': Use this tool when the user asks you to write, generate, or save a script based on what has been discussed. Trigger on phrases like 'write a script', 'turn this into a script', 'save a script', or 'make a script from our conversation'.
        - Parameters for 'write_script':
          - 'topic': Optional. Use this to pass a specific theme, genre, or extra instruction the user mentioned (e.g. 'make it a horror script', 'focus on the dragon character'). If the user gave no special direction, omit it or pass an empty string.
        - The tool reads `$script:history` directly — no need to summarize or pass the conversation yourself.
        - Output file is saved to the current working directory as script.txt. If that exists, it increments: script(1).txt, script(2).txt, etc.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Write and save a script derived from the current conversation.
        - Optional 'topic' param lets you steer the genre or focus.
        - File saves to current directory as script.txt (auto-increments if file exists).
"@
}
