# lib/UI.ps1
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

function Get-StatusBarText {
    param($s = $script:lastStatus)
    $barWidth  = 16
    
    $ctxPct = if ($CONTEXT_WINDOW -gt 0) { $s.total / $CONTEXT_WINDOW } else { 0 }
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

    Write-Host $top -ForegroundColor $Color
    if ($Title) {
        $pad = $inner - $Title.Length - 2
        if ($pad -lt 0) { $pad = 0 }
        Write-Host ("$V " + $Title + (" " * $pad) + " $V") -ForegroundColor $Color
        Write-Host $empty -ForegroundColor $Color
    }
    foreach ($line in $Lines) {
        if ($line.Length -gt ($inner - 2)) { $line = $line.Substring(0, $inner - 2) }
        $pad = $inner - $line.Length - 2
        if ($pad -lt 0) { $pad = 0 }
        Write-Host ("$V " + $line + (" " * $pad) + " $V") -ForegroundColor $Color
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
    # Clear the spinner line fully
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
    $inner      = $Width - 2
    $titleLines = if ($Title) { 2 } else { 0 }
    $totalLines = 1 + $titleLines + 1 + $Options.Count + 1 + 1 + 1

    function Write-MenuLine {
        param([string]$text, [bool]$highlight)
        $pad = $inner - $text.Length - 2
        if ($pad -lt 0) { $pad = 0; $text = $text.Substring(0, $inner - 2) }
        if ($highlight) {
            Write-Host "$V" -NoNewline -ForegroundColor Yellow
            Write-Host (" " + $text + (" " * $pad) + " ") -NoNewline -BackgroundColor DarkYellow -ForegroundColor Black
            Write-Host "$V" -ForegroundColor Yellow
        } else {
            Write-Host ("$V " + $text + (" " * $pad) + " $V") -ForegroundColor Yellow
        }
    }

    function Render-Menu {
        Set-CursorSafe $script:menuStartRow
        $top    = "$TL" + ("$H" * $inner) + "$TR"
        $bottom = "$BL" + ("$H" * $inner) + "$BR"
        $empty  = "$V" + (" " * $inner) + "$V"
        Write-Host $top -ForegroundColor Yellow
        if ($Title) {
            $pad = $inner - $Title.Length - 2
            if ($pad -lt 0) { $pad = 0 }
            Write-Host ("$V " + $Title + (" " * $pad) + " $V") -ForegroundColor Yellow
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
