# lib/UI.ps1 v0.1.2
# Responsibility: Contains UI-related functions like Draw-Box, Show-ArrowMenu, Start-Spinner, and Start-BarTracker.
# Keeps the main loop clean and focused on orchestration.

function Convert-ToHyperlink {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    
    $esc = [char]27
    # Regex for Windows Paths (e.g., C:\Users\...)
    $pathRegex = '\b([A-Za-z]:\\[^ "''><\n\t\r\)\(]+)\b'
    # Regex for URLs (http/https)
    $urlRegex  = '\b(https?://[^ "''><\n\t\r\)\(]+)\b'

    # Handle Web Links first
    $Text = [regex]::Replace($Text, $urlRegex, {
        param($m)
        $url = $m.Groups[1].Value
        return "$($esc)]8;;$($url)$($esc)\$($url)$($esc)]8;;$($esc)\"
    })

    # Handle File Paths (Convert \ to / for the file:/// URI)
    $Text = [regex]::Replace($Text, $pathRegex, {
        param($m)
        $path = $m.Groups[1].Value
        $uri  = "file:///" + $path.Replace('\', '/')
        return "$($esc)]8;;$($uri)$($esc)\$($path)$($esc)]8;;$($esc)\"
    })

    return $Text
}

# ====================== SAFE CURSOR MOVE ======================
function Set-CursorSafe {
    param([int]$row)
    $maxRow = [Console]::BufferHeight - 1
    if ($row -lt 0)       { $row = 0 }
    if ($row -gt $maxRow) { $row = $maxRow }
    [Console]::SetCursorPosition(0, $row)
}

function Get-StatusBarText {
    param($s = $script:lastStatus)
    $barWidth  = 16
    
    $limit = if ($script:CONTEXT_LIMIT) { $script:CONTEXT_LIMIT } else { 15000 }
    $ctxPct = if ($limit -gt 0) { $s.total / $limit } else { 0 }
    if ($ctxPct -gt 1.0) { $ctxPct = 1.0 }
    
    $maxOut = $script:GUARDRAILS.maxOutputTokens
    $outPct = if ($maxOut -gt 0) { $s.candidate / $maxOut } else { 0 }
    if ($outPct -gt 1.0) { $outPct = 1.0 }
    
    $ctxFill   = [int]($ctxPct * $barWidth)
    $outFill   = [int]($outPct * $barWidth)
    $ctxBar    = ("$BLK" * $ctxFill)  + ("$LBK" * ($barWidth - $ctxFill))
    $outBar    = ("$BLK" * $outFill)  + ("$LBK" * ($barWidth - $outFill))
    
    $finStr    = ""
    if ($s.finish -and $s.finish -ne "STOP") { $finStr = " stop:$($s.finish)" }
    
    $modelStr  = "  model:$($script:MODEL)"
    
    return "  ctx $ctxBar {0:P0} ($($s.total))   out $outBar {1:P0} ($($s.candidate))   prompt:$($s.prompt)$finStr$modelStr" -f $ctxPct, $outPct
}

function Read-SecureStringWithCancel {
    param([string]$Prompt)
    Write-Host "${Prompt}: " -NoNewline
    $secureString = New-Object System.Security.SecureString
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "Enter") { Write-Host ""; return $secureString }
        if ($key.Key -eq "Escape") { Write-Host " [Cancelled]"; return $null }
        if ($key.Key -eq "Backspace") {
            if ($secureString.Length -gt 0) {
                $secureString.RemoveAt($secureString.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        } else {
            $secureString.AppendChar($key.KeyChar)
            Write-Host "*" -NoNewline
        }
    }
}

function Read-HostWithCancel {
    param([string]$Prompt)
    Write-Host "${Prompt}: " -NoNewline
    $inputStr = ""
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "Enter") { Write-Host ""; return $inputStr }
        if ($key.Key -eq "Escape") { Write-Host " [Cancelled]"; return $null }
        if ($key.Key -eq "Backspace") {
            if ($inputStr.Length -gt 0) {
                $inputStr = $inputStr.Substring(0, $inputStr.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
        } else {
            $inputStr += $key.KeyChar
            Write-Host $key.KeyChar -NoNewline
        }
    }
}

# ====================== BAR TRACKER ======================
# Polls every 50ms while user is typing — if cursor moves to a new row,
# erases bar at old position and redraws it one line below new cursor row.
$script:barTrackerPS = $null
$script:barTrackerRS = $null
$script:barRow       = -1

function Start-BarTracker {
    param([int]$InitialBarRow, [string]$HighlightANSI)
    Stop-BarTracker
    $script:barRow = $InitialBarRow

    $script:barTrackerRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:barTrackerRS.Open()
    $script:barTrackerRS.SessionStateProxy.SetVariable('sharedBarRow',  ([ref]$script:barRow))
    $script:barTrackerRS.SessionStateProxy.SetVariable('statusText',    (Get-StatusBarText))
    $script:barTrackerRS.SessionStateProxy.SetVariable('darkPurple', $HighlightANSI)
    $script:barTrackerPS = [System.Management.Automation.PowerShell]::Create()
    $script:barTrackerPS.Runspace = $script:barTrackerRS
    [void]$script:barTrackerPS.AddScript({
        $lastCursorRow = -1
        $currentBarRow = $sharedBarRow.Value
        
        $esc = [char]27
        $ansiCyan = "$esc[36m"
        $ansiDarkBlueBG = "$esc[44m"
        $ansiReset = "$esc[0m"

        while ($true) {
            try {
                Start-Sleep -Milliseconds 50
                $curRow = [Console]::CursorTop
                if ($curRow -ne $lastCursorRow) {
                    $lastCursorRow = $curRow
                    $w = [Console]::WindowWidth
                    
                    # Erase old bar row
                    if ($currentBarRow -ge 0 -and $currentBarRow -lt [Console]::BufferHeight) {
                        $savedL = [Console]::CursorLeft
                        $savedT = [Console]::CursorTop
                        
                        if ($currentBarRow -eq $curRow) {
                            # We wrapped onto the bar line. 
                            # Clear from the cursor to the end of the row to remove bar text while keeping user text.
                            [Console]::SetCursorPosition($savedL, $currentBarRow)
                            [Console]::Write($darkPurple + (" " * ($w - $savedL - 1)))
                        } else {
                            # Standard erasure of old bar position
                            [Console]::SetCursorPosition(0, $currentBarRow)
                            [Console]::Write($ansiReset + (" " * ($w - 1)))
                        }
                        
                        [Console]::SetCursorPosition($savedL, $savedT)
                        [Console]::Write($darkPurple)
                    }
                    
                    # Redraw bar one line below current cursor
                    $newBarRow = $curRow + 1
                    if ($newBarRow -lt [Console]::BufferHeight) {
                        $savedL = [Console]::CursorLeft
                        $savedT = [Console]::CursorTop
                        [Console]::SetCursorPosition(0, $newBarRow)
                        $txt = $statusText
                        if ($txt.Length -gt ($w-1)) { $txt = $txt.Substring(0,$w-1) } else { $txt = $txt.PadRight($w-1) }
                        
                        [Console]::Write("${ansiCyan}${ansiDarkBlueBG}${txt}${ansiReset}")
                        [Console]::SetCursorPosition($savedL, $savedT)
                        [Console]::Write($darkPurple)
                        
                        $currentBarRow = $newBarRow
                        $sharedBarRow.Value = $newBarRow
                    }
                }
            } catch { }
        }
    })
    $script:barTrackerPS.BeginInvoke() | Out-Null
}

function Stop-BarTracker {
    if ($script:barTrackerPS) {
        try { $script:barTrackerPS.Stop(); $script:barTrackerPS.Dispose() } catch {}
        try { $script:barTrackerRS.Close(); $script:barTrackerRS.Dispose() } catch {}
        $script:barTrackerPS = $null; $script:barTrackerRS = $null
    }
}
function Get-VisualWidth {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    
    $width = 0
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
        $el = $enumerator.GetTextElement()
        
        # Explicit Overrides for your specific terminal font behavior
        # These render as 1-cell in your environment
        switch ($el[0]) {
            [char]0x2728 { $width += 1; continue } # ✨
            [char]0x2753 { $width += 1; continue } # ❓
            [char]0x2611 { $width += 1; continue } # ☑ (Alternate for ask_user)
        }

        # Check for Surrogate Pairs (most emojis)
        if ([char]::IsHighSurrogate($el[0])) {
            # Problematic 1-cell surrogates in your terminal
            if ($el -match "[\uD83D\uDEE1]|[\uD83C\uDF99]") { # 🛡, 🎙
                $width += 1
            } else {
                $width += 2
            }
        } else {
            # BMP characters: 1 cell unless in known wide list
            if ($el[0] -match "[\u2705\u274C\u26A1]") { # ✅, ❌, ⚡
                $width += 2
            } else {
                $width += 1
            }
        }
    }
    return $width
}

