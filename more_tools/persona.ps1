# ===============================================
# GemmaCLI Tool - persona.ps1 v1.1.0
# Responsibility: Transforms Gemma into a specific historical or fictional persona.
# ===============================================

function Invoke-Persona {
    param([string]$character)

    $dbPath = "database/personas.json"
    if (-not (Test-Path $dbPath)) {
        return "ERROR: database/personas.json not found."
    }

    try {
        $raw = Get-Content -Path $dbPath -Raw -Encoding UTF8
        # Strip BOM if present
        if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) {
            $raw = $raw.Substring(1)
        }
        $db = $raw | ConvertFrom-Json
    } catch {
        return "ERROR: Failed to parse personas.json. $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($character) -or $character -match "^(?i)list$") {
        $list = @()
        foreach ($key in $db.PSObject.Properties.Name) {
            $name = $db.$key.name
            $desc = $db.$key.description
            $list += "- $name ($key): $desc"
        }
        $listStr = $list -join "`n"
        return "CONSOLE::[Persona Database]`n$listStr`::END_CONSOLE::The user has been shown the following personas:`n$listStr"
    }

    # Find closest match
    $foundKey = $null
    foreach ($key in $db.PSObject.Properties.Name) {
        if ($key -match "(?i)$character" -or $db.$key.name -match "(?i)$character") {
            $foundKey = $key
            break
        }
    }

    if (-not $foundKey) {
        return "ERROR: Persona '$character' not found. Ask the user to choose from the available list or call the tool with 'list'."
    }

    $p = $db.$foundKey
    
    # Prepare TTS Voice instruction for the main process
    $voiceCmd = if ($p.sex -eq "female") { "SET_VOICE:Zira" } else { "SET_VOICE:David" }
    $voiceLabel = if ($p.sex -eq "female") { "Zira" } else { "David" }

    $instructions = @"
[ROLE ADOPTION: $($p.name.ToUpper())]
You are now acting as $($p.name).
Sex: $($p.sex)
$($p.description)

CORE INSTRUCTIONS:
$($p.instructions)

Adhere strictly to this persona for the remainder of this conversation until asked to stop or change. Acknowledge that you have adopted this role IN CHARACTER.
"@

    return "CONSOLE::[Persona Activated: $($p.name) (Voice: $voiceLabel)]::$voiceCmd::END_CONSOLE::$instructions"
}

# ====================== TOOL REGISTRATION ======================

$ToolMeta = @{
    Name        = "persona"
    Icon        = "🎭"
    RendersToConsole = $true
    Category    = @("Help/Consultation", "Gaming/Entertainment")
    Behavior    = "Transforms the AI into a specific historical or fictional persona loaded from a database."
    Description = "Activate a persona. Call this tool when the user asks you to act like someone else (e.g., Shakespeare, Machiavelli). Pass 'list' to see available personas."
    Parameters  = @{
        character = "string - The name or ID of the persona to adopt, or 'list' to see available options."
    }
    Example     = @"
<tool_call>{ "name": "persona", "parameters": { "character": "shakespeare" } }</tool_call>
"@
    FormatLabel = { param($p) if ($p.character) { "$($p.character)" } else { "list" } }
    Execute     = {
        param($params)
        Invoke-Persona -character $params.character
    }
    ToolUseGuidanceMajor = @"
- Call this tool when the user asks you to roleplay, act like, or speak as a specific historical figure or persona.
- If the user doesn't specify who, or asks who you can be, call this tool with character='list'.
- When a persona is returned, you MUST read the core instructions and strictly adopt that persona's voice, tone, and worldview for the rest of the conversation.
- Acknowledge the change IN CHARACTER immediately.
"@
    ToolUseGuidanceMinor = "Persona database loader."
}