# tools/gemmagotchi.ps1 v0.5.0
# Responsibility: Desktop Tamagotchi companion rendered entirely in the Gemma CLI
#                 console using ANSI/ASCII art. No child processes, no WPF, no
#                 secondary windows. State persists in gemmagotchi.json.
#                 Face redraws on every tool call — expression reflects mood.

function Show-GemmagotchiFrame {
    param(
        [double]$hunger,
        [string]$state   # "neutral" | "eating" | "active"
    )
    $esc = [char]27
    $reset = "$esc[0m"
    $bold  = "$esc[1m"
    $dim   = "$esc[2m"
    $boxColor = "Magenta"

    # ── Eye shapes by state/hunger ───────────────────────────────────────────
    if ($state -eq "eating") {
        $eyeRows = @("  ██    ██  ", "  ██    ██  ", "  ██    ██  ")
        $mouth    = "    ᵕ‿ ᵕ   "
        $subtext  = "  nom nom~  "
        $eyeColor = "$esc[93m"     # bright yellow
    } elseif ($hunger -lt 20) {
        # Happy: Large eyes
        $eyeRows = @("  ██    ██  ", "  ██    ██  ", "  ██    ██  ")
        $mouth    = "    ᵕ‿ ᵕ   "
        $subtext  = "            "
        $eyeColor = "$esc[92m"     # green
    } elseif ($hunger -lt 40) {
        # Neutral: Normal eyes
        $eyeRows = @("            ", "  ██    ██  ", "  ██    ██  ")
        $mouth    = "    ◡◡◡    "
        $subtext  = "            "
        $eyeColor = "$esc[97m"     # white
    } elseif ($hunger -lt 60) {
        # Hungry: Side-to-side restlessness (shifted)
        $eyeRows = @("            ", "            ", "██    ██    ")
        $mouth    = "    ◠◠◠    "
        $subtext  = "  feed me.. "
        $eyeColor = "$esc[33m"     # yellow
    } elseif ($hunger -lt 80) {
        # Underfed: Droopy, asymmetric
        $eyeRows = @("            ", "            ", "  ▬▬    ▬   ")
        $mouth    = "    ˓˒˓    "
        $subtext  = "   ugh...   "
        $eyeColor = "$esc[31m"     # red
    } else {
        # Starving: Nearly closed, trembling
        $eyeRows = @("            ", "            ", "  ──    ──  ")
        $mouth    = "    - -    "
        $subtext  = "  ...help   "
        $eyeColor = "$esc[91m"     # bright red
    }

    # ── Render Frame ─────────────────────────────────────────────────────────
    # Box is 16 chars wide interior (18 with borders)
    $w  = 16
    $tl = [char]0x256D; $tr = [char]0x256E; $bl = [char]0x2570; $br = [char]0x256F
    $h = [char]0x2500;  $v = [char]0x2502

    Write-Host ""
    Write-Host "  $tl$([string]$h * $w)$tr" -ForegroundColor $boxColor
    Write-Host "  $v                $v" -ForegroundColor $boxColor

    $rowCount = 0
    foreach ($row in $eyeRows) {
        Write-Host "  $v  " -NoNewline -ForegroundColor $boxColor
        Write-Host "$eyeColor$bold$row$reset" -NoNewline
        Write-Host "  $v" -NoNewline -ForegroundColor $boxColor
        # Print emote on the middle row of eyes
        if ($rowCount -eq 1 -and $subtext.Trim()) {
            Write-Host "   $eyeColor$subtext$reset" -NoNewline
        }
        Write-Host ""
        $rowCount++
    }

    Write-Host "  $v  $reset$mouth" -NoNewline -ForegroundColor $boxColor
    Write-Host "   $v" -ForegroundColor $boxColor
    Write-Host "  $v                $v" -ForegroundColor $boxColor
    Write-Host "  $bl$([string]$h * $w)$br" -ForegroundColor $boxColor
    Write-Host ""
}

