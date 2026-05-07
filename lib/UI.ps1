# lib/UI.ps1 v0.1.2
# Responsibility: Contains UI-related functions like Draw-Box, Show-ArrowMenu, Start-Spinner, and Start-BarTracker.
# Keeps the main loop clean and focused on orchestration.

# ====================== SAFE CURSOR MOVE ======================
function Set-CursorSafe {
    param([int]$row)
    $maxRow = [Console]::BufferHeight - 1
    if ($row -lt 0)       { $row = 0 }
    if ($row -gt $maxRow) { $row = $maxRow }
    [Console]::SetCursorPosition(0, $row)
}

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

function Get-VisualWidth {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    # Use StringInfo to count "Text Elements" (grapheme clusters)
    $si = [System.Globalization.StringInfo]::new($Text)
    $len = $si.LengthInTextElements

    $width = 0
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enumerator.MoveNext()) {
         $el = $enumerator.GetTextElement()
         # Heuristic for 2-cell emojis: Surrogates or characters outside BMP
         if ([char]::IsHighSurrogate($el[0]) -or $el.Length -gt 1) {
             $width += 2
         } else {
             # Check specific BMP ranges known for 2-cell display if needed
             # For now, this covers the most common cases.
             $width += 1
         }
     }
     return $width
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

# ====================== CONSOLE SYNC ======================
$script:consoleLock = New-Object Object

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
    $script:barTrackerRS.SessionStateProxy.SetVariable('consoleLock', $script:consoleLock)
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
                    
                    [System.Threading.Monitor]::Enter($consoleLock)
                    try {
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
                    } finally { [System.Threading.Monitor]::Exit($consoleLock) }
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

function Get-StandardToolLabel {
    param(
        [hashtable]$Tool,
        [hashtable]$Params
    )
    $icon = if ($Tool.Icon) { $Tool.Icon } else { [char]0x25CF } # $DOT
    $name = $Tool.Name
    $suffix = if ($Tool.FormatLabel) { & $Tool.FormatLabel $Params } else { "" }
    
    if ([string]::IsNullOrWhiteSpace($suffix)) {
        return "$icon $name"
    }
    return "$icon $name -> $suffix"
}

function Draw-Box {
    param(
        [string[]]$Lines,
        [string]$Title = "",
        [int]$Width = 80,
        [ConsoleColor]$Color = "Cyan"
    )
    $inner  = $Width - 2
    $top    = "$TL" + ("$H" * $inner) + "$TR"
    $bottom = "$BL" + ("$H" * $inner) + "$BR"
    $empty  = "$V" + (" " * $inner) + "$V"

    # Detect if we have a real console cursor (fails in piped/redirected output)
    $hasConsoleCursor = $false
    try {
        [void][Console]::CursorTop
        $hasConsoleCursor = $true
    } catch { }

    Write-Host $top -ForegroundColor $Color
    if ($Title) {
        $vTitleWidth = Get-VisualWidth -Text $Title
        $pad = $inner - $vTitleWidth - 2
        if ($pad -lt 0) { $pad = 0 }
        $displayTitle = $Title
        # Note: Truncation logic may need to be smarter for ANSI, but Title is usually plain
        if ($Title.Length -gt ($inner - 2)) { $displayTitle = $Title.Substring(0, $inner - 2) }
        
        if ($hasConsoleCursor) {
            $row = [Console]::CursorTop
            Write-Host "$V " -NoNewline -ForegroundColor $Color
            Write-Host $displayTitle -NoNewline -ForegroundColor $Color
            [Console]::SetCursorPosition($Width - 1, $row)
            Write-Host "$V" -ForegroundColor $Color
        } else {
            Write-Host ("$V " + $displayTitle + (" " * $pad) + " $V") -ForegroundColor $Color
        }
        Write-Host $empty -ForegroundColor $Color
    }
    foreach ($line in $Lines) {
        $displayLine = $line
        # Truncation logic based on visual width
        if ((Get-VisualWidth -Text $line) -gt ($inner - 2)) { 
            # Fallback to simple substring for now, as truncation of ANSI is complex
            $displayLine = $line.Substring(0, [math]::Min($line.Length, $inner - 2)) 
        }
        $displayLine = Convert-ToHyperlink -Text $displayLine
        
        if ($hasConsoleCursor) {
            $row = [Console]::CursorTop
            Write-Host "$V " -NoNewline -ForegroundColor $Color
            Write-Host $displayLine -NoNewline -ForegroundColor $Color
            # Force right border to exact column, immune to character width drift
            [Console]::SetCursorPosition($Width - 1, $row)
            Write-Host "$V" -ForegroundColor $Color
        } else {
            $vLineWidth = Get-VisualWidth -Text $displayLine
            $pad = $inner - $vLineWidth - 2
            if ($pad -lt 0) { $pad = 0 }
            Write-Host ("$V " + $displayLine + (" " * $pad) + " $V") -ForegroundColor $Color
        }
    }
    Write-Host $bottom -ForegroundColor $Color
}

