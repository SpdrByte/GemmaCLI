# ===============================================
# GemmaCLI Tool - summarize_context.ps1 v0.2.0
# Responsibility: Sends conversation history to Gemini Flash 2.5 Lite,
#                 generates a structured markdown summary, saves to .md file.
# ===============================================

function Invoke-SummarizeContextTool {
    param(
        [string]$filename = ""
    )

    # --- API Key Check ---
    if (-not $script:API_KEY) {
        return "ERROR: Google API key not found. Please set `$script:API_KEY`."
    }

    # --- Build output file path ---
    $workDir  = Get-Location
    $baseName = if ($filename) { [System.IO.Path]::GetFileNameWithoutExtension($filename) } else { "summary" }
    $outPath  = Join-Path $workDir "$baseName.md"
    $counter  = 1
    while (Test-Path $outPath) {
        $outPath = Join-Path $workDir "$baseName($counter).md"
        $counter++
    }

    # --- Build conversation text from history ---
    $historySummary = ""
    if ($script:history -and $script:history.Count -gt 0) {
        $lines = foreach ($entry in $script:history) {
            $role = $entry.role
            $text = ($entry.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " "
            if ($text -and $text.Trim().Length -gt 0) {
                "[$($role.ToUpper())]: $text"
            }
        }
        $historySummary = $lines -join "`n"
    }

    if ([string]::IsNullOrWhiteSpace($historySummary)) {
        return "ERROR: Conversation history is empty. Nothing to summarize."
    }

    # --- Build the prompt ---
    $summaryPrompt = @"
You are a precise technical summarizer. Analyze the conversation history below and produce a clean, structured Markdown summary document.

The document must follow this exact structure:

# Conversation Summary
> *Generated: {DATE}*

## Overview
A 2-3 sentence high-level summary of what the conversation was about.

## Key Topics
A bullet list of the main subjects, questions, or themes discussed.

## Decisions & Conclusions
A bullet list of any conclusions reached, decisions made, or answers given.

## Action Items
A bullet list of any tasks, follow-ups, or things the user said they would do. If none, write "None identified."

## Notable Details
Any specific facts, code snippets, file names, errors, or technical details worth preserving.

---
Replace {DATE} with today's date: $(Get-Date -Format 'dddd, MMMM dd yyyy HH:mm')

Now summarize this conversation:

--- CONVERSATION HISTORY ---
$historySummary
--- END OF HISTORY ---
"@

    # --- API Call ---
    try {
        $model = Resolve-ModelId "gemini-lite"
        $uri   = "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=$script:API_KEY"

        $body = @{
            contents = @(
                @{
                    parts = @(
                        @{ text = $summaryPrompt }
                    )
                }
            )
            generationConfig = @{
                maxOutputTokens = 2048
                temperature     = 0.3
                topP            = 0.9
            }
        }

        $jsonBody    = $body | ConvertTo-Json -Compress -Depth 6
        $rawResponse = Invoke-WebRequest -Uri $uri -Method Post -Body $jsonBody `
                            -ContentType "application/json" -UseBasicParsing -ErrorAction Stop
        $response    = $rawResponse.Content | ConvertFrom-Json

        $summaryText = $response.candidates[0].content.parts[0].text

        if ([string]::IsNullOrWhiteSpace($summaryText)) {
            return "ERROR: Gemini returned an empty summary. Try again."
        }

        # --- Write to file ---
        Set-Content -Path $outPath -Value $summaryText -Encoding UTF8 -Force
        $charCount = $summaryText.Length
        $fileName  = Split-Path $outPath -Leaf

        return "OK: Summary written to '$outPath' ($charCount characters). File: $fileName"

    } catch {
        $errorBody = $_.ErrorDetails.Message
        return "ERROR: Gemini API call failed. Message: $($_.Exception.Message) | Body: $errorBody"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "summarize_context"
    RendersToConsole = $false
    Category    = @("Help/Consultation", "Memory Management")
    Behavior    = "Summarizes the current conversation history into a structured Markdown document and saves it as a .md file. Use when the user wants to save, export, or recap the conversation."
    Description = "Sends the full conversation history to Gemini Flash 2.5 Lite and generates a structured Markdown summary with sections for overview, key topics, decisions, action items, and notable details. Saves to the current working directory."
    Parameters  = @{
        filename = "string - (optional) Base name for the output file, without extension. Defaults to 'summary'. Auto-increments if the file already exists (e.g. summary(1).md)."
    }
    Example     = "<tool_call>{ ""name"": ""summarize_context"", ""parameters"": { ""filename"": ""project_recap"" } }</tool_call>"
    FormatLabel = { param($p) "📋 SummarizeContext -> $(if ($p.filename) { "$($p.filename).md" } else { 'summary.md' })" }
    Execute     = {
        param($params)
        $filename = if ($params.filename) { $params.filename } else { "" }
        Invoke-SummarizeContextTool -filename $filename
    }
    ToolUseGuidanceMajor = @"
        - When to use 'summarize_context': Use when the user asks to summarize, recap, export, or save the conversation. Trigger on phrases like 'summarize our chat', 'save a summary', 'export this conversation', 'write up what we discussed'.
        - Parameters for 'summarize_context':
          - 'filename': Optional. If the user specifies a name (e.g. 'save it as project_notes'), pass that as the filename without extension. Otherwise omit it and the file will be named summary.md.
        - The tool reads `$script:history` directly — do not attempt to pass or reconstruct the conversation yourself.
        - Temperature is set low (0.3) intentionally — this tool prioritises accuracy over creativity.
        - Output saves to the current working directory. Auto-increments filename if file already exists.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Summarize and save the current conversation as a .md file.
        - Optional 'filename' param sets the output file name (no extension needed).
        - Saves to current directory as summary.md, auto-increments if file exists.
"@
}