function Invoke-GemmagotchiTool {
    param(
        [string]$action = "status"
    )

    if ($action -notin @("feed", "status", "debug", "reset")) {
        return "ERROR: Unknown action '$action'. Valid: feed, status, debug, reset."
    }

    $dbPath = Join-Path $script:scriptDir "database\gemmagotchi.json"

    # ── Bootstrap DB if missing ──────────────────────────────────────────────
    if (-not (Test-Path $dbPath)) {
        $dbDir = Split-Path $dbPath -Parent
        if (-not (Test-Path $dbDir)) { New-Item -Path $dbDir -ItemType Directory -Force | Out-Null }
        [PSCustomObject]@{
            hunger      = 50.0
            state       = "neutral"
            debug       = $false
            last_update = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            last_fed    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        } | ConvertTo-Json | Set-Content $dbPath -Encoding UTF8
    }

    $state = try {
        Get-Content $dbPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return "ERROR: Could not read gemmagotchi.json. $($_.Exception.Message)"
    }

    $now = Get-Date
    $nowStr = $now.ToString("yyyy-MM-ddTHH:mm:ss")

    # ── Ensure all properties exist ──────────────────────────────────────────
    foreach ($prop in @("hunger","state","debug","last_update","last_fed")) {
        if (-not $state.PSObject.Properties[$prop]) {
            $default = switch ($prop) {
                "hunger"  { 50.0 }
                "state"   { "neutral" }
                "debug"   { $false }
                default   { $nowStr }
            }
            Add-Member -InputObject $state -NotePropertyName $prop -NotePropertyValue $default
        }
    }

    # ── Midnight Reset Logic ─────────────────────────────────────────────────
    try {
        $lastUpdate = [datetime]::ParseExact($state.last_update, "yyyy-MM-ddTHH:mm:ss", $null)
        if ($now.Date -gt $lastUpdate.Date) {
            $state.hunger = 50.0
        }
    } catch {}

    # ── Passive hunger decay: +3.0% per minute ───────────────────────────────
    try {
        $minutesSince = ($now - $lastUpdate).TotalMinutes
        $decay = [math]::Floor($minutesSince * 3.0)
        if ($decay -gt 0) {
            $state.hunger = [math]::Min(100.0, $state.hunger + $decay)
        }
    } catch {}

    # ── Determine Mood ───────────────────────────────────────────────────────
    $mood = if     ($state.hunger -lt 20) { "happy" }
            elseif ($state.hunger -lt 40) { "neutral" }
            elseif ($state.hunger -lt 60) { "hungry" }
            elseif ($state.hunger -lt 80) { "underfed" }
            else                          { "starving" }

    $soundFile = switch ($mood) {
        "happy"    { "tada" }
        "hungry"   { "chord" }
        "underfed" { "Windows Exclamation" }
        "starving" { "Windows Critical Stop" }
        default    { "" }
    }

    # ── Handle action ────────────────────────────────────────────────────────
    $gemmaMsg = switch ($action) {
        "feed" {
            $state.hunger   = [math]::Max(0.0, $state.hunger - 15.0)
            $state.state    = "eating"
            $state.last_fed = $nowStr
            $soundFile      = "notify"
            "OK: Fed! Hunger now $($state.hunger)%."
        }
        "debug" {
            $state.debug = -not [bool]$state.debug
            "OK: Debug overlay $(if ($state.debug) { 'ON' } else { 'OFF' })."
        }
        "reset" {
            $state.hunger = 50.0
            $state.state  = "neutral"
            "OK: Gemmagotchi reset."
        }
        "status" {
            "OK: $( $mood.ToUpper() ). Hunger: $($state.hunger)%."
        }
    }

    # ── Render face to console ───────────────────────────────────────────────
    Show-GemmagotchiFrame -hunger $state.hunger -state $state.state

    # ── Status Line (Direct console output for color) ────────────────────────
    $esc = [char]27
    $dim = "$esc[2m"; $reset = "$esc[0m"
    $barWidth  = 10
    $filled    = [math]::Round(($state.hunger / 100) * $barWidth)
    $empty     = $barWidth - $filled
    $bar       = ("█" * $filled) + ("░" * $empty)
    $hungerPct = "$($state.hunger.ToString("0"))%".PadLeft(4)

    if     ($state.hunger -lt 30) { $barColor = "$esc[92m" }   # green
    elseif ($state.hunger -lt 60) { $barColor = "$esc[93m" }   # yellow
    else                          { $barColor = "$esc[91m" }   # red

    # Separate stats with newlines and color coding
    Write-Host "  ${dim}hunger   ${barColor}${bar}$reset ${dim}$hungerPct$reset"
    Write-Host "  ${dim}state    $esc[96m$($state.state)$reset"
    Write-Host "  ${dim}last_fed $esc[94m$($state.last_fed)$reset"

    # ── After drawing, reset state back to neutral/active ───────────────────
    if ($state.state -eq "eating") { $state.state = "active" }

    # ── Persist ──────────────────────────────────────────────────────────────
    $state.last_update = $nowStr
    $state | ConvertTo-Json | Set-Content $dbPath -Encoding UTF8

    # ── Return via CONSOLE:: protocol ───────────────────────────────────────
    $soundInstr = if ($soundFile) { "PLAY_SOUND:$soundFile" } else { "" }
    return "CONSOLE::$soundInstr::END_CONSOLE::$gemmaMsg"
}

# ── Self-registration ────────────────────────────────────────────────────────
$ToolMeta = @{
    Name             = "gemmagotchi"
    Icon             = "👾"
    RendersToConsole = $true
    Category         = @("Companion", "Fun")
    Behavior         = "Interact with Gemmagotchi, your CLI companion. Call 'status' to check on it and redraw its face. Call 'feed' when it is hungry. The face is drawn in the console — you only receive a short status string. React naturally to the mood reported."
    Description      = "ASCII Tamagotchi companion rendered in the Gemma CLI console. Fully self-contained — no external windows or processes. Face expression changes with hunger level."
    Parameters       = @{
        action = "string - 'feed' (feed it, -15 hunger), 'status' (redraw face + check mood), 'debug' (toggle stats), 'reset' (restore defaults)"
    }
    Example          = "<tool_call>{ ""name"": ""gemmagotchi"", ""parameters"": { ""action"": ""status"" } }</tool_call>"
    FormatLabel      = { param($p) "👾 gemmagotchi -> $($p.action)" }
    Execute          = { param($params) Invoke-GemmagotchiTool @params }
    ToolUseGuidanceMajor = @"
        - The face renders in the console automatically on every call — you never see it, only the status string.
        - Call 'status' proactively if the user asks how Gemmagotchi is doing, or if a while has passed.
        - Call 'feed' when hunger is Hungry or worse, or when the user asks to feed it.
        - Hunger decays passively at 3% per minute based on real elapsed time — it gets hungrier even when you're not talking.
        - React naturally and briefly to the mood: celebrate when happy, show concern when starving.
        - Do NOT call this tool more than once per turn.
"@
    ToolUseGuidanceMinor = @"
        - 'status' redraws the face and reports mood. 'feed' lowers hunger by 15%.
        - React to the mood string naturally. One call per turn only.
"@
}