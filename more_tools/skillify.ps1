# tools/skillify.ps1 v1.2.0
# Responsibility: Captures or searches repeatable processes.
#                 Everything is stored directly in database/skills.json.
# =============================================================================

function Invoke-SkillifyTool {
    param(
        [string]$action = "capture", # "capture" | "search" | "list"
        [string]$query  = "",        # keyword for search
        [string]$description = ""    # hint for capture
    )

    $currentToolDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $scriptRootDir  = Split-Path -Parent $currentToolDir
    $dbFile         = Join-Path $scriptRootDir "database/skills.json"

    # ── ACTION: search / list ───────────────────────────────────────────────
    if ($action -match "search|list") {
        if (-not (Test-Path $dbFile)) { return "INFO: No skills database found yet." }
        try {
            $db = Get-Content $dbFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        } catch {
            return "ERROR: Failed to parse skills.json"
        }
        
        $results = @()
        foreach ($key in $db.Keys) {
            $s = $db[$key]
            $match = $false
            if ($action -eq "list") { $match = $true }
            else {
                if ($s.name -match $query -or $s.description -match $query -or ($s.tags -join " ") -match $query) {
                    $match = $true
                }
            }

            if ($match) {
                $results += "✨ $($s.name) [$($s.tags -join ', ')]`n   $($s.description)"
            }
        }
        
        if ($results.Count -eq 0) { return "INFO: No skills found matching '$query'." }
        return "FOUND SKILLS:`n`n" + ($results -join "`n`n")
    }

    # ── ACTION: capture ─────────────────────────────────────────────────────
    $historyFile = Join-Path $env:APPDATA "GemmaCLI/last_session.json"
    if (-not (Test-Path $historyFile)) { 
        return "ERROR: No session history found to analyze. Ensure you've had a conversation before calling capture." 
    }

    try {
        $history = Get-Content $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return "ERROR: Could not read history file."
    }

    $userMessages = @()
    foreach ($turn in $history) { 
        if ($turn.role -eq "user") { 
            foreach ($part in $turn.parts) { if ($part.text) { $userMessages.Add($part.text) } } 
        } 
    }
    $userMsgBlock = $userMessages -join "`n---`n"

    if ([string]::IsNullOrWhiteSpace($userMsgBlock)) {
        return "ERROR: No conversation history to analyze."
    }

    $analysisPrompt = @"
You are an expert automation engineer. Analyze these user messages and distill the process into a reusable Skill JSON object.
Context: $description
User Messages:
$userMsgBlock

Output ONLY a JSON object:
{
  "name": "kebab-case-id",
  "title": "Clear Title",
  "description": "One line summary",
  "tags": ["list", "of", "keywords"],
  "content": "The full technical guide in markdown format"
}
"@

    Write-Host "`n[SKILLIFY] Analyzing history and synthesizing skill..." -ForegroundColor Cyan
    $modelId = Resolve-ModelId "gemini-fast"
    $uri = "https://generativelanguage.googleapis.com/v1beta/models/${modelId}:generateContent?key=$($script:API_KEY)"
    $jsonResponse = Invoke-SingleTurnApi -uri $uri -prompt $analysisPrompt -spinnerLabel "Distilling..." -backend "gemini"

    if ($jsonResponse -like "ERROR:*") { return $jsonResponse }

    try {
        # Clean potential markdown fences
        $jsonClean = $jsonResponse -replace "^```json\s*", "" -replace "^```\s*", "" -replace "```\s*$", ""
        $newSkill = $jsonClean | ConvertFrom-Json
        
        # Save to DB
        $db = @{}
        if (Test-Path $dbFile) { 
            try { $db = Get-Content $dbFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch {}
        }
        
        $db[$newSkill.name] = $newSkill
        
        if (-not (Test-Path (Split-Path $dbFile))) { New-Item -Path (Split-Path $dbFile) -ItemType Directory -Force | Out-Null }
        $db | ConvertTo-Json -Depth 10 | Set-Content -Path $dbFile -Encoding UTF8 -Force

        return "OK: Skill '$($newSkill.name)' captured directly into database/skills.json."
    } catch {
        return "ERROR: Failed to parse or save skill JSON. Model output was: $jsonResponse"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "skillify"
    Icon        = "✨"
    RendersToConsole = $true
    Category    = @("Process Automation")
    Behavior    = "Analyzes history to extract technical skills and stores them in database/skills.json. Also allows searching for existing skills."
    Description = "Manages a skills database in database/skills.json."
    Parameters  = @{
        action      = "string - required. 'capture', 'search', or 'list'."
        query       = "string - optional. Search term for 'search'."
        description = "string - optional. Hint for 'capture'."
    }
    FormatLabel = { param($p) "$($p.action) $(if($p.query){'['+$p.query+']'})" }
    Execute     = { param($params) Invoke-SkillifyTool @params }
    ToolUseGuidanceMajor = @"
        - 'capture': Call this at the end of a multi-turn engineering task to save the process. It reads your history and creates a skill entry.
        - 'search': Use this to find previously saved processes.
        - 'list': Show all saved skills.
        - Storage: All data is stored in 'database/skills.json'. No separate markdown files are created.
"@
    ToolUseGuidanceMinor = @"
        - Manage reusable skills in a JSON database.
        - Actions: capture, search, list.
"@
}