# ====================== SPINNER (Smooth & Stable) ======================
function Start-Spinner {
    param([string]$Label = "Thinking")
    # Clean up previous if exists
    Stop-Spinner

    $script:spinnerRow = [Console]::CursorTop
    $script:spinnerRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()        
    $script:spinnerRS.Open()
    $script:spinnerRS.SessionStateProxy.SetVariable('spinnerLabel', $Label)
    $script:spinnerRS.SessionStateProxy.SetVariable('spinnerRow', $script:spinnerRow)
    $script:spinnerRS.SessionStateProxy.SetVariable('consoleLock', $script:consoleLock)
    $script:spinnerPS = [System.Management.Automation.PowerShell]::Create()
    $script:spinnerPS.Runspace = $script:spinnerRS
    [void]$script:spinnerPS.AddScript({
        $frames = @('|', '/', '-', '\')
        $i = 0
        try { [Console]::CursorVisible = $false } catch {}
        while ($true) {
            try {
                $w = [Console]::WindowWidth
                $savedL = [Console]::CursorLeft
                $savedT = [Console]::CursorTop
                
                [System.Threading.Monitor]::Enter($consoleLock)
                try {
                    [Console]::SetCursorPosition(0, $spinnerRow)
                    $msg = "  $($frames[$i % 4])  $spinnerLabel...           "
                    if ($msg.Length -gt $w) { $msg = $msg.Substring(0, $w) }
                    [Console]::Write($msg.PadRight($w))
                    
                    [Console]::SetCursorPosition($savedL, $savedT)
                } finally { [System.Threading.Monitor]::Exit($consoleLock) }
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
            # Wait for the background thread to actually exit
            $null = $script:spinnerPS.EndInvoke($script:spinnerHandle)
            $script:spinnerPS.Dispose()
            $script:spinnerRS.Close()
            $script:spinnerRS.Dispose()
        } catch { }
        
        # Clear the spinner line using the saved row
        if ($null -ne $script:spinnerRow) {
            $w = [Console]::WindowWidth
            $savedL = [Console]::CursorLeft
            $savedT = [Console]::CursorTop
            
            [Console]::SetCursorPosition(0, $script:spinnerRow)
            [Console]::Write(" " * $w)
            [Console]::SetCursorPosition($savedL, $savedT)
        }
        
        $script:spinnerPS = $null
    }
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
    $inner      = $Width - 2
    $titleLines = if ($Title) { 2 } else { 0 }
    $totalLines = 1 + $titleLines + 1 + $Options.Count + 1 + 1 + 1

    function Write-MenuLine {
        param([string]$text, [bool]$highlight)
        if ($highlight) {
            Write-Host "$V" -NoNewline -ForegroundColor Yellow
            Write-Host (" " + $text + " ") -NoNewline -BackgroundColor DarkYellow -ForegroundColor Black
            $currentCol = [Console]::CursorLeft
            $spacesNeeded = ($Width - 1) - $currentCol
            if ($spacesNeeded -gt 0) {
                Write-Host (" " * $spacesNeeded) -NoNewline -BackgroundColor DarkYellow -ForegroundColor Black
            }
            Write-Host "$V" -ForegroundColor Yellow
        } else {
            Write-Host "$V " -NoNewline -ForegroundColor Yellow
            Write-Host $text -NoNewline -ForegroundColor Yellow
            $currentCol = [Console]::CursorLeft
            $spacesNeeded = ($Width - 1) - $currentCol
            if ($spacesNeeded -gt 0) {
                Write-Host (" " * $spacesNeeded) -NoNewline -ForegroundColor Yellow
            }
            Write-Host "$V" -ForegroundColor Yellow
        }
    }

    function Render-Menu {
        Set-CursorSafe $script:menuStartRow
        $top    = "$TL" + ("$H" * $inner) + "$TR"
        $bottom = "$BL" + ("$H" * $inner) + "$BR"
        $empty  = "$V" + (" " * $inner) + "$V"
        Write-Host $top -ForegroundColor Yellow
        if ($Title) {
            $displayTitle = $Title
            if ($Title.Length -gt ($inner - 2)) { $displayTitle = $Title.Substring(0, $inner - 2) }
            Write-Host "$V " -NoNewline -ForegroundColor Yellow
            Write-Host $displayTitle -NoNewline -ForegroundColor Yellow
            $currentCol = [Console]::CursorLeft
            $spacesNeeded = ($Width - 1) - $currentCol
            if ($spacesNeeded -gt 0) {
                Write-Host (" " * $spacesNeeded) -NoNewline -ForegroundColor Yellow
            }
            Write-Host "$V" -ForegroundColor Yellow
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