# ===============================================
# GemmaCLI Tool - project.ps1 v0.1.0
# Responsibility: Save, load, or list project context entries stored in
#                 a per-project hashtable in AppData. Designed to give
#                 Gemma immediate orientation at the start of a session
#                 without consuming large portions of the context window.
# ===============================================

function Invoke-ProjectTool {
    param(
        [string]$action,        # "save" | "load" | "list"
        [string]$name     = "",
        [string]$description = "",
        [string]$stack    = "",
        [string]$entry_points = "",
        [string]$notes    = ""
    )

    $action = $action.Trim().ToLower()
    $name   = $name.Trim()

    $projectFile = Join-Path $env:APPDATA "GemmaCLI/projects.json"

    # ── Helper: load the full projects store ────────────────────────────────
    function Get-ProjectStore {
        if (Test-Path $projectFile) {
            try {
                $raw = Get-Content $projectFile -Raw -Encoding UTF8
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    return $raw | ConvertFrom-Json -AsHashtable
                }
            } catch { }
        }
        return @{}
    }

    # ── Helper: persist the full projects store ──────────────────────────────
    function Save-ProjectStore {
        param([hashtable]$store)
        $dir = Split-Path $projectFile -Parent
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
        $store | ConvertTo-Json -Depth 5 | Set-Content -Path $projectFile -Encoding UTF8 -Force
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: save
    # ════════════════════════════════════════════════════════════════════════
    if ($action -eq "save") {

        if ([string]::IsNullOrWhiteSpace($name)) {
            return "ERROR: 'name' is required for action 'save'."
        }

        $store = Get-ProjectStore

        # Parse stack and entry_points into arrays if comma-separated
        $stackArr       = @()
        $entryArr       = @()
        if (-not [string]::IsNullOrWhiteSpace($stack)) {
            $stackArr = $stack -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }
        if (-not [string]::IsNullOrWhiteSpace($entry_points)) {
            $entryArr = $entry_points -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }

        $existing = if ($store.ContainsKey($name)) { $store[$name] } else { @{} }

        $store[$name] = @{
            name          = $name
            working_dir   = (Get-Location).Path
            description   = if (-not [string]::IsNullOrWhiteSpace($description)) { $description } `
                            elseif ($existing.description) { $existing.description } else { "" }
            stack         = if ($stackArr.Count -gt 0) { $stackArr } `
                            elseif ($existing.stack)   { $existing.stack }   else { @() }
            entry_points  = if ($entryArr.Count -gt 0) { $entryArr } `
                            elseif ($existing.entry_points) { $existing.entry_points } else { @() }
            notes         = if (-not [string]::IsNullOrWhiteSpace($notes)) { $notes } `
                            elseif ($existing.notes) { $existing.notes } else { "" }
            last_saved    = Get-Date -Format "yyyy-MM-dd HH:mm"
        }

        try {
            Save-ProjectStore $store
            return "OK: Project '$name' saved. Working dir: $((Get-Location).Path)"
        } catch {
            return "ERROR: Could not save project. $($_.Exception.Message)"
        }
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: load
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "load") {

        if ([string]::IsNullOrWhiteSpace($name)) {
            return "ERROR: 'name' is required for action 'load'."
        }

        $store = Get-ProjectStore

        if (-not $store.ContainsKey($name)) {
            return "ERROR: No project found with name '$name'. Use action 'list' to see saved projects."
        }

        $p = $store[$name]

        $stackStr  = if ($p.stack -and $p.stack.Count -gt 0)        { $p.stack -join ", " }        else { "not specified" }
        $entryStr  = if ($p.entry_points -and $p.entry_points.Count -gt 0) { $p.entry_points -join ", " } else { "not specified" }
        $notesStr  = if (-not [string]::IsNullOrWhiteSpace($p.notes)) { $p.notes } else { "none" }
        $descStr   = if (-not [string]::IsNullOrWhiteSpace($p.description)) { $p.description } else { "none" }

        return @"
PROJECT CONTEXT LOADED: $($p.name)
  Working Dir  : $($p.working_dir)
  Description  : $descStr
  Stack        : $stackStr
  Entry Points : $entryStr
  Notes        : $notesStr
  Last Saved   : $($p.last_saved)
"@
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: list
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "list") {

        $store = Get-ProjectStore

        if ($store.Count -eq 0) {
            return "OK: No projects saved yet. Use action 'save' to add one."
        }

        $lines = @("Saved projects ($($store.Count)):")
        foreach ($key in ($store.Keys | Sort-Object)) {
            $p = $store[$key]
            $lines += "  - $($p.name) | $($p.working_dir) | Last saved: $($p.last_saved)"
        }
        return $lines -join "`n"
    }

    else {
        return "ERROR: Unknown action '$action'. Valid actions are: save, load, list."
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "project"
    RendersToConsole = $false
    Category         = @("Memory Management", "System Administration")
    Behavior         = "Use this tool to save, load, or list project context entries. At the start of a session, if the user mentions a project name or you are in an unfamiliar working directory, proactively call 'load' to orient yourself. Call 'save' when the user describes or updates a project so you can recall it in future sessions."
    Description      = "Manages persistent project context entries stored per-project in AppData. Each entry captures the project name, working directory, description, tech stack, key entry point files, and notes — giving Gemma fast orientation without scanning the filesystem."
    Parameters       = @{
        action        = "string - required. One of: 'save', 'load', 'list'"
        name          = "string - required for save and load. The project name used as the unique key."
        description   = "string - optional (save only). A 2-3 sentence summary of what the project is."
        stack         = "string - optional (save only). Comma-separated list of languages/frameworks, e.g. 'PowerShell, JSON, REST'."
        entry_points  = "string - optional (save only). Comma-separated list of key files, e.g. 'GemmaCLI.ps1, config.json'."
        notes         = "string - optional (save only). Short freeform notes: conventions, gotchas, current focus."
    }
    Example          = "<tool_call>{ ""name"": ""project"", ""parameters"": { ""action"": ""load"", ""name"": ""GemmaCLI"" } }</tool_call>"
    FormatLabel      = {
        param($p)
        switch ($p.action) {
            "save" { "📁 project > save > $($p.name)" }
            "load" { "📂 project > load > $($p.name)" }
            "list" { "📋 project > list" }
            default { "📁 project > $($p.action)" }
        }
    }
    Execute          = { param($params) Invoke-ProjectTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'project':
            - 'load': Call at the start of a session when the user references a project by name or when you are in an unfamiliar directory and want to orient yourself before asking the user to re-explain everything.
            - 'save': Call after the user describes a new project or corrects/updates project details. Capture description, stack, entry_points, and notes as completely as possible from the conversation.
            - 'list': Call if you are unsure whether a project has been saved before, or if the user asks what projects are available.
        - Parameters:
            - 'name': Use the project name exactly as the user states it. This is the unique key — consistency matters.
            - 'description': Keep to 2-3 sentences. Focus on purpose, not implementation detail.
            - 'stack': Comma-separated. Include languages, frameworks, and notable tools (e.g. 'PowerShell, Gemini API, JSON').
            - 'entry_points': List only the most important files — the ones you would want to read first to understand the project.
            - 'notes': Anything that would save time: known quirks, current focus area, conventions the user follows.
        - Token awareness: A loaded project entry is intentionally compact (~200-400 tokens). Prefer loading over asking the user to re-explain.
"@
    ToolUseGuidanceMinor = @"
        - Use 'load' at session start if you recognise a project name.
        - Use 'save' when the user describes or updates a project.
        - Use 'list' to check what projects exist.
        - 'name' is required for save and load.
"@
}