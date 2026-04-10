# ===============================================
# GemmaCLI Tool - write_story.ps1 v0.3.0
# Responsibility: Sends conversation history to Gemini Flash 2.5 Lite
#                 and writes the generated story to a .txt file.
# ===============================================

function Invoke-WriteStoryTool {
    param(
        [string]$topic = ""
    )

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Build output file path (story.txt, story(1).txt, story(2).txt ...) ---
    $workDir   = Get-Location
    $outPath   = Join-Path $workDir "story.txt"
    $counter   = 1
    while (Test-Path $outPath) {
        $outPath = Join-Path $workDir "story($counter).txt"
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
        return "ERROR: No usable conversation history found (everything was scrubbed or the session is empty). Please interact more before generating a story."
    }

    # --- Build the prompt ---
    $storyPrompt = @"
You are a master creative fiction writer. Your goal is to write a detailed, immersive, and well-structured novel based on the provided conversation history.

CRITICAL INSTRUCTIONS:
1. STRIP ALL METADATA: The history contains technical metadata, tool calls (e.g., <tool_call>), JSON objects, and mechanical game logs (e.g., [SYSTEM] TOOL RESULT, HP updates, dice rolls). You MUST ignore these mechanical details entirely.
2. FOCUS ON NARRATIVE: Capture the atmosphere, dialogue, character motivations, and emotional stakes discussed or implied in the conversation.
3. DETAILED & EXPANSIVE: Do not just summarize. Write a rich narrative with vivid descriptions.
4. STRUCTURE: Give the story a compelling title on the first line. Organize the content into multiple clearly labeled chapters (e.g., CHAPTER 1: THE AWAKENING).

$(if ($topic) { "ADDITIONAL FOCUS: $topic`n" })

--- CONVERSATION HISTORY (SCRUBBED) ---
$historySummary
--- END OF HISTORY ---

Write the complete, immersive story now.
"@

    # --- API Call ---
    try {
        $model = Resolve-ModelId "gemini-lite"
        $uri   = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$script:API_KEY"

        $body = @{
            contents = @(
                @{
                    parts = @(
                        @{ text = $storyPrompt }
                    )
                }
            )
            generationConfig = @{
                maxOutputTokens = 16384
                temperature     = 0.9
                topP            = 0.95
            }
        }

        $jsonBody = $body | ConvertTo-Json -Compress -Depth 6
        $jsonBody = $jsonBody.TrimStart([char]0xFEFF)
        $rawResponse = Invoke-WebRequest -Uri $uri -Method Post -Body $jsonBody `
                           -ContentType "application/json" -UseBasicParsing -ErrorAction Stop
        $response    = $rawResponse.Content | ConvertFrom-Json

        $storyText = $response.candidates[0].content.parts[0].text

        if ([string]::IsNullOrWhiteSpace($storyText)) {
            return "ERROR: Gemini returned an empty story. Try again or refine the conversation context."
        }

        # --- Write to file ---
        Set-Content -Path $outPath -Value $storyText -Encoding UTF8 -Force
        $charCount = $storyText.Length
        $fileName  = Split-Path $outPath -Leaf

        return "OK: Story written to '$outPath' ($charCount characters). File: $fileName"

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
        return "ERROR: Gemini API call failed.`nStatus: $($_.Exception.Response.StatusCode)`nBody: $errorBody`nPrompt length: $($storyPrompt.Length) chars`nJSON length: $($jsonBody.Length) chars"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "write_story"
    Icon        = "📖"
    RendersToConsole = $false
    Category    = @("Digital Media Production", "Help/Consultation")
    Behavior    = "Generates a creative short story based on the current conversation history using Gemini Flash 2.5 Lite, then saves it as a .txt file in the current working directory."
    Description = "Sends the full conversation history to Gemini Flash 2.5 Lite and instructs it to write a story. Saves the output to story.txt (or story(1).txt etc. if the file already exists)."
    Parameters  = @{
        topic = "string - (optional) An additional focus, theme, or instruction to guide the story. Leave empty to let the model derive everything from context."
    }
    Example     = "<tool_call>{ ""name"": ""write_story"", ""parameters"": { ""topic"": ""focus on the mystery elements"" } }</tool_call>"
    FormatLabel = { param($p) "$(if ($p.topic) { $p.topic } else { '' })" }
    Execute     = {
        param($params)
        $topic = if ($params.topic) { $params.topic } else { "" }
        Invoke-WriteStoryTool -topic $topic
    }
    ToolUseGuidanceMajor = @"
        - When to use 'write_story': Use this tool when the user asks you to write, generate, or save a story based on what has been discussed. Trigger on phrases like 'write a story', 'turn this into a story', 'save a story', or 'make a story from our conversation'.
        - Parameters for 'write_story':
          - 'topic': Optional. Use this to pass a specific theme, genre, or extra instruction the user mentioned (e.g. 'make it a horror story', 'focus on the dragon character'). If the user gave no special direction, omit it or pass an empty string.
        - The tool reads `$script:history` directly — no need to summarize or pass the conversation yourself.
        - Output file is saved to the current working directory as story.txt. If that exists, it increments: story(1).txt, story(2).txt, etc.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Write and save a story derived from the current conversation.
        - Optional 'topic' param lets you steer the genre or focus.
        - File saves to current directory as story.txt (auto-increments if file exists).
"@
}