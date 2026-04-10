# tools/motion_detector.ps1 v1.1.0
# Responsibility: Blocking motion detection using FFmpeg.
# Workflow: CLI -> Invoke-MotionDetectorTool -> [Blocking Loop] -> Motion -> Return to Gemini

$script:GemmaSurveillanceArt = @'
  |`-._/\_.-`|   ♛GEMMA____  ___  ___  ________  ________  ________      
  |    ┇┇    |    |\   ____\|\  \|\  \|\   __  \|\   __  \|\   ___ \     
  |___/⛬ \___|    \ \  \___|\ \  \\\  \ \  \|\  \ \  \|\  \ \  \_|\ \    
  |__[[GG]]__|     \ \  \  __\ \  \\\  \ \   __  \ \   _  _\ \  \ \\ \   
  \  \╚╬╬╝/  /      \ \  \|\  \ \  \\\  \ \  \ \  \ \  \\  \\ \  \_\\ \  
   \   ┇┇   /        \ \_______\ \_______\ \__\ \__\ \__\\ _\\ \_______\ 
    \  ┇┇  /          \|▓▓▓▓▓▓▓|\|▓▓▓▓▓▓▓|\|▓▓|\|▓▓|\|▓▓|\|▓▓|\|▓▓▓▓▓▓▓|
     '.┇┇.'                                                              
'@

