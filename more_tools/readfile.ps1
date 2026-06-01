# ===============================================
# GemmaCLI Tool - readfile.ps1 
# Responsibility: Function to read file content + Metadata for self-registration.
# Supports optional line range reading (start_line / end_line) for large files.
# ===============================================

function Invoke-ReadFileTool {
    param(
        [string]$file_path,
        [int]$start_line   = 0,
        [int]$end_line     = 0,
        [bool]$line_numbers = $false
    )

    $file_path = $file_path.Trim().Trim("'").Trim('"').Replace('\\', '\')

    try {
        $fullPath = Resolve-Path -Path $file_path -ErrorAction Stop
        $displayPath = $fullPath
        if ($displayPath.Length -gt 20) {
            $displayPath = "..." + $displayPath.Substring($displayPath.Length - 20)
        }
        Write-Output "readfile -> $displayPath"
        
        if (-not (Test-Path $fullPath -PathType Leaf)) {
            return "ERROR: Path exists but is not a file: $file_path"
        }

        $fileInfo = Get-Item $fullPath

        # ── Validate line range args ─────────────────────────────────────
        $useRange = ($start_line -gt 0) -or ($end_line -gt 0)

        if ($useRange) {
            # Default end_line to a large sentinel if only start_line was given
            if ($start_line -lt 1)  { $start_line = 1 }
            if ($end_line   -lt 1)  { $end_line   = [int]::MaxValue }

            if ($end_line -lt $start_line) {
                return "ERROR: end_line ($end_line) must be greater than or equal to start_line ($start_line)."
            }
        }

        # ── Line-range read (streaming — O(n) memory regardless of file size) ──
        if ($useRange) {
            $reader      = [System.IO.StreamReader]::new([string]$fullPath)
            $lineNum     = 0
            $collected   = [System.Text.StringBuilder]::new()
            $charCount   = 0
            $maxChars    = 20000
            $truncated   = $false
            $linesFound  = 0

            try {
                while (-not $reader.EndOfStream) {
                    $line    = $reader.ReadLine()
                    $lineNum++

                    if ($lineNum -lt $start_line) { continue }
                    if ($lineNum -gt $end_line)   { break    }

                    $linesFound++
                    $entry = if ($line_numbers) { "$lineNum`: $line`n" } else { "$line`n" }

                    if (($charCount + $entry.Length) -gt $maxChars) {
                        $truncated = $true
                        break
                    }

                    $collected.Append($entry) | Out-Null
                    $charCount += $entry.Length
                }
            } finally {
                $reader.Close()
            }

            if ($linesFound -eq 0) {
                # Count total lines so we can give a helpful error
                $totalLines = (Get-Content -Path $fullPath).Count
                return "ERROR: Line range $start_line-$end_line is out of bounds. File has $totalLines lines total."
            }

            $rangeLabel  = "Lines $start_line-$([Math]::Min($end_line, $lineNum)) of '$($fileInfo.Name)'"
            $truncNote   = if ($truncated) { "`n[TRUNCATED: Output reached 20,000 character limit before end of range]" } else { "" }
            return "[$rangeLabel]$truncNote`n`n$($collected.ToString())"
        }

        # ── Full-file read ────────────────────────────────────────────────
        # For files larger than 1 MB, return only the first 20,000 characters
        if ($fileInfo.Length -gt 1MB) {
            if ($line_numbers) {
                $reader     = [System.IO.StreamReader]::new([string]$fullPath)
                $collected  = [System.Text.StringBuilder]::new()
                $charCount  = 0
                $maxChars   = 20000
                $lineNum    = 0
                try {
                    while (-not $reader.EndOfStream) {
                        $line = $reader.ReadLine()
                        $lineNum++
                        $entry = "$lineNum`: $line`n"
                        if (($charCount + $entry.Length) -gt $maxChars) {
                            $collected.Append("[TRUNCATED: Reached 20,000 character limit]`n") | Out-Null
                            break
                        }
                        $collected.Append($entry) | Out-Null
                        $charCount += $entry.Length
                    }
                } finally {
                    $reader.Close()
                }
                return "[TRUNCATED: File exceeds 1 MB. Showing first 20,000 characters with line numbers. Use start_line/end_line to read specific sections.]`n`n$($collected.ToString())"
            } else {
                $reader     = [System.IO.StreamReader]::new([string]$fullPath)
                $charBuffer = New-Object char[] 20000
                $charsRead  = $reader.Read($charBuffer, 0, 20000)
                $reader.Close()
                $content = New-Object string($charBuffer, 0, $charsRead)
                return "[TRUNCATED: File exceeds 1 MB. Showing first 20,000 characters. Use start_line/end_line to read specific sections.]`n`n$content"
            }
        }

        if ($line_numbers) {
            $lines = [System.IO.File]::ReadAllLines([string]$fullPath)
            $numbered = for ($i = 0; $i -lt $lines.Count; $i++) {
                "$($i + 1): $($lines[$i])"
            }
            return ($numbered -join "`n")
        }

        return Get-Content -Path $fullPath -Raw -ErrorAction Stop

    } catch {
        return "ERROR: Could not read file '$file_path'. $($_.Exception.Message)"
    }
}

# ── Standard metadata block for registration ─────────────────────────────────
$ToolMeta = @{
    Name             = "readfile"
    Version          = "v1.1.1"
    Icon             = "📖"
    RendersToConsole = $false
    Interactive      = $false
    Category         = @("System Administration", "Coding/Development", "Memory Management")
    Behavior         = @"
Use this tool to read the contents of a file. Before using, verify the file exists with `searchdir`.
To read a specific section of a large file, pass start_line and/or end_line.
If neither is provided the full file is returned (auto-truncated at 20,000 characters for files > 1 MB).
"@
    Tutorial         = "I can read any text-based file, in full or by line range. Try: 'Read lines 50 to 100 of server.log'."
    Description      = "Reads raw text content of a local file. Supports optional start_line / end_line for targeted reading of large files."
    Keywords         = @("Readfile", "Read", "File", "View", "Get", "Lines", "Range")
    Parameters       = @{
        file_path  = "string  - Absolute or relative path to the file. (required)"
        start_line   = "integer - First line to read, 1-based. Omit to start from the beginning. (optional)"
        end_line     = "integer - Last line to read, inclusive. Omit to read to end of file or until 20,000-char limit. (optional)"
        line_numbers = "boolean - When true, prepends 'N: ' to every line. Use when you need exact line positions for editfile. (optional, default: false)"
    }
    Example          = "<tool_call>{ ""name"": ""readfile"", ""parameters"": { ""file_path"": ""app.log"", ""start_line"": 100, ""end_line"": 200 } }</tool_call>"
    FormatLabel      = {
        param($params)
        $range = if ($params.start_line -or $params.end_line) {
            $s = if ($params.start_line) { $params.start_line } else { "1" }
            $e = if ($params.end_line)   { $params.end_line   } else { "EOF" }
            " [lines $s-$e]"
        } else { "" }
        "$($params.file_path)$range"
    }
    Execute          = { param($params)
        $s = if ($params.start_line)   { [int]$params.start_line   } else { 0 }
        $e = if ($params.end_line)     { [int]$params.end_line     } else { 0 }
        $n = if ($params.line_numbers) { [bool]$params.line_numbers } else { $false }
        Invoke-ReadFileTool -file_path $params.file_path -start_line $s -end_line $e -line_numbers $n
    }
    ToolUseGuidanceMajor = @"
        - When to use 'readfile': Use to inspect textual content of any local file — code, config, logs, or data.
        - Parameters:
            - `file_path` (required): Absolute or relative path. Always confirm existence with `searchdir` first.
            - `start_line`   (optional, integer): First line to return, 1-based. Use when you need a specific section.
            - `end_line`     (optional, integer): Last line to return, inclusive. Can be combined with start_line.
            - `line_numbers` (optional, boolean): Prepend 'N: ' to every line. Enable this when reading a file
              that you intend to edit with `editfile`, so you can pass exact line numbers.
        - Line range strategy:
            - For large or unknown-size files, prefer reading in chunks (e.g., 1-100, then 101-200) rather than
              reading the full file, to stay within context limits.
            - If the file is under 1 MB and no range is given, the full content is returned.
            - Files over 1 MB without a range are auto-truncated to the first 20,000 characters.
        - Output: Raw text of the requested lines, prefixed with a range label when a range is used.
        - Error Handling: Returns a descriptive ERROR string if the file is missing, not a file, out of range, or unreadable.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Read the content of a file safely, in full or by line range.
        - Basic use: Provide `file_path`. Add `start_line`/`end_line` for targeted reads.
        - Tip: Use `searchdir` to confirm path before calling readfile.
"@
}