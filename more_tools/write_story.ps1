# ===============================================
# GemmaCLI Tool - write_story.ps1 v0.1.2
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
    $storyPrompt = @"
You are a creative fiction writer. Based on the conversation history below, write an engaging, well-structured novel. The story should capture the themes, characters, or ideas discussed in the conversation and present them in a compelling narrative form.

$(if ($topic) { "Additional focus for the story: $topic`n" })
--- CONVERSATION HISTORY ---
$historySummary
--- END OF HISTORY ---

Write the complete story now. Give it a title on the first line, then a blank line, then the chapter title followed by chapter body. Make as many chapters as possible with context given.
"@

    # --- API Call ---
    try {
        $model = "gemini-2.5-flash-lite"
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
        try { $errorBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { (New-Object System.IO.StreamReader $_).ReadToEnd() } } catch {}
        if (-not $errorBody) { $errorBody = $_.ErrorDetails.Message }
        if (-not $errorBody) { $errorBody = $_.Exception.Message }
        return "ERROR: Gemini API call failed.`nStatus: $($_.Exception.Response.StatusCode)`nBody: $errorBody`nPrompt length: $($storyPrompt.Length) chars`nJSON length: $($jsonBody.Length) chars"
        Set-Content -Path "C:\Users\kevin\Documents\AI\debug_json.txt" -Value $jsonBody -Encoding UTF8
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "write_story"
    RendersToConsole = $false
    Category    = @("Digital Media Production", "Help/Consultation")
    Behavior    = "Generates a creative short story based on the current conversation history using Gemini Flash 2.5 Lite, then saves it as a .txt file in the current working directory."
    Description = "Sends the full conversation history to Gemini Flash 2.5 Lite and instructs it to write a story. Saves the output to story.txt (or story(1).txt etc. if the file already exists)."
    Parameters  = @{
        topic = "string - (optional) An additional focus, theme, or instruction to guide the story. Leave empty to let the model derive everything from context."
    }
    Example     = "<tool_call>{ ""name"": ""write_story"", ""parameters"": { ""topic"": ""focus on the mystery elements"" } }</tool_call>"
    FormatLabel = { param($p) "📖 WriteStory$(if ($p.topic) { " -> $($p.topic)" } else { '' })" }
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