function Invoke-MotionDetectorTool {
    param(
        [string]$action = "watch",   # "watch" is now the primary blocking action
        [float]$sensitivity = 0.02, # Motion threshold
        [int]$timeout_sec = 60,     # How long to wait before giving up
        [bool]$alarm = $false,      # Whether to play a sound on detection
        [string]$night_mode = "auto", # "true" | "false" | "auto"
        [bool]$photo = $false       # Capture a snapshot if motion is detected
    )

    Write-Host $script:GemmaSurveillanceArt -ForegroundColor Cyan

    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "C:\Users\kevin\Documents\AI\GemmaCLI" }

    $tempDir = Join-Path $scriptRootDir "temp"
    if (-not (Test-Path $tempDir)) { New-Item $tempDir -ItemType Directory -Force | Out-Null }

    $internalLog = Join-Path $tempDir "ffmpeg_motion_internal.log"
    $errorLog = Join-Path $tempDir "ffmpeg_motion_error.log"

    if ($action -eq "watch") {
        # Sensitivity Scaling: Bring human-friendly numbers into FFmpeg range (0.0 - 1.0)
        # 1.0+ becomes percentage (e.g. 5 -> 0.05)
        # 0.1 - 0.9 becomes 10ths (e.g. 0.2 -> 0.02)
        if ($sensitivity -ge 1.0) { 
            $sensitivity = $sensitivity / 100 
        } elseif ($sensitivity -ge 0.1) {
            $sensitivity = $sensitivity / 10
        }
        
        if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue)) { return "ERROR: FFmpeg is required." }

        # Clear old logs
        if (Test-Path $internalLog) { Remove-Item $internalLog -Force }
        if (Test-Path $errorLog) { Remove-Item $errorLog -Force }
        New-Item $internalLog -ItemType File -Force | Out-Null

        # Auto-detect camera
        $ffmpegOutput = ffmpeg -list_devices true -f dshow -i dummy 2>&1
        $ffmpegLines = $ffmpegOutput | ForEach-Object { $_.ToString() }
        $camMatch = $ffmpegLines | Select-String -Pattern '"([^"]+)" \(video\)'
        $camName = "Integrated Camera"
        if ($camMatch) { $camName = $camMatch[0].Matches[0].Groups[1].Value }

        Write-Host "[MOTION] Arming in 10 seconds (get into position)..." -ForegroundColor Yellow
        
        $actualNightMode = $false
        if ($night_mode -eq "true" -or $night_mode -eq "True" -or $night_mode -eq $true) { $actualNightMode = $true }
        elseif ($night_mode -eq "false" -or $night_mode -eq "False" -or $night_mode -eq $false) { $actualNightMode = $false }
        else {
            # AUTO MODE: Sample brightness during the countdown
            Write-Host "[MOTION] Sampling room brightness..." -ForegroundColor DarkGray
            
            # Use a smaller sleep before FFmpeg so FFmpeg has time to run within the arming window
            Start-Sleep -Seconds 2
            
            # Robust Sampling: Scale frame to 1x1 pixel and use showinfo to get the mean luma.
            # This is much more reliable than signalstats across different FFmpeg builds.
            $sampleOutput = ffmpeg -y -loglevel repeat -t 1 -f dshow -i "video=$camName" -vf "scale=1:1,format=gray,showinfo" -f null - 2>&1
            
            # Look for the showinfo mean luma value (e.g. mean:[123])
            $lumaMatches = $sampleOutput | ForEach-Object { $_.ToString() } | Select-String "mean:\[(\d+)\]"
            
            if ($lumaMatches) {
                # Grab the last match (the most recent frame sampled)
                $luma = [int]$lumaMatches[-1].Matches[0].Groups[1].Value
                if ($luma -lt 60) {
                    $actualNightMode = $true
                    Write-Host "[MOTION] Low light detected ($luma). Activating Night Mode." -ForegroundColor Cyan
                } else {
                    Write-Host "[MOTION] Ambient light sufficient ($luma). Day Mode active." -ForegroundColor Yellow
                }
            } else {
                # Check for specific hardware errors
                $rawText = ($sampleOutput | ForEach-Object { $_.ToString() }) -join " "
                if ($rawText -match "Access is denied|Device or resource busy") {
                    Write-Host "[MOTION] Sampling failed: Camera is in use by another app." -ForegroundColor Red
                } else {
                    Write-Host "[MOTION] Sampling failed (Metadata timeout). Defaulting to Day Mode." -ForegroundColor Yellow
                }
            }
            # Final short pause to finish the 10s arming window
            Start-Sleep -Seconds 2
        }

        $modeLabel = if ($actualNightMode) { "NIGHT (Gamma Boost)" } else { "DAY (Standard)" }
        Write-Host "[MOTION] Watching $camName ($modeLabel, Sens: $sensitivity)..." -ForegroundColor Gray
        
        # Keep system awake only if plugged in (Smart Power Logic)
        $ste = $null
        $ES_CONTINUOUS = [uint32]2147483648
        try {
            $isPluggedIn = $true # Default for desktops
            try { $isPluggedIn = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue).PowerOnline } catch {}
            
            if ($isPluggedIn -eq $false) {
                Write-Host "[MOTION] Power Status: BATTERY (Sleep prevention skipped)" -ForegroundColor Gray
            } else {
                $steCode = @"
                [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
                public static extern uint SetThreadExecutionState(uint esFlags);
"@
                $ste = Add-Type -MemberDefinition $steCode -Name "Win32Sleep$([Guid]::NewGuid().ToString('N'))" -Namespace "Win32" -PassThru
                # ES_CONTINUOUS (2147483648) | ES_SYSTEM_REQUIRED (1) | ES_DISPLAY_REQUIRED (2)
                $flags = [uint32]2147483651
                $ste::SetThreadExecutionState($flags) | Out-Null
                Write-Host "[MOTION] Power Status: AC (Sleep & Display Prevention ENABLED)" -ForegroundColor Green
            }
        } catch { 
            Write-Host " [!] Warning: Could not enable sleep prevention: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Start FFmpeg in background
        # Filters: tmix for temporal averaging (reduces TV flash false positives), eq=gamma for low-light boost
        $filters = @()
        if ($actualNightMode) { $filters += "eq=gamma=1.5" }
        $filters += "tmix=frames=3,format=yuv420p,select='gt(scene,$sensitivity)',metadata=print:file='$(Split-Path $internalLog -Leaf)':direct=1"
        $vfFilter = $filters -join ","
        $ffArgs = "-y -f dshow -i `"video=$camName`" -vf `"$vfFilter`" -f null -"
        
        $ffProc = $null
        try {
            # Move to temp dir so FFmpeg writes to the right relative path
            Push-Location $tempDir
            $ffProc = Start-Process ffmpeg -ArgumentList $ffArgs -NoNewWindow -PassThru -RedirectStandardError "ffmpeg_motion_error.log"
            
            $start = Get-Date
            $motionDetected = $false
            
            # BLOCKING LOOP
            while (((Get-Date) - $start).TotalSeconds -lt $timeout_sec) {
                if ($ffProc.HasExited) {
                    return "ERROR: FFmpeg exited unexpectedly. Check $errorLog"
                }

                if ((Get-Item $internalLog).Length -gt 0) {
                    $motionDetected = $true
                    break
                }
                Start-Sleep -Milliseconds 500
            }

            if ($motionDetected) {
                $ts = Get-Date -Format "HH:mm:ss"
                $alarmTag = if ($alarm) { " PLAY_SOUND:Alarm01" } else { "" }
                
                $photoTag = ""
                if ($photo) {
                    Write-Host "[MOTION] Capturing photo..." -ForegroundColor Cyan
                    $photoPath = Join-Path $tempDir "motion_capture.jpg"
                    # Capture 1 frame immediately
                    & ffmpeg -y -f dshow -i "video=$camName" -frames:v 1 -q:v 2 $photoPath 2>$null
                    if (Test-Path $photoPath) {
                        $absPath = (Get-Item $photoPath).FullName
                        $photoTag = "`n[PHOTO] Snapshot saved to: $absPath"
                    }
                }

                return "CONSOLE::$($script:GemmaSurveillanceArt)`n🚨 MOTION DETECTED AT $ts!$alarmTag$photoTag::END_CONSOLE::OK: Motion was detected on '$camName' at $ts."
            } else {
                return "CONSOLE::$($script:GemmaSurveillanceArt)`nOK: No motion detected within the $timeout_sec second timeout.::END_CONSOLE::OK: Timeout reached."
            }

        } catch {
            return "ERROR: Motion detection failed. $($_.Exception.Message)"
        } finally {
            if ($ste) { 
                $ste::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null 
                Write-Host "[MOTION] Sleep Prevention: DISABLED" -ForegroundColor Yellow
            }
            if ($ffProc -and -not $ffProc.HasExited) {
                Stop-Process -Id $ffProc.Id -Force -ErrorAction SilentlyContinue
            }
            Pop-Location
        }
    }

    return "ERROR: Unknown action '$action'."
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "motion_detector"
    Icon        = "🛡"
    Interactive = $true
    Category    = @("Security", "Vision")
    Behavior    = "Actively watches the camera for motion. This tool BLOCKS (shows a spinner) until movement is detected or it times out. Use this when you want to 'listen' for an intruder before deciding to engage with voice or video."
    Description = "Active motion listener/sensor."
    Parameters  = @{
        action      = "string - optional. Defaults to 'watch'."
        sensitivity = "float - optional. Motion threshold (default 0.02). Lower is more sensitive."
        timeout_sec = "int - optional. How long to wait for motion (default 60)."
        alarm       = "bool - optional. If true, plays an alarm sound when motion is detected."
        night_mode  = "string - optional. 'true', 'false', or 'auto' (default). Enhances low-light vision."
        photo       = "bool - optional. If true, captures a snapshot (temp/motion_capture.jpg) on detection."
    }
    Example     = '<tool_call>{ "name": "motion_detector", "parameters": { "action": "watch", "timeout_sec": 30, "photo": true } }</tool_call>'
    FormatLabel = { 
        param($p) 
        $t = if ($p.timeout_sec) { $p.timeout_sec } else { 60 }
        $nm = if ($p.night_mode) { $p.night_mode } else { "auto" }
        $cam = if ($p.photo) { " 📸" } else { "" }
        "(timeout: $($t)s$(if($nm -ne 'false'){' [NIGHT: '+$nm+']'})$cam)" 
    }
    Execute     = { param($params) Invoke-MotionDetectorTool @params }
}
