# ===============================================
# GemmaCLI Tool - stream_twitch.ps1 v1.6.0
# Responsibility: Streams the Gemma CLI window via FFmpeg to Twitch.
# Capture: gdigrab desktop with window coordinates (GetWindowRect).
# Interactive: runs on main thread so GetForegroundWindow() returns the CLI window.
# ===============================================

function Invoke-StreamTwitchTool {
    param(
        [string]$action,
        [string]$preset = "Medium"
    )

    $RTMP_URL = "rtmp://live.twitch.tv/app/"

    if ($action -notin @('start', 'stop')) {
        return "ERROR: action must be 'start' or 'stop'."
    }

    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "." }
    $tempDir = Join-Path $scriptRootDir "temp"
    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
    $pidFile = Join-Path $tempDir "stream_twitch.pid"

    if ($action -eq 'stop') {
        if (-not (Test-Path $pidFile)) {
            return "CONSOLE::No active Twitch stream found.::END_CONSOLE::ERROR: No stream is running."
        }

        $oldPid = $null
        try {
            $rawPid = [System.IO.File]::ReadAllText($pidFile)
            $oldPid = [int]$rawPid.Trim()
        } catch {
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            return "CONSOLE::Stream PID file was corrupt. Cleaned up.::END_CONSOLE::ERROR: Could not read stream PID."
        }

        try {
            Stop-Process -Id $oldPid -Force -ErrorAction Stop
            Remove-Item $pidFile -Force
            return "CONSOLE::Twitch stream stopped.::END_CONSOLE::OK: Stream stopped."
        } catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            return "CONSOLE::Twitch stream was not running (stale PID).::END_CONSOLE::OK: Stream stopped (was not active)."
        } catch {
            return "CONSOLE::ERROR: Could not stop stream. $($_.Exception.Message)::END_CONSOLE::ERROR: Could not stop stream. $($_.Exception.Message)"
        }
    }

    if (Test-Path $pidFile) {
        try {
            $rawPid = [System.IO.File]::ReadAllText($pidFile)
            $existing = [int]$rawPid.Trim()
            if (Get-Process -Id $existing -ErrorAction SilentlyContinue) {
                return "CONSOLE::Already streaming to Twitch (PID $existing).::END_CONSOLE::ERROR: Stream already active. Use 'stop' first."
            }
        } catch { }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        return "CONSOLE::ERROR: ffmpeg not found in PATH. Install ffmpeg first.::END_CONSOLE::ERROR: ffmpeg not found in PATH. Install ffmpeg first."
    }

    $streamKey = Get-StoredKey -keyName "stream_twitch"
    if ([string]::IsNullOrWhiteSpace($streamKey)) {
        return "CONSOLE::ERROR: No Twitch stream key stored. Enable the 'stream_twitch' tool in /settings to enter your key.::END_CONSOLE::ERROR: No Twitch stream key stored. Enable the 'stream_twitch' tool in /settings to enter your key."
    }

    # ── Detect the CLI window (in focus after approval on main thread) ──
    if (-not ("Win32Capture" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32Capture {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
    public struct RECT  { public int Left; public int Top; public int Right; public int Bottom; }
    public struct POINT { public int X; public int Y; }
}
'@
    }

    [Win32Capture]::SetProcessDPIAware() | Out-Null
    $hWnd = [Win32Capture]::GetForegroundWindow()

    $sb = New-Object System.Text.StringBuilder 256
    [Win32Capture]::GetWindowText($hWnd, $sb, 256) | Out-Null
    $windowTitle = $sb.ToString()

    if ([string]::IsNullOrWhiteSpace($windowTitle)) {
        return "CONSOLE::ERROR: Could not detect the CLI window title.::END_CONSOLE::ERROR: Could not detect the CLI window title."
    }

    # Gather coords from all three Win32 methods for comparison.
    $wr    = New-Object Win32Capture+RECT
    [void][Win32Capture]::GetWindowRect($hWnd, [ref]$wr)

    $dwm   = New-Object Win32Capture+RECT
    $dwmSz = [System.Runtime.InteropServices.Marshal]::SizeOf($dwm)
    $dwmHr = [Win32Capture]::DwmGetWindowAttribute($hWnd, 9, [ref]$dwm, $dwmSz)

    $cr    = New-Object Win32Capture+RECT
    [void][Win32Capture]::GetClientRect($hWnd, [ref]$cr)
    $pt    = New-Object Win32Capture+POINT   # (0,0) in client-space
    [void][Win32Capture]::ClientToScreen($hWnd, [ref]$pt)

    # ── debug: dump all coords, do NOT start ffmpeg ──
    if ($action -eq 'debug') {
        $lines = @(
            "Window              : $windowTitle",
            "GetWindowRect       : L=$($wr.Left) T=$($wr.Top) R=$($wr.Right) B=$($wr.Bottom)  ($($wr.Right-$wr.Left)x$($wr.Bottom-$wr.Top))",
            "DWM ExtFrameBounds  : L=$($dwm.Left) T=$($dwm.Top) R=$($dwm.Right) B=$($dwm.Bottom)  ($($dwm.Right-$dwm.Left)x$($dwm.Bottom-$dwm.Top))  hr=$dwmHr",
            "ClientRect+ToScreen : originX=$($pt.X) originY=$($pt.Y)  clientW=$($cr.Right)  clientH=$($cr.Bottom)"
        )
        $out = $lines -join "`n"
        return "CONSOLE::$out::END_CONSOLE::DEBUG: $out"
    }

    # GetClientRect gives content dimensions; ClientToScreen maps (0,0) to screen.
    # Together they give the capture region that starts after the title bar/borders
    # with no hardcoded pixel offsets.
    $bottomSkip = 40   # px to trim from the bottom (in-app toolbar); tune as needed

    $offsetX = [Math]::Max(0, $pt.X)
    $offsetY = [Math]::Max(0, $pt.Y)
    $width   = [Math]::Max(2, $cr.Right)
    $height  = [Math]::Max(2, $cr.Bottom - $bottomSkip)

    # libx264 requires even dimensions for yuv420p
    if ($width  % 2 -ne 0) { $width-- }
    if ($height % 2 -ne 0) { $height-- }

    # Presets control framerate only; capture region and encoding are identical.
    switch ($preset.ToLower()) {
        'high'  { $framerate = 30; $preset = 'High' }
        'low'   { $framerate = 15; $preset = 'Low'  }
        default { $framerate = 24; $preset = 'Medium' }
    }

    $ffmpegArgs = @(
        # Input: screen capture (low-latency probe so frames start immediately)
        "-probesize", "32",
        "-analyzeduration", "0",
        "-f", "gdigrab",
        "-framerate", "$framerate",
        "-offset_x", "$offsetX",
        "-offset_y", "$offsetY",
        "-video_size", "${width}x${height}",
        "-i", "desktop",
        # Input: silent stereo audio (keeps Twitch VODs happy; tiny bandwidth cost)
        "-f", "lavfi",
        "-i", "anullsrc=r=44100:cl=stereo",
        # Video: pad to 1920x1080 so Twitch never letterboxes, fix keyframe interval
        "-vf", "pad=1920:1080:0:0:black",
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-tune", "zerolatency",
        "-b:v", "1500k",
        "-maxrate", "1500k",
        "-bufsize", "3000k",
        "-g", "$($framerate * 2)",
        "-pix_fmt", "yuv420p",
        # Audio: encode silent track as AAC
        "-c:a", "aac",
        "-b:a", "96k",
        "-f", "flv",
        "$($RTMP_URL.TrimEnd('/'))/$streamKey"
    )

    try {
        $ffmpegProc = Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -PassThru -WindowStyle Hidden
        [System.IO.File]::WriteAllText($pidFile, $ffmpegProc.Id.ToString(), [System.Text.UTF8Encoding]::new($false))

        # ── ON AIR banner ──
        Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor White
        Write-Host "║  " -NoNewline -ForegroundColor White
        Write-Host "● REC        stream_twitch tool         LIVE ●" -NoNewline -ForegroundColor Red
        Write-Host "  ║" -ForegroundColor White
        Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor White
        Write-Host "║                                                  ║" -ForegroundColor White
        Write-Host "║  █     ████   █    █  ████                       ║" -ForegroundColor White
        Write-Host "║  █       █     █   █  █                          ║" -ForegroundColor White
        Write-Host "║  █       █      █ █   ████                       ║" -ForegroundColor White
        Write-Host "║  █       █      ██    █                          ║" -ForegroundColor White
        Write-Host "║  ████  ████     █     ████                       ║" -ForegroundColor White
        Write-Host "║                                                  ║" -ForegroundColor White
        Write-Host "║  github.com/SpdrByte/GemmaCLI                    ║" -ForegroundColor White
        Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor White

        $consoleMsg = "Twitch streaming started (window: '$windowTitle', ${width}x${height} @ ${framerate}fps) [$preset]"
        $resultMsg  = "OK: Twitch streaming window '$windowTitle' ${width}x${height} @ ${framerate}fps"
        return "CONSOLE::$consoleMsg::END_CONSOLE::$resultMsg"
    } catch {
        return "CONSOLE::ERROR: Failed to launch ffmpeg. $($_.Exception.Message)::END_CONSOLE::ERROR: Failed to launch ffmpeg. $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name             = "stream_twitch"
    Icon             = "🟣"
    RendersToConsole = $true
    Interactive      = $true
    RequiresKey      = $true
    KeyUrl           = "https://dashboard.twitch.tv/settings/stream"
    RequiresBilling  = $false
    Category         = @("Media", "Streaming")
    Keywords         = @("twitch", "stream", "live", "broadcast", "ffmpeg", "rtmp")
    Behavior         = "Use this tool to stream the Gemma CLI window via FFmpeg to Twitch. It captures the desktop region occupied by the CLI window using GetWindowRect coordinates. This tool runs on the main thread so it can reliably detect the CLI window at the moment of approval. Call with action='start' to begin and action='stop' to end. Requires a Twitch stream key stored securely via DPAPI. Supports quality presets Low, Medium, and High."
    Description      = "Starts or stops a live stream of the CLI window to Twitch via FFmpeg. Captures the desktop region at the detected window coordinates. Runs interactively on the main thread."
    Parameters       = @{
        action = "string - 'start' to begin streaming, 'stop' to end stream, or 'debug' to print capture coordinates without starting ffmpeg. (required)"
        preset = "string - framerate preset: Low (15fps), Medium (24fps), High (30fps). Encoding settings and capture region are identical across presets. (default: Medium, optional)"
    }
    Example          = '<tool_call>{ "name": "stream_twitch", "parameters": { "action": "start", "preset": "Medium" } }</tool_call>'
    FormatLabel      = { param($params) "$($params.action) [$($params.preset)]" }
    Tutorial         = "I can stream your CLI window live to Twitch. Try saying: 'start streaming my CLI to Twitch' or 'stop the Twitch stream'."
    Execute          = { param($params) Invoke-StreamTwitchTool @params }
    ToolUseGuidanceMajor = "        - When to use 'stream_twitch': Use to start or stop broadcasting the GemmaCLI window to Twitch.        - Parameters:            - `action` (required): 'start' or 'stop'.            - `preset` (optional): 'Low', 'Medium', or 'High'. Defaults to Medium.        - Setup: You must store a Twitch stream key via /settings before using this tool.        - Workflow: Call with action='start', then action='stop' when finished."
    ToolUseGuidanceMinor = "        - Purpose: Start/stop a live stream of the CLI window to Twitch.        - Basic use: action='start' to stream, action='stop' to end.        - Tip: Requires a stream key from your Twitch dashboard."
}