function Get-StandardToolLabel {
    param(
        [hashtable]$Tool,
        [hashtable]$Params
    )
    $icon = if ($Tool.Icon) { $Tool.Icon } else { "●" }
    $name = $Tool.Name
    $suffix = if ($Tool.FormatLabel) { & $Tool.FormatLabel $Params } else { "" }
    
    # Normalize Icon Slot to exactly 3 cells for perfect text alignment
    $vIconWidth = Get-VisualWidth -Text $icon
    $iconSlot = if ($vIconWidth -eq 1) { "$icon  " } else { "$icon " }

    if ([string]::IsNullOrWhiteSpace($suffix)) {
        return "$iconSlot$name"
    }
    return "$iconSlot$name -> $suffix"
}

function Draw-Box {
    param(
        [string[]]$Lines,
        [string]$Title = "",
        [int]$Width = 80,
        [ConsoleColor]$Color = "Cyan"
    )
    $esc = [char]27
    $inner  = $Width - 2
    $maxTextWidth = $inner - 2
    if ($maxTextWidth -lt 1) { return } # Failsafe for tiny widths

    # --- Start Text Wrapping ---
    $wrappedLines = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Lines) {
        foreach ($rawLine in $Lines) {
            if ($null -eq $rawLine) { $wrappedLines.Add(''); continue }
            
            $subLines = $rawLine.ToString() -split "`r?`n"
            foreach ($line in $subLines) {
                if ((Get-VisualWidth -Text $line) -le $maxTextWidth) {
                    $wrappedLines.Add($line)
                    continue
                }

                $rem = $line
                while ($rem.Length -gt 0) {
                    $vRemWidth = Get-VisualWidth -Text $rem
                    if ($vRemWidth -le $maxTextWidth) {
                        $wrappedLines.Add($rem)
                        break
                    }
                    
                    # Find last space within the max width
                    $breakIdx = 0
                    $vCurrent = 0
                    $lastSpaceIdx = -1
                    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($rem)
                    
                    $i = 0
                    while ($enum.MoveNext()) {
                        $el = $enum.GetTextElement()
                        $vw = Get-VisualWidth -Text $el
                        if ($vCurrent + $vw -gt $maxTextWidth) { break }
                        $vCurrent += $vw
                        $i += $el.Length
                        if ($el -eq " ") { $lastSpaceIdx = $i }
                    }

                    # if we have a space, and it's not the start of the line, break there
                    if ($lastSpaceIdx -gt 0) {
                        $breakIdx = $lastSpaceIdx
                        $wrappedLines.Add($rem.Substring(0, $breakIdx).TrimEnd())
                        $rem = $rem.Substring($breakIdx).TrimStart()
                    } else { 
                        # no space, so hard wrap at the character limit
                        $breakIdx = $i
                        if ($breakIdx -eq 0 -and $rem.Length -gt 0) {
                           # First character is already too wide, take just that one
                           $enum.Reset(); $enum.MoveNext() | Out-Null
                           $breakIdx = $enum.Current.Length
                        }
                        $wrappedLines.Add($rem.Substring(0, $breakIdx))
                        $rem = $rem.Substring($breakIdx)
                    }
                }
            }
        }
    }
    # --- End Text Wrapping ---

    $top    = "$TL" + ("$H" * $inner) + "$TR"
    $bottom = "$BL" + ("$H" * $inner) + "$BR"
    $empty  = "$V" + (" " * $inner) + "$V"

    Write-Host $top -ForegroundColor $Color
    if ($Title) {
        # Simple truncate for title
        $vTitleWidth = Get-VisualWidth -Text $Title
        $displayTitle = $Title
        if ($vTitleWidth -gt $maxTextWidth) {
            # Find a good truncation point
            $charEnum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Title)
            $truncVWidth = 0
            $truncIdx = 0
            while($charEnum.MoveNext()) {
                $el = $charEnum.GetTextElement()
                $vEl = Get-VisualWidth -Text $el
                if ($truncVWidth + $vEl + 3 -gt $maxTextWidth) { break }
                $truncVWidth += $vEl
                $truncIdx += $el.Length
            }
            $displayTitle = $Title.Substring(0, $truncIdx) + '...'
            $vTitleWidth = Get-VisualWidth -Text $displayTitle
        }
        $pad = $inner - $vTitleWidth - 2
        if ($pad -lt 0) { $pad = 0 }
        
        Write-Host ("$V " + $displayTitle + (" " * $pad)) -NoNewline -ForegroundColor $Color
        Write-Host "$esc[$($Width)G$V" -ForegroundColor $Color
        Write-Host $empty -ForegroundColor $Color
    }

    foreach ($line in $wrappedLines) {
        $vLineWidth = Get-VisualWidth -Text $line
        $pad = $inner - $vLineWidth - 2
        if ($pad -lt 0) { $pad = 0 }

        Write-Host ("$V " + $line + (" " * $pad)) -NoNewline -ForegroundColor $Color
        # SNAP: Anchor the right border to the exact column
        Write-Host "$esc[$($Width)G$V" -ForegroundColor $Color
    }
    Write-Host $bottom -ForegroundColor $Color
}

# ====================== SPINNER (Smooth & Stable) ======================
function Start-Spinner {
    param([string]$Label = "Thinking")
    # Clean up previous if exists
    Stop-Spinner

    $script:spinnerRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()        
    $script:spinnerRS.Open()
    $script:spinnerRS.SessionStateProxy.SetVariable('spinnerLabel', $Label)
    $script:spinnerPS = [System.Management.Automation.PowerShell]::Create()
    $script:spinnerPS.Runspace = $script:spinnerRS
    [void]$script:spinnerPS.AddScript({
        $frames = @('|', '/', '-', '\')
        $i = 0
        try { [Console]::CursorVisible = $false } catch {}
        while ($true) {
            try {
                # Fixed length message to prevent "stuttering" from varying lengths
                $msg = "`r  $($frames[$i % 4])  $spinnerLabel...           "
                [Console]::Write($msg)
            } catch { break }
            $i++
            Start-Sleep -Milliseconds 100
        }
    })
    $script:spinnerHandle = $script:spinnerPS.BeginInvoke()
}

function Stop-Spinner {
    if ($script:spinnerPS) {
        try {
            $script:spinnerPS.Stop()
            $script:spinnerPS.Dispose()
            $script:spinnerRS.Close()
            $script:spinnerRS.Dispose()
        } catch { }
        $script:spinnerPS = $null
    }
    # Clear the spinner line fully and reset cursor to start of line
    [Console]::Write("`r" + (" " * 60) + "`r")
    try { [Console]::CursorVisible = $true } catch {}
}

# ====================== ARROW-KEY MENU ======================
function Show-ArrowMenu {
    param(
        [string[]]$Options,
        [string]$Title = "",
        [int]$Width = 100,
        [int]$Default = 0
    )
    $selected   = $Default
    $esc        = [char]27
    $inner      = $Width - 2
    $maxTextWidth = $inner - 2

    # --- Wrap Title ---
    $wrappedTitle = New-Object System.Collections.Generic.List[string]
    if ($Title) {
        $subLines = $Title.ToString() -split "`r?`n"
        foreach ($line in $subLines) {
            if ((Get-VisualWidth -Text $line) -le $maxTextWidth) {
                $wrappedTitle.Add($line)
                continue
            }
            $rem = $line
            while ($rem.Length -gt 0) {
                $vRemWidth = Get-VisualWidth -Text $rem
                if ($vRemWidth -le $maxTextWidth) { $wrappedTitle.Add($rem); break }
                $breakIdx = 0; $vCurrent = 0; $lastSpaceIdx = -1
                $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($rem)
                $i = 0
                while ($enum.MoveNext()) {
                    $el = $enum.GetTextElement()
                    $vw = Get-VisualWidth -Text $el
                    if ($vCurrent + $vw -gt $maxTextWidth) { break }
                    $vCurrent += $vw; $i += $el.Length
                    if ($el -eq " ") { $lastSpaceIdx = $i }
                }
                if ($lastSpaceIdx -gt 0) {
                    $wrappedTitle.Add($rem.Substring(0, $lastSpaceIdx).TrimEnd())
                    $rem = $rem.Substring($lastSpaceIdx).TrimStart()
                } else { 
                    $breakIdx = $i
                    if ($breakIdx -eq 0 -and $rem.Length -gt 0) { $enum.Reset(); $enum.MoveNext() | Out-Null; $breakIdx = $enum.Current.Length }
                    $wrappedTitle.Add($rem.Substring(0, $breakIdx)); $rem = $rem.Substring($breakIdx)
                }
            }
        }
    }

    $titleLines = if ($wrappedTitle.Count -gt 0) { $wrappedTitle.Count + 1 } else { 0 }
    $totalLines = 1 + $titleLines + 1 + $Options.Count + 1 + 1 + 1

    function Write-MenuLine {
        param([string]$text, [bool]$highlight)
        $display = $text
        $vWidth = Get-VisualWidth -Text (" " + $display)
        if ($vWidth -gt ($Width - 3)) {
            # Truncate option if too long
            $truncVWidth = 0
            $truncIdx = 0
            $charEnum = [System.Globalization.StringInfo]::GetTextElementEnumerator($display)
            while($charEnum.MoveNext()) {
                $el = $charEnum.GetTextElement()
                $vEl = Get-VisualWidth -Text $el
                if ($truncVWidth + $vEl + 4 -gt ($Width - 3)) { break }
                $truncVWidth += $vEl
                $truncIdx += $el.Length
            }
            $display = $display.Substring(0, $truncIdx) + "..."
            $vWidth = Get-VisualWidth -Text (" " + $display)
        }

        $pad = ($Width - 2) - $vWidth
        if ($pad -lt 0) { $pad = 0 }

        if ($highlight) {
            Write-Host "$V" -NoNewline -ForegroundColor Yellow -BackgroundColor Black
            Write-Host (" " + $display + (" " * $pad)) -NoNewline -BackgroundColor DarkYellow -ForegroundColor Black
            Write-Host "$esc[$($Width)G$V" -ForegroundColor Yellow -BackgroundColor Black
        } else {
            Write-Host ("$V " + $display + (" " * $pad)) -NoNewline -ForegroundColor Yellow -BackgroundColor Black
            Write-Host "$esc[$($Width)G$V" -ForegroundColor Yellow -BackgroundColor Black
        }
    }

    function Render-Menu {
        Set-CursorSafe $script:menuStartRow
        $top    = "$TL" + ("$H" * $inner) + "$TR"
        $bottom = "$BL" + ("$H" * $inner) + "$BR"
        $empty  = "$V" + (" " * $inner) + "$V"
        Write-Host $top -ForegroundColor Yellow
        if ($wrappedTitle.Count -gt 0) {
            foreach ($tLine in $wrappedTitle) {
                $vLineW = Get-VisualWidth -Text $tLine
                $pad = $inner - $vLineW - 2
                if ($pad -lt 0) { $pad = 0 }
                Write-Host ("$V " + $tLine + (" " * $pad)) -NoNewline -ForegroundColor Yellow
                Write-Host "$esc[$($Width)G$V" -ForegroundColor Yellow
            }
            Write-Host $empty -ForegroundColor Yellow
        }
        Write-Host $empty -ForegroundColor Yellow
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $prefix = if ($i -eq $selected) { "$DOT " } else { "  " }
            Write-MenuLine ($prefix + $Options[$i]) ($i -eq $selected)
        }
        Write-Host $empty -ForegroundColor Yellow
        Write-Host $bottom -ForegroundColor Yellow
        Write-Host ("  Use [Up/Down] to navigate, [Enter] to confirm, [Esc] to cancel   ") -ForegroundColor DarkGray
    }

    function Exit-Menu {
        [Console]::CursorVisible = $true
        Set-CursorSafe ($script:menuStartRow + $totalLines)
        Write-Host ""
    }

    $spaceNeeded = $totalLines + 1
    $currentRow  = [Console]::CursorTop
    $bufferH     = [Console]::BufferHeight
    if (($currentRow + $spaceNeeded) -ge $bufferH) {
        1..$spaceNeeded | ForEach-Object { Write-Host "" }
        $currentRow = [Console]::CursorTop - $spaceNeeded
        if ($currentRow -lt 0) { $currentRow = 0 }
    }
    $script:menuStartRow   = $currentRow
    [Console]::CursorVisible = $false

    try {
        Render-Menu
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($selected -gt 0) { $selected-- }; Render-Menu }
                "DownArrow" { if ($selected -lt ($Options.Count - 1)) { $selected++ }; Render-Menu }      
                "Enter"     { Exit-Menu; return $selected }
                "Escape"    { Exit-Menu; return -1 }
                default {
                    $digit = [int][char]$key.KeyChar - [int][char]'1'
                    if ($digit -ge 0 -and $digit -lt $Options.Count) {
                        $selected = $digit; Render-Menu; Exit-Menu; return $selected
                    }
                }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}
