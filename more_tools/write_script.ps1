# ===============================================
# GemmaCLI Tool - write_script.ps1 v0.1.2
# Responsibility: Sends conversation history to Gemini Flash 2.5 Lite
#                 and writes the generated script to a .txt file.
# ===============================================

function Invoke-WriteScriptTool {
    param(
        [string]$topic = ""
    )

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Build output file path (script.txt, script(1).txt, script(2).txt ...) ---
    $workDir   = Get-Location
    $outPath   = Join-Path $workDir "script.txt"
    $counter   = 1
    while (Test-Path $outPath) {
        $outPath = Join-Path $workDir "script($counter).txt"
        $counter++
    }

    # --- Build conversation summary from history ---
   $historySummary = ""
   if ($script:history -and $script:history.Count -gt 0) {
       $lines = foreach ($entry in $script:history) {
           $role = $entry.role
           $text = ($entry.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " "
           $text = $text.Replace([char]0x201C, "'").Replace([char]0x201D, "'").Replace([char]0x2018, "'").Replace([char]0x2019, "'")
           $text = $text.Replace('\\n', ' ').Replace('\\r', ' ').Replace('\\t', ' ')
           if ($text -and $text.Length -gt 0) {
               "[$($role.ToUpper())]: $text"
           }
       }
       $historySummary = $lines -join "`n"
   }

    # --- Build the prompt ---
    $scriptPrompt = @"
You are a creative scriptwriter. Based on the conversation history below, write an engaging, well-structured screenplay/script. The script should capture the themes, characters, or ideas discussed in the conversation and present them in a compelling script form (scene headings, action lines, character names in CAPS, dialogue, parentheticals, etc.).

$(if ($topic) { "Additional focus for the script: $topic`n" })
--- CONVERSATION HISTORY ---
$historySummary
--- END OF HISTORY ---

Write the complete script now. Give it a title on the first line, then a blank line, then scene headings (e.g. INT. LOCATION - TIME) followed by action descriptions, character names, and dialogue. Make as many scenes as possible with context given.
"@

    # --- API Call ---
    try {
        $model = "gemini-2.5-flash-lite"
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
                maxOutputTokens = 4096
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
            return "ERROR: Gemini returned an empty script. Try again or refine the conversation context."
        }

        # --- Write to file ---
        Set-Content -Path $outPath -Value $scriptText -Encoding UTF8 -Force
        $charCount = $scriptText.Length
        $fileName  = Split-Path $outPath -Leaf

        return "OK: Script written to '$outPath' ($charCount characters). File: $fileName"

     } catch {
        $errorBody = ""
        try { $errorBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { (New-Object System.IO.StreamReader $_).ReadToEnd() } } catch {}
        if (-not $errorBody) { $errorBody = $_.ErrorDetails.Message }
        if (-not $errorBody) { $errorBody = $_.Exception.Message }
        return "ERROR: Gemini API call failed.`nStatus: $($_.Exception.Response.StatusCode)`nBody: $errorBody`nPrompt length: $($scriptPrompt.Length) chars`nJSON length: $($jsonBody.Length) chars"
        Set-Content -Path "C:\Users\kevin\Documents\AI\debug_json.txt" -Value $jsonBody -Encoding UTF8
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "write_script"
    RendersToConsole = $false
    Category    = @("Digital Media Production")
    Behavior    = "Generates a creative short script/screenplay based on the current conversation history using Gemini Flash 2.5 Lite, then saves it as a .txt file in the current working directory."
    Description = "Sends the full conversation history to Gemini Flash 2.5 Lite and instructs it to write a script. Saves the output to script.txt (or script(1).txt etc. if the file already exists)."
    Parameters  = @{
        topic = "string - (optional) An additional focus, theme, or instruction to guide the script. Leave empty to let the model derive everything from context."
    }
    Example     = "<tool_call>{ ""name"": ""write_script"", ""parameters"": { ""topic"": ""focus on the mystery elements"" } }</tool_call>"
    FormatLabel = { param($p) "📖 WriteScript$(if ($p.topic) { " -> $($p.topic)" } else { '' })" }
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
