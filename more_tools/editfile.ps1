# ===============================================
# GemmaCLI Tool - editfile.ps1 v1.0.1
# Responsibility: Surgical line-anchored string replacement.
# Synergy: Designed to pair with readfile when line_numbers=true.
# ===============================================

function Invoke-EditFileTool {
    param(
        [string]$file_path,
        [int]$line_number,
        [string]$old_content,
        [string]$new_content
    )

    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')

    if ($line_number -lt 1) {
        return "ERROR: line_number must be 1-based (got $line_number)."
    }
    if ([string]::IsNullOrWhiteSpace($old_content)) {
        return "ERROR: old_content cannot be empty. Pass the exact line(s) you want to replace."
    }

    try {
        $fullPath = Resolve-Path -Path $file_path -ErrorAction Stop
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            return "ERROR: Path exists but is not a file: $file_path"
        }

        # Detect BOM before reading (ReadAllLines discards it)
        $hasBom = $false
        $fs = [System.IO.FileStream]::new([string]$fullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        try {
            $bom = New-Object byte[] 3
            $read = $fs.Read($bom, 0, 3)
            if ($read -eq 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) {
                $hasBom = $true
            }
        } finally {
            $fs.Close()
        }

        $lines = [System.IO.File]::ReadAllLines([string]$fullPath)
        $totalLines = $lines.Count

        # Split old/new content into line arrays
        $oldLines = $old_content -split "`n"
        $newLines = $new_content -split "`n"

        # Normalize: remove trailing `r from each split line (in case model included CRLF)
        $oldLines = @($oldLines | ForEach-Object { $_.TrimEnd("`r") })
        $newLines = @($newLines | ForEach-Object { $_.TrimEnd("`r") })

        $blockSize = $oldLines.Count
        $endLine   = $line_number + $blockSize - 1

        if ($endLine -gt $totalLines) {
            return "ERROR: Edit block (lines $line_number-$endLine) exceeds file length ($totalLines lines)."
        }

        # ── Exact-match safety check ──────────────────────────────────────
        for ($i = 0; $i -lt $blockSize; $i++) {
            $fileIdx   = $line_number - 1 + $i
            $expected  = $oldLines[$i]
            $actual    = $lines[$fileIdx]

            if ($expected -ne $actual) {
                $ctxStart = [Math]::Max(0, $fileIdx - 2)
                $ctxEnd   = [Math]::Min($totalLines - 1, $fileIdx + 2)
                $context  = @()
                for ($c = $ctxStart; $c -le $ctxEnd; $c++) {
                    $marker = if ($c -eq $fileIdx) { ">>> " } else { "    " }
                    $context += "$marker$($c + 1): $($lines[$c])"
                }

                return @(
                    "ERROR: Mismatch at line $($fileIdx + 1). Edit aborted.",
                    "",
                    "Expected:",
                    "    $expected",
                    "",
                    "Found:",
                    "    $actual",
                    "",
                    "Context:",
                    ($context -join "`n"),
                    "",
                    "Tip: Re-read the file with line_numbers=true to verify exact content."
                ) -join "`n"
            }
        }

        # ── Apply replacement ─────────────────────────────────────────────
        # Use unary comma to prevent PowerShell's if-statement from unwrapping
        # single-element arrays into bare strings (which breaks concatenation).
        $before = if ($line_number -gt 1) { ,($lines[0..($line_number - 2)]) } else { @() }
        $after  = if ($endLine -lt $totalLines) { ,($lines[$endLine..($totalLines - 1)]) } else { @() }
        $newFileLines = $before + $newLines + $after

        $encoding = if ($hasBom) { [System.Text.UTF8Encoding]::new($true) } else { [System.Text.UTF8Encoding]::new($false) }
        [System.IO.File]::WriteAllLines([string]$fullPath, $newFileLines, $encoding)

        # ── Return context with line numbers ──────────────────────────────
        $newTotal = $newFileLines.Count
        $ctxStart = [Math]::Max(0, $line_number - 4)
        $ctxEnd   = [Math]::Min($newTotal - 1, $line_number + $newLines.Count + 2)
        $contextOut = @()
        for ($c = $ctxStart; $c -le $ctxEnd; $c++) {
            $marker = if ($c -ge ($line_number - 1) -and $c -lt ($line_number - 1 + $newLines.Count)) { ">>> " } else { "    " }
            $contextOut += "$marker$($c + 1): $($newFileLines[$c])"
        }

        return @(
            "OK: Replaced lines $line_number-$endLine in '$($fullPath.Path)'."
            "",
            "Context:",
            ($contextOut -join "`n")
        ) -join "`n"

    } catch {
        return "ERROR: Could not edit file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Standard metadata block for registration ─────────────────────────────────
$ToolMeta = @{
    Name             = "editfile"
    Icon             = "✏️"
    RendersToConsole = $false
    Interactive      = $false
    Version          = "1.0.1"
    Category         = @("Coding/Development", "System Administration")
    Behavior         = @"
Use this tool for surgical edits to an existing file. It replaces an exact block of text
anchored at a specific line number. The edit only applies if the old_content matches exactly.
For larger rewrites (more than ~10 lines), use writefile instead.
"@
    Tutorial         = "I can edit specific lines in a file safely. Try: 'Change line 42 of app.js from oldFunc() to newFunc()'."
    Description      = "Surgical line-anchored string replacement. Requires exact old_content match at the given line_number."
    Keywords         = @("Edit", "Replace", "StrReplace", "Modify", "Patch", "Line")
    Parameters       = @{
        file_path  = "string - Absolute or relative path to the file. (required)"
        line_number = "integer - 1-based line number where old_content begins. (required)"
        old_content = "string - Exact text to match (can be multi-line, use newline chars). (required)"
        new_content = "string - Replacement text (can be multi-line). (required)"
    }
    Example          = "<tool_call>{ ""name"": ""editfile"", ""parameters"": { ""file_path"": ""app.js"", ""line_number"": 42, ""old_content"": ""function oldFunc() {"", ""new_content"": ""function newFunc() {"" } }</tool_call>"
    FormatLabel      = {
        param($params)
        "line $($params.line_number) of $($params.file_path)"
    }
    Execute          = { param($params)
        Invoke-EditFileTool @params
    }
    ToolUseGuidanceMajor = @"
        - When to use 'editfile': Use for small, surgical edits (single line or a few contiguous lines).
          For large rewrites (more than ~10 lines), prefer 'writefile' to reduce token usage.
        - Parameters:
            - `file_path`  (required): Path to the file.
            - `line_number` (required): 1-based line where `old_content` starts. Get this from `readfile` with `line_numbers=true`.
            - `old_content` (required): Exact text that currently exists at that position. Must match character-for-character.
            - `new_content` (required): The replacement text.
        - Multi-line edits: `old_content` and `new_content` can contain newline characters (`\n`).
          The tool matches a contiguous block starting at `line_number`.
        - Safety: The edit is ABORTED if any line in `old_content` does not match the file.
          The error response shows expected vs found vs surrounding context.
        - Workflow:
            1. Call `readfile` with `line_numbers=true` to inspect the target area.
            2. Copy the exact line(s) you want to replace into `old_content`.
            3. Provide `new_content` and the starting `line_number`.
            4. If the edit fails with a mismatch, re-read the file and try again.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Surgically replace exact text at a known line number.
        - Basic use: readfile (with line_numbers=true) → editfile → verify.
        - Tip: old_content must match exactly. When in doubt, re-read the file.
"@
    Relationships      = @{
        readfile = "Always use readfile with `line_numbers=true` before calling editfile so you have exact line numbers and content."
        writefile = "Use writefile instead of editfile when rewriting more than ~10 lines at once."
    }
}
