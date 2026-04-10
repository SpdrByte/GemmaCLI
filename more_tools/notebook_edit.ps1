# GemmaCLI Tool - notebook_edit.ps1 v0.2.0
# Responsibility: Surgically edits cells in a Jupyter Notebook (.ipynb) file.
# ===============================================

function Invoke-NotebookEditTool {
    param(
        [string]$notebook_path,
        [string]$cell_id,
        [string]$new_source,
        [string]$cell_type, # 'code' or 'markdown'
        [string]$edit_mode = "replace" # 'replace', 'insert', 'delete'
    )

    $notebook_path = $notebook_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    if ([string]::IsNullOrWhiteSpace($notebook_path)) {
        return "ERROR: notebook_path cannot be empty."
    }

    if (-not (Test-Path $notebook_path)) {
        if ($script:TOOLS.ContainsKey("writefile")) {
            return "ERROR: Notebook file '$notebook_path' not found. To create a NEW notebook, use the 'writefile' tool first with a basic JSON structure, then use 'notebook_edit' to add cells."
        } else {
            return "ERROR: Notebook file '$notebook_path' not found. Note: The 'writefile' tool is required to create a new notebook, but it is currently inactive. Would you like to edit an existing notebook instead?"
        }
    }

    if ($notebook_path -notmatch '\.ipynb$') {
        return "ERROR: File must be a Jupyter notebook (.ipynb file)."
    }

    try {
        $json = Get-Content -Path $notebook_path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return "ERROR: Failed to parse notebook as JSON. It may be corrupted."
    }

    if ($null -eq $json.cells) {
        return "ERROR: Invalid notebook structure (missing 'cells' array)."
    }

    # Helper to find cell index by ID or numeric index
    function Get-CellIndex {
        param($id, $cells)
        if ([string]::IsNullOrWhiteSpace($id)) { return -1 }
        # Try finding by 'id' property (modern notebooks)
        for ($i = 0; $i -lt $cells.Count; $i++) {
            if ($cells[$i].id -eq $id) { return $i }
        }
        # Fallback to numeric index (cell-N format)
        if ($id -match 'cell-(\d+)') {
            $idx = [int]$matches[1]
            if ($idx -ge 0 -and $idx -lt $cells.Count) { return $idx }
        }
        # Direct numeric index
        if ($id -as [int] -ne $null) {
            $idx = [int]$id
            if ($idx -ge 0 -and $idx -lt $cells.Count) { return $idx }
        }
        return -1
    }

    $cellIndex = Get-CellIndex -id $cell_id -cells $json.cells

    # Helper to split source and ensure trailing newlines
    function Format-Source {
        param($source)
        return $source -split "`r?`n" | ForEach-Object { $_ + "`n" }
    }

    switch ($edit_mode) {
        "replace" {
            if ($cellIndex -eq -1) { return "ERROR: Cell '$cell_id' not found for replacement." }
            $targetCell = $json.cells[$cellIndex]
            $targetCell.source = Format-Source $new_source
            if ($cell_type) { $targetCell.cell_type = $cell_type }
            if ($targetCell.cell_type -eq "code") {
                if ($targetCell.PSObject.Properties['execution_count']) { $targetCell.execution_count = $null }
                else { $targetCell | Add-Member -NotePropertyName "execution_count" -NotePropertyValue $null }
                
                if ($targetCell.PSObject.Properties['outputs']) { $targetCell.outputs = @() }
                else { $targetCell | Add-Member -NotePropertyName "outputs" -NotePropertyValue @() }
            }
        }
        "insert" {
            $newCell = [PSCustomObject]@{
                cell_type = if ($cell_type) { $cell_type } else { "code" }
                metadata = @{}
                source = Format-Source $new_source
            }
            if ($newCell.cell_type -eq "code") {
                $newCell | Add-Member -NotePropertyName "execution_count" -NotePropertyValue $null
                $newCell | Add-Member -NotePropertyName "outputs" -NotePropertyValue @()
            }
            # Add unique ID if notebook format supports it (4.5+)
            if ($json.nbformat -gt 4 -or ($json.nbformat -eq 4 -and $json.nbformat_minor -ge 5)) {
                $newCell | Add-Member -NotePropertyName "id" -NotePropertyValue ([guid]::NewGuid().ToString().Substring(0,8))
            }

            $currentCells = New-Object System.Collections.Generic.List[PSObject]
            foreach ($c in $json.cells) { $currentCells.Add($c) }

            if ($cellIndex -eq -1) {
                # Insert at end if ID not specified or not found
                $currentCells.Add($newCell)
                $finalIdx = $currentCells.Count - 1
            } else {
                # Insert after the found cell
                $currentCells.Insert($cellIndex + 1, $newCell)
                $finalIdx = $cellIndex + 1
            }
            $json.cells = $currentCells.ToArray()
            $cellIndex = $finalIdx
        }
        "delete" {
            if ($cellIndex -eq -1) { return "ERROR: Cell '$cell_id' not found for deletion." }
            $currentCells = New-Object System.Collections.Generic.List[PSObject]
            foreach ($c in $json.cells) { $currentCells.Add($c) }
            $currentCells.RemoveAt($cellIndex)
            $json.cells = $currentCells.ToArray()
        }
        default {
            return "ERROR: Invalid edit_mode '$edit_mode'. Use 'replace', 'insert', or 'delete'."
        }
    }

    try {
        $updatedContent = $json | ConvertTo-Json -Depth 100
        $updatedContent | Set-Content -Path $notebook_path -Encoding UTF8
        $resolved = Resolve-Path $notebook_path
        return "OK: Successfully performed '$edit_mode' on cell index $cellIndex in '$resolved'."
    } catch {
        return "ERROR: Failed to save updated notebook. $($_.Exception.Message)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "notebook_edit"
    Icon        = "📓"
    RendersToConsole = $false
    Category    = @("Data Science", "Coding/Development")
    Relationships = @{
        "writefile" = "Use 'writefile' to create a new .ipynb file before using 'notebook_edit' to modify its cells. 'notebook_edit' is for surgical edits, not initial creation."
    }
    Behavior    = "Use this tool to surgically edit cells in a Jupyter Notebook (.ipynb). It prevents JSON corruption by manipulating the notebook structure directly rather than treating it as raw text."
    Description = "Edits, inserts, or deletes cells in a Jupyter Notebook file (.ipynb)."
    Parameters  = @{
        notebook_path = "string - absolute path to the .ipynb file."
        cell_id       = "string - the ID of the cell to edit. Can be the 'id' property, a numeric index, or 'cell-N' format."
        new_source    = "string - the new code or markdown text for the cell."
        cell_type     = "string - 'code' or 'markdown'. Required for 'insert', optional for 'replace'."
        edit_mode     = "string - 'replace' (default), 'insert' (inserts after cell_id), or 'delete'."
    }
    Example     = "<tool_call>{ ""name"": ""notebook_edit"", ""parameters"": { ""notebook_path"": ""analysis.ipynb"", ""cell_id"": ""0"", ""new_source"": ""print('hello')"", ""cell_type"": ""code"", ""edit_mode"": ""replace"" } }</tool_call>"
    FormatLabel = { param($params) 
        "$($params.notebook_path) ($($params.edit_mode))" 
    }
    Execute     = {
        param($params)
        Invoke-NotebookEditTool @params
    }
    ToolUseGuidanceMajor = @"
        - When to use 'notebook_edit': Use this tool whenever you need to modify a Jupyter Notebook. Never use 'writefile' for .ipynb files as it easily leads to JSON corruption.
        - Important: To create a NEW notebook, you MUST use 'writefile' to create a basic .ipynb structure first (e.g., '{ "cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5 }'), then use 'notebook_edit' to add/edit cells.
        - Cell IDs: Notebooks use unique IDs for cells. If you don't know the ID, you can use the 0-based index (e.g., "0" for the first cell).
        - State: Editing a cell resets its execution count and clears its output to maintain consistency.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Safely edit Jupyter Notebooks.
        - Basic use: Provide `notebook_path`, `cell_id`, and `new_source`. 
        - Modes: Supports 'replace', 'insert', and 'delete'.
"@
}
