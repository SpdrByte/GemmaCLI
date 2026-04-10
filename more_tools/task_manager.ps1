# tools/task_manager.ps1 v1.1.0
# Responsibility: Manages a session-specific task list (To-Do) for Gemma.
#                 Integrates with projects.json for persistent state.
# =============================================================================

function Invoke-TaskManagerTool {
    param(
        [string]$action,             # "add" | "update" | "list" | "clear" | "init"
        [string]$project_name,       # Name of the project (synergy with 'project' tool)
        [string]$subject      = "",  # Brief title for 'add'
        [int]$task_id         = -1,  # ID for 'update'
        [string]$status       = "",  # "pending" | "in_progress" | "completed"
        [string]$task_list    = ""   # Comma-separated list for 'init'
    )

    $action = $action.Trim().ToLower()
    $project_name = $project_name.Trim()
    $projectFile = Join-Path $env:APPDATA "GemmaCLI/projects.json"

    # ── Helper: load/save store ──────────────────────────────────────────────
    function Get-Store {
        if (Test-Path $projectFile) {
            try { return Get-Content $projectFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { }
        }
        return @{}
    }
    function Save-Store {
        param([hashtable]$store)
        $dir = Split-Path $projectFile -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $store | ConvertTo-Json -Depth 5 | Set-Content -Path $projectFile -Encoding UTF8 -Force
    }

    $store = Get-Store
    if (-not $store.ContainsKey($project_name)) {
        $store[$project_name] = @{ name=$project_name; tasks=@(); working_dir=(Get-Location).Path }
    }
    $proj = $store[$project_name]
    
    # Ensure tasks is a list/array
    if ($null -eq $proj.tasks) { $proj.tasks = @() }
    elseif ($proj.tasks -isnot [System.Collections.ArrayList] -and $proj.tasks -isnot [array]) {
        # Convert from PSCustomObject array (from JSON) to List for easier manipulation
        $list = New-Object System.Collections.Generic.List[PSObject]
        foreach ($t in $proj.tasks) { $list.Add($t) }
        $proj.tasks = $list
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: init (Quickly set up multiple tasks)
    # ════════════════════════════════════════════════════════════════════════
    if ($action -eq "init") {
        if ([string]::IsNullOrWhiteSpace($task_list)) { return "ERROR: 'task_list' (comma-separated) is required for 'init'." }
        $subjects = $task_list -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $newTasks = New-Object System.Collections.Generic.List[PSObject]
        $id = 1
        foreach ($s in $subjects) {
            $newTasks.Add(@{ id=$id; subject=$s; status="pending" })
            $id++
        }
        $proj.tasks = $newTasks
        Save-Store $store
        return "OK: Task list initialized for '$project_name'. Use 'list' to see them."
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: add
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "add") {
        if ([string]::IsNullOrWhiteSpace($subject)) { return "ERROR: 'subject' is required for 'add'." }
        $nextId = 1
        if ($proj.tasks.Count -gt 0) { 
            $max = 0; foreach($t in $proj.tasks) { if ($t.id -gt $max) { $max = $t.id } }
            $nextId = $max + 1
        }
        
        $currentTasks = New-Object System.Collections.Generic.List[PSObject]
        foreach($t in $proj.tasks) { $currentTasks.Add($t) }
        $currentTasks.Add(@{ id=$nextId; subject=$subject; status="pending" })
        $proj.tasks = $currentTasks
        
        Save-Store $store
        return "OK: Added task #${nextId}: '$subject'"
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: update
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "update") {
        if ($task_id -lt 1) { return "ERROR: Valid 'task_id' is required for 'update'." }
        $target = $null
        foreach ($t in $proj.tasks) { if ($t.id -eq $task_id) { $target = $t; break } }
        if (-not $target) { return "ERROR: Task #$task_id not found." }

        if ($status -match "in_progress") {
            # Mark others as pending if they were in_progress (only one active at a time)
            foreach ($t in $proj.tasks) { if ($t.status -eq "in_progress") { $t.status = "pending" } }
            $target.status = "in_progress"
        }
        elseif ($status -match "completed") { $target.status = "completed" }
        elseif ($status -match "pending")   { $target.status = "pending" }
        else { return "ERROR: Invalid status '$status'. Use: pending, in_progress, completed." }

        Save-Store $store
        return "OK: Task #$task_id updated to '$($target.status)'."
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: list
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "list") {
        if ($proj.tasks.Count -eq 0) { return "INFO: No tasks found for project '$project_name'." }
        $lines = @("TASKS: $($project_name)")
        foreach ($t in $proj.tasks) {
            $icon = switch ($t.status) { "completed" { "[X]" } "in_progress" { "[>]" } default { "[ ]" } }
            $lines += "  $($t.id). $icon $($t.subject)"
        }
        return $lines -join "`n"
    }

    # ════════════════════════════════════════════════════════════════════════
    # ACTION: clear
    # ════════════════════════════════════════════════════════════════════════
    elseif ($action -eq "clear") {
        $proj.tasks = @()
        Save-Store $store
        return "OK: All tasks cleared for project '$project_name'."
    }

    else { return "ERROR: Unknown action '$action'. Valid: add, update, list, clear, init." }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "task_manager"
    Icon        = "📝"
    RendersToConsole = $false
    Category    = @("Workflow Planning")
    Relationships = @{
        "project" = "Use 'task_manager' to track sub-steps for a project loaded via the 'project' tool. It stores session progress inside the projects.json file."
    }
    Behavior    = "Helps Gemma chain multiple actions together in a structured way. Use 'init' to plan the session's steps, then 'update' as you complete them. Persists in the AppData project store."
    Description = "Manages session-specific tasks for a project."
    Parameters  = @{
        action       = "string - required. 'add', 'update', 'list', 'clear', 'init'."
        project_name = "string - required. The project this task list belongs to."
        subject      = "string - optional (add only). Task title."
        task_id      = "int - optional (update only). The ID of the task."
        status       = "string - optional (update only). 'pending', 'in_progress', 'completed'."
        task_list    = "string - optional (init only). Comma-separated list of task subjects."
    }
    Example     = "<tool_call>{ ""name"": ""task_manager"", ""parameters"": { ""action"": ""init"", ""project_name"": ""GemmaCLI"", ""task_list"": ""Search files, Analyze code, Fix bug, Test fix"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.action) ($($p.project_name))" }
    Execute     = { param($params) Invoke-TaskManagerTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'task_manager': Use this proactively at the start of any multi-step request to ensure you don't lose the thread as context window grows.
        - Chaining: After planning with 'init', mark each task as 'in_progress' before doing the work, and 'completed' after.
        - Synergy: This tool uses the same 'project_name' as the 'project' tool. Loading a project does NOT load tasks; you must call 'task_manager action=list' to see them.
"@
    ToolUseGuidanceMinor = @"
        - Use 'init' to plan 3-7 steps for a task.
        - Use 'update' to track progress.
        - Uses projects.json for storage.
"@
}
