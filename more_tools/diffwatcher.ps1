# ===============================================
# GemmaCLI Tool - diffwatcher.ps1 v0.1.0
# Responsibility: Watches a file for external changes using FileSystemWatcher,
#                 then returns a formatted unified diff for analysis.
#                 Primary use: auditing edits made by other agents or collaborators.
# ===============================================

function Invoke-DiffWatcherTool {
    param(
        [string]$file_path,
        [string]$timeout_seconds = "60"
    )

    # ── Sanitize inputs ──────────────────────────────────────────────────────
    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')
    $timeout   = [int]$timeout_seconds

    if ([string]::IsNullOrWhiteSpace($file_path)) {
        return "ERROR: file_path cannot be empty."
    }

    try {
        $fullPath = (Resolve-Path -Path $file_path -ErrorAction Stop).Path
    } catch {
        return "ERROR: File not found: '$file_path'"
    }

    if (-not (Test-Path $fullPath -PathType Leaf)) {
        return "ERROR: Path is not a file: '$fullPath'"
    }

    try {
        # ── Snapshot original content ────────────────────────────────────────
        $originalLines = Get-Content -Path $fullPath -Encoding UTF8

        $dir      = Split-Path $fullPath -Parent
        $fileName = Split-Path $fullPath -Leaf

        # ── Set up FileSystemWatcher ─────────────────────────────────────────
        $watcher                     = New-Object System.IO.FileSystemWatcher
        $watcher.Path                = $dir
        $watcher.Filter              = $fileName
        $watcher.NotifyFilter        = [System.IO.NotifyFilters]::LastWrite
        $watcher.EnableRaisingEvents = $true

        # Blocks until file changes or timeout — spinner runs during this wait
        $result = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Changed, $timeout * 1000)

        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()

        if ($result.TimedOut) {
            return "ERROR: Timed out after ${timeout}s. No changes detected in '$fileName'."
        }

        # ── Read new content ─────────────────────────────────────────────────
        # Small sleep to let the writing process finish flushing
        Start-Sleep -Milliseconds 300
        $newLines = Get-Content -Path $fullPath -Encoding UTF8

        # ── Build unified diff ───────────────────────────────────────────────
        $maxLines      = 500
        $truncated     = $false
        $addCount      = 0
        $removeCount   = 0
        $outputBuffer  = [System.Collections.Generic.List[string]]::new()

        $oldArr = @($originalLines)
        $newArr = @($newLines)
        $oldLen = $oldArr.Count
        $newLen = $newArr.Count
        $maxLen = [Math]::Max($oldLen, $newLen)
        $lineNum = 1

        for ($idx = 0; $idx -lt $maxLen; $idx++) {
            $oldLine = if ($idx -lt $oldLen) { $oldArr[$idx] } else { $null }
            $newLine = if ($idx -lt $newLen) { $newArr[$idx] } else { $null }

            if ($null -eq $oldLine -and $null -ne $newLine) {
                $outputBuffer.Add("│ $($lineNum.ToString().PadLeft(3))  + $newLine")
                $addCount++
                $lineNum++
            } elseif ($null -ne $oldLine -and $null -eq $newLine) {
                $outputBuffer.Add("│ $($lineNum.ToString().PadLeft(3))  - $oldLine")
                $removeCount++
                $lineNum++
            } elseif ($oldLine -ne $newLine) {
                $outputBuffer.Add("│ $($lineNum.ToString().PadLeft(3))  - $oldLine")
                $outputBuffer.Add("│ $($lineNum.ToString().PadLeft(3))  + $newLine")
                $removeCount++
                $addCount++
                $lineNum++
            } else {
                $outputBuffer.Add("│ $($lineNum.ToString().PadLeft(3))    $oldLine")
                $lineNum++
            }

            if ($outputBuffer.Count -ge $maxLines) {
                $truncated = $true
                break
            }
        }

        $totalChanges = $addCount + $removeCount

        if ($totalChanges -eq 0) {
            return "OK: File '$fileName' was touched but no line content changed."
        }

        # ── Build header ─────────────────────────────────────────────────────
        $header = [System.Collections.Generic.List[string]]::new()
        $header.Add("╭─ DIFFWATCHER ────────────────────────────────────────────────────────────────╮")
        $header.Add("│ File    : $fullPath")
        $header.Add("│ Changes : $totalChanges lines  (+$addCount / -$removeCount)")
        if ($truncated) {
            $header.Add("│ WARNING : Diff truncated at $maxLines lines. Large changeset — manual review advised.")
        }
        $header.Add("├──────────────────────────────────────────────────────────────────────────────┤")

        $footer = "╰─────────────────────────────────────────────────────────────────────────────╯"

        return ($header + $outputBuffer + @($footer)) -join "`n"

    } catch {
        return "ERROR: diffwatcher failed. $($_.Exception.Message)"
    }
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "diffwatcher"
    RendersToConsole = $false
    Category         = @("Memory Management", "Coding/Development", "System Administration")
    Behavior         = "Use this tool to monitor a file for edits made by another agent, a collaborator, or the user. It snapshots the file contents, waits for the file to change, then returns a formatted line-by-line diff for your analysis."
    Description      = "Watches a file for external changes using FileSystemWatcher. When the file is modified, returns a formatted unified diff (max 500 lines) showing added, removed, and unchanged lines with line numbers. Truncates with a warning on large changesets."
    Parameters       = @{
        file_path       = "string - required. Absolute or relative path to the file to watch."
        timeout_seconds = "string - optional. Seconds to wait for a change before giving up. Default: 60. Recommended max: 300."
    }
    Example          = "<tool_call>{ ""name"": ""diffwatcher"", ""parameters"": { ""file_path"": ""src/player.ts"", ""timeout_seconds"": ""120"" } }</tool_call>"
    FormatLabel      = { param($p) "👁️ diffwatcher -> $($p.file_path)" }
    Execute          = { param($params) Invoke-DiffWatcherTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'diffwatcher':
            - Use when you have instructed another agent or tool to edit a file and want to verify the result.
            - Use when the user asks you to monitor a file for changes or audit another agent's or collaborator's work.
            - Do NOT use for files you are editing yourself — diffwatcher is for observing external changes only.

        - Job lifecycle and cancellation:
            - Once called, diffwatcher blocks until the file changes or the timeout expires. The spinner will run during this wait.
            - If the user presses ESC, the job is cancelled and you will receive NO result back. An absent result always means the job was cancelled — not that it is still running. You are free to call diffwatcher again immediately after a cancellation.
            - Only call diffwatcher once per file at a time. Do not call it again until you have received a result or confirmed via absent result that the previous call was cancelled.
            - If you are unsure whether a previous call completed or was cancelled, assume cancelled and proceed freely.

        - Reading the diff:
            - Lines prefixed with '+' were added.
            - Lines prefixed with '-' were removed.
            - Lines with no prefix are unchanged context lines.
            - Line numbers are shown on the left for reference.

        - If the diff is truncated (WARNING in header): inform the user the changeset is large and a full manual review is advised. Use 'readfile' to inspect specific sections.

        - Token awareness: A 500-line diff costs roughly 3,000–5,000 tokens. Factor this into your context budget.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Watch a file for external edits and return a diff.
        - Use after telling another agent or collaborator to edit a file.
        - '+' = added, '-' = removed, no prefix = unchanged.
        - If you get no result back, the job was cancelled — call again freely.
        - Do not call again until you have a result or know it was cancelled.
        - If truncated, use 'readfile' to inspect the full file.
"@
}