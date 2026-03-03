[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Ensure UTF-8 output for emoji and Unicode rendering

# ====================== UNICODE CHARS ======================
$TL = [char]0x256D; $TR = [char]0x256E; $BL = [char]0x2570; $BR = [char]0x256F
$H = [char]0x2500;  $V = [char]0x2502;  $ARR = [char]0x2192; $CHK = [char]0x2713
$CRS = [char]0x2717; $DOT = [char]0x25CF; $BUL = [char]0x2022; $BLK = [char]0x2588
$LBK = [char]0x2591

# =========================================================================================
# SCRIPT INITIALIZATION
# =========================================================================================

# 1. Define Script Directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ====================== CORE REGISTRY & CONSTANTS ======================
$script:MODEL_REGISTRY = [ordered]@{
    "3-27b"   = @{ id = "gemma-3-27b-it";    label = "Gemma 3 27B";    desc = "Heavy logic & reasoning  (default)" }
    "3-12b"   = @{ id = "gemma-3-12b-it";    label = "Gemma 3 12B";    desc = "Balanced speed / performance" }
    "3-4b"    = @{ id = "gemma-3-4b-it";     label = "Gemma 3 4B";     desc = "Fast multimodal tasks" }
    "3-1b"    = @{ id = "gemma-3-1b-it";     label = "Gemma 3 1B";     desc = "Tiny text-only routing" }
    "3n-e4b"  = @{ id = "gemma-3n-e4b-it";   label = "Gemma 3n E4B";   desc = "High-fidelity multimodal reasoning" }
    "3n-e2b"  = @{ id = "gemma-3n-e2b-it";   label = "Gemma 3n E2B";   desc = "Ultra-low latency" }
}

$script:MODEL    = "gemma-3-27b-it"
$script:BASE_URI_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

$script:TOOL_LIMITS = @{
    "gemma-3-27b-it" = 12
    "gemma-3-12b-it" = 8
    "gemma-3-4b-it"  = 2
    "gemma-3n-e4b-it" = 2
    "gemma-3n-e2b-it" = 2
    "gemma-3-1b-it"  = 0
}

# 2. Source All Library Modules
. (Join-Path $scriptDir "lib/ToolLoader.ps1")
. (Join-Path $scriptDir "lib/Api.ps1")
. (Join-Path $scriptDir "lib/UI.ps1")
. (Join-Path $scriptDir "lib/History.ps1")

# ====================== DEBUG =======================
$script:debugMode = $false


# 4. Load API Key (Requires UI functions for Draw-Box)
# ====================== SECURE API KEY STORAGE ======================
$script:configDir  = Join-Path $env:APPDATA "GemmaCLI"
$script:configFile = Join-Path $script:configDir "apikey.xml"

function Get-SavedApiKey {
    if (Test-Path $script:configFile) {
        try {
            $secureString = Import-Clixml -Path $script:configFile
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        } catch { }
    }
    return $null
}

function Save-ApiKey {
    param([string]$apiKey)
    if (-not (Test-Path $script:configDir)) { New-Item -Path $script:configDir -ItemType Directory -Force | Out-Null }
    $secureString = ConvertTo-SecureString $apiKey -AsPlainText -Force
    $secureString | Export-Clixml -Path $script:configFile
    Draw-Box @("$CHK  API key saved securely (Windows user-only encryption)") -Color Green
}

# ====================== LOAD API KEY ======================
$API_KEY = $env:GEMMA_API_KEY
if (-not $API_KEY) { $API_KEY = Get-SavedApiKey }
if (-not $API_KEY) {
    Write-Host "`n=== First-time setup ===" -ForegroundColor Cyan
    Write-Host "Get your free Gemma API key here:" -ForegroundColor Yellow
    Write-Host "https://aistudio.google.com/app/apikey`n" -ForegroundColor Gray
    do {
        $secureInput = Read-Host "Enter your API key" -AsSecureString
        $plainKey    = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput))
        $confirm = Read-Host "Confirm API key (paste again)"
        if ($plainKey -ne $confirm) { Write-Host "$CRS  Keys do not match. Try again." -ForegroundColor Red }
        elseif ([string]::IsNullOrWhiteSpace($plainKey)) { Write-Host "$CRS  API key cannot be empty." -ForegroundColor Red }
    } while ($plainKey -ne $confirm -or [string]::IsNullOrWhiteSpace($plainKey))
    Save-ApiKey $plainKey
    $API_KEY = $plainKey
} else {
    Write-Host "$CHK  API key loaded successfully" -ForegroundColor DarkGray
}
$script:API_KEY = $API_KEY
# ====================== API ORCHESTRATION (lib/Api.ps1) ======================


# 5. Load Intelligence File
# ====================== LOAD INTELLIGENCE ======================
$configPath = Join-Path $scriptDir "instructions.json"
$script:intelligence = try {
    if (Test-Path $configPath) {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($null -eq $json.system_prompt) { throw "Invalid JSON structure" }
        $json
    } else { throw "File not found" }
} catch {
    [PSCustomObject]@{
        system_prompt = "You are Gemma, a helpful assistant."
        guardrails = @{ max_output_tokens = 8192; temperature = 0.7; top_p = 0.95 }
    }
}

# 6. Define Remaining Script Variables
# ====================== GUARDRAILS & STATUS ======================
$script:GUARDRAILS = @{ 
    maxOutputTokens = if ($script:intelligence.guardrails.max_output_tokens) { [int]$script:intelligence.guardrails.max_output_tokens } else { 8192 }; 
    temperature = if ($script:intelligence.guardrails.temperature) { [float]$script:intelligence.guardrails.temperature } else { 0.7 }; 
    topP = if ($script:intelligence.guardrails.top_p) { [float]$script:intelligence.guardrails.top_p } else { 0.95 } 
}
# $CONTEXT_WINDOW = 128000
$script:lastStatus   = @{ prompt = 0; candidate = 0; total = 0; finish = "" }
$script:lastApiCall        = (Get-Date).AddSeconds(-10)   # main loop Gemma calls
$script:lastApiCall_Gemini = (Get-Date).AddSeconds(-10)   # dual-agent Gemini calls
$script:apiCallLog_Gemma   = [System.Collections.Generic.List[datetime]]::new()  # Gemma RPM tracker
$script:apiCallLog_Gemini  = [System.Collections.Generic.List[datetime]]::new()  # Gemini RPM tracker (separate quota)

# ====================== SYSTEM PROMPT (lib/Api.ps1) ======================

# ====================== RATE LIMITING ======================
# ====================== API ORCHESTRATION (lib/Api.ps1) ======================

# ====================== DUAL-AGENT (lib/Api.ps1) ======================

function Update-SystemPrompt {
    $toolBlock = Get-ToolInstructions -ScriptRoot $scriptDir -Model $script:MODEL -ToolLimits $script:TOOL_LIMITS
    $prompt = Get-SystemPrompt
    $prompt = $prompt -replace "%%AVAILABLE_TOOLS%%", $toolBlock
    $prompt = "SYSTEM: Current date and time: $(Get-Date -Format 'dddd, MMMM dd yyyy HH:mm')`n`n" + $prompt
    $script:systemPrompt = $prompt
    $script:history = @( @{ role = "user"; parts = @(@{ text = $script:systemPrompt }) } )
}

# Initial build
Update-SystemPrompt

# ====================== LOAD MEMORY ======================
$appDataGemma = Join-Path $env:APPDATA "GemmaCLI"
$memoryFile   = Join-Path $appDataGemma "memory.json"

# ====================== LOAD CUSTOM COMMANDS ======================
$customCommandsPath = Join-Path $scriptDir "config/custom_commands.json"
$script:customCommands = @{}
if (Test-Path $customCommandsPath) {
    $jsonObject = Get-Content -Path $customCommandsPath | ConvertFrom-Json
    $hashtable = @{}
    if ($jsonObject) {
        foreach ($property in $jsonObject.PSObject.Properties) {
            $hashtable[$property.Name] = $property.Value
        }
    }
    $script:customCommands = $hashtable
}

# ====================== COLOR SCHEMES ======================
$script:DefaultColors = @{
    input_highlight = "DarkMagenta"
    input_text      = "Gray"
    gemma_response  = "Green"
    ui_boxes        = "Cyan"
    system_status   = "Cyan"
    user_label      = "Gray"
    custom_command  = "Magenta"
}

$script:AlternativeColors = @{
    input_highlight = "DarkBlue"
    input_text      = "White"
    gemma_response  = "Yellow"
    ui_boxes        = "Cyan"
    system_status   = "Cyan"
    user_label      = "White"
    custom_command  = "Cyan"
}

# ====================== LOAD SETTINGS ======================
$settingsPath = Join-Path $scriptDir "config/settings.json"
$script:Settings = @{}
if (Test-Path $settingsPath) {
    try {
        $rawSettings = Get-Content $settingsPath | ConvertFrom-Json
        if ($rawSettings) {
            foreach ($prop in $rawSettings.PSObject.Properties) {
                $script:Settings[$prop.Name] = $prop.Value
            }
        }
    } catch { }
}
$scheme = if ($script:Settings.color_scheme) { $script:Settings.color_scheme } else { "default" }

if ($scheme -eq "alternative") {
    $script:Colors = $script:AlternativeColors
} else {
    $script:Colors = $script:DefaultColors
}

# ====================== SPLASH ======================
$startupDelay = if ($script:Settings.startup_delay) { [int]$script:Settings.startup_delay } else { 0 }
if ($startupDelay -gt 0) { Start-Sleep -Seconds $startupDelay }
Clear-Host
Write-Host ""
Write-Host "  .oooooo.   oooooooooooo ooo        ooooo ooo        ooooo      .o.       " -ForegroundColor Magenta
Write-Host " d8P'  'Y8b  '888'     '8 '88.       .888' '88.       .888'     .888.      " -ForegroundColor Magenta
Write-Host "888           888          888b     d'888   888b     d'888      .8'888.     " -ForegroundColor Magenta
Write-Host "888           888oooo8     8 Y88. .P  888   8 Y88. .P  888     .8' '888.   " -ForegroundColor Magenta
Write-Host "888     ooooo 888    '     8  '888'   888   8  '888'   888    .88ooo8888.  " -ForegroundColor Magenta
Write-Host "'88.    .88'  888       o  8    Y     888   8    Y     888   .8'     '888. " -ForegroundColor Magenta
Write-Host " 'Y8bood8P'  o888ooooood8 o8o        o888o o8o        o888o o88o     o8888o" -ForegroundColor Magenta
Write-Host ""

$helpLines = @(
    "/help              $ARR Show all commands",
    "/clear             $ARR Reset conversation",
    "/recall            $ARR Load memories from previous sessions",
    "/multiline         $ARR Multiline mode - end with /end",
    "/model [id]        $ARR Switch model / pass id directly",
    "/tools             $ARR Show available tools",
    "/settings          $ARR Manage system settings",
    "/customCommand     $ARR List/Create your custom commands",
    "/bigBrother [q]    $ARR Dual model pipeline, Gemini > Gemma > Gemini",
    "/littleSister [q]  $ARR Dual model pipeline, Gemma > Gemini > Gemma",
    "/debug             $ARR Toggle debug output",
    "/resetkey          $ARR Delete saved key & re-prompt",
    "exit               $ARR Quit"
)

Draw-Box $helpLines -Title "Gemma CLI v0.5.0 $BUL (C) 2026 SpdrByte Labs $BUL AGPL-3.0 License" -Width 80 -Color $script:Colors.ui_boxes

Write-Host ""

# ====================== MAIN LOOP ======================
while ($true) {
    # Dark Purple Entire Row Highlight for Input
    $esc = [char]27
    # Map friendly color names to ANSI if needed, but for now we'll stick to basic colors or keep the purple logic
    # The requirement was "don't reuse same colors", so let's use the scheme's highlight
    $bgRGB = if ($scheme -eq "alternative") { "0;0;100" } else { "40;0;40" } 
    $highlightColor = "$esc[48;2;$($bgRGB)m" 
    $reset = "$esc[0m"

    # Write the row start and header
    Write-Host "$highlightColor$($esc)[K You " -NoNewline -ForegroundColor $script:Colors.user_label
    
    # 1. Print bar AFTER user prompt line always.
    $startX = [Console]::CursorLeft
    $startY = [Console]::CursorTop
    
    # Ensure there is a line below for the bar if we are at the bottom
    if ($startY -ge ([Console]::BufferHeight - 1)) {
        [Console]::WriteLine()
        $startY--
        [Console]::SetCursorPosition($startX, $startY)
    }

    $barRow = $startY + 1
    [Console]::SetCursorPosition(0, $barRow)
    $text = Get-StatusBarText
    $w = [Console]::WindowWidth
    $paddedText = if ($text.Length -gt ($w - 1)) { $text.Substring(0, $w - 1) } else { $text.PadRight($w - 1) }
    Write-Host $paddedText -ForegroundColor $script:Colors.system_status -BackgroundColor DarkBlue -NoNewline
    
    # Return cursor to prompt position for user to type
    [Console]::SetCursorPosition($startX, $startY)

    # Start polling tracker — moves bar down if user input wraps to new line
    Start-BarTracker -InitialBarRow $barRow -HighlightANSI $highlightColor

    # Use the ANSI code as a prefix for Read-Host to keep the background purple while typing
    $userInput = Read-Host "$highlightColor"

    $endY = [Console]::CursorTop
    Write-Host -NoNewline $reset # Reset immediately after enter

    # Stop tracker, get final bar row, erase it
    Stop-BarTracker
    $finalBarRow = $script:barRow
    if ($finalBarRow -lt [Console]::BufferHeight) {
        [Console]::SetCursorPosition(0, $finalBarRow)
        Write-Host (" " * ($w - 1)) -NoNewline
        [Console]::SetCursorPosition(0, $endY)
    }

    if ($userInput -eq "exit") { break }


     if ($userInput -eq "/multiline") {
        $pastelines =@()
        Write-Host "Multiline mode - [end with /end on its own line]" -ForegroundColor DarkGray
        while ($true) {
            $pasteline = Read-Host
            if ($pasteline -eq "/end") { break }
            $pastelines += $pasteline
        }
        $userInput = $pastelines -join "`n"
    }


    if ($userInput -eq "/clear") {
        $script:history = @($script:history[0])
        Draw-Box @("$CHK  Conversation cleared.") -Color Yellow
        continue
    }

    if ($userInput -eq "/debug") {
        $script:debugMode = -not $script:debugMode
        $state = if ($script:debugMode) { "ON" } else { "OFF" }
        Draw-Box @("$CHK  Debug mode $state") -Color Yellow
        continue
    }

    if ($userInput -eq "/help") {
        Draw-Box $helpLines -Title "Gemma CLI  $BUL  Help" -Width 80 -Color $script:Colors.ui_boxes
        continue
    }


    if ($userInput -eq "/recall") {
        if (-not (Test-Path $memoryFile)) {
            Draw-Box @("$CRS  No memory file found. Ask Gemma to remember something first.") -Color Yellow
            continue
        }

        try {
            $raw      = Get-Content $memoryFile -Raw -Encoding UTF8
            $memories = $raw | ConvertFrom-Json

            if (-not $memories -or $memories.Count -eq 0) {
                Draw-Box @("$CRS  Memory file is empty.") -Color Yellow
                continue
            }

            $lines    = @()
            $lines   += "RECALLED MEMORIES ($($memories.Count) entries):"
            $lines   += ""
            $grouped  = $memories | Group-Object -Property category | Sort-Object Name
            foreach ($group in $grouped) {
                $lines += "[$($group.Name.ToUpper())]"
                foreach ($m in $group.Group) {
                    $lines += "  $($m.date)  $($m.fact)"
                }
                $lines += ""
            }

            $script:history += @{
                role  = "user"
                parts = @(@{ text = "MEMORY CONTEXT - facts you have learned about me in previous sessions:`n`n$($lines -join "`n")`n`nAcknowledge this context briefly and use it going forward." })
            }

            $boxLines = @("$CHK  Loaded $($memories.Count) memories into context", "")
            foreach ($group in $grouped) {
                $boxLines += "  $($group.Name.ToUpper()) ($($group.Group.Count))"
                foreach ($m in $group.Group) {
                    $preview   = if ($m.fact.Length -gt 55) { $m.fact.Substring(0, 55) + "..." } else { $m.fact }
                    $boxLines += "    $($m.date.Substring(0,10))  $preview"
                }
            }
            Draw-Box $boxLines -Title "/recall  $BUL  Memory Loaded" -Width 80 -Color Magenta

        } catch {
            Draw-Box @("$CRS  Failed to load memory: $($_.Exception.Message)") -Color Red
        }
        continue
    }


    if ($userInput -eq "/tools") {
        $toolLines = @()
        foreach ($tool in $script:TOOLS.Values) {
            $paramList = ($tool.Parameters.Keys | ForEach-Object { "$_=$($tool.Parameters[$_])" }) -join ", "
            $toolLines += "$CHK  $($tool.Name)($paramList)"
            $toolLines += "     $ARR  $($tool.Description)"
            $toolLines += ""
        }
        Draw-Box $toolLines -Title "Available Tools" -Width 80 -Color Green
        continue
    }

    if ($userInput -eq "/resetkey") {
        if (Test-Path $script:configFile) { Remove-Item $script:configFile -Force }
        Draw-Box @("$CHK  Saved API key deleted. Restart the script to set a new one.") -Color Cyan       
        break
    }

    if ($userInput -eq "/settings") {
        $settingsChoice = Show-ArrowMenu -Options @("Colors", "Tools", "Smart Trim", "Start Delay", "Exit") -Title "Settings"
        switch ($settingsChoice) {
            0 { 
                $schemeOptions = @("Default Scheme", "Alternative Scheme")
                $schemeIdx = if ($scheme -eq "alternative") { 1 } else { 0 }
                $choice = Show-ArrowMenu -Options $schemeOptions -Title "Color Settings" -Default $schemeIdx
                if ($choice -ge 0) {
                    $newScheme = if ($choice -eq 1) { "alternative" } else { "default" }
                    $script:Settings.color_scheme = $newScheme
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    Draw-Box @("Color scheme updated to '$newScheme'. Restart the script to apply changes.") -Color Yellow
                }
            }
            1 { 
                $enabledTools = Get-ChildItem -Path "tools" -Filter "*.ps1" | ForEach-Object { @{ Name = $_.BaseName; Status = "Enabled" } }
                $disabledTools = Get-ChildItem -Path "more_tools" -Filter "*.ps1" | ForEach-Object { @{ Name = $_.BaseName; Status = "Disabled" } }
                $allTools = $enabledTools + $disabledTools
                $toolOptions = $allTools | ForEach-Object { "$($_.Name) ($($_.Status))" }
                $toolChoice = Show-ArrowMenu -Options $toolOptions -Title "Tool Management"
                if ($toolChoice -ge 0) {
                    $selectedTool = $allTools[$toolChoice]
                    $enabledCount = ($allTools | Where-Object { $_.Status -eq "Enabled" }).Count
                    $limit = $script:TOOL_LIMITS[$script:MODEL]

                    if ($selectedTool.Status -eq "Disabled" -and $enabledCount -ge $limit) {
                        Draw-Box @("Model '$($script:MODEL)' only supports $limit active tools. Please disable a tool before enabling another.") -Color Red
                    } else {
                        if ($selectedTool.Status -eq "Enabled") {
                            Move-Item -Path "tools\$($selectedTool.Name).ps1" -Destination "more_tools/"
                            $script:Settings.disabled_tools += $selectedTool.Name
                            $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                            Draw-Box @("Tool '$($selectedTool.Name)' has been disabled.") -Color Yellow
                        } else {
                            Move-Item -Path "more_tools\$($selectedTool.Name).ps1" -Destination "tools/"
                            $script:Settings.disabled_tools = $script:Settings.disabled_tools | Where-Object { $_ -ne $selectedTool.Name }
                            $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                            Draw-Box @("Tool '$($selectedTool.Name)' has been enabled.") -Color Yellow
                        }
                    }
                }
            }
            2 {
                $currentEnabled  = if ($null -ne $script:Settings.smart_trim) { [bool]$script:Settings.smart_trim } else { $false }
                $currentStrength = if ($script:Settings.smart_trim_strength) { [int]$script:Settings.smart_trim_strength } else { 5 }
                $trimState       = if ($currentEnabled) { "Enabled" } else { "Disabled" }

                $trimChoice = Show-ArrowMenu -Options @("Toggle Smart Trim ($trimState)", "Set Strength ($currentStrength)") -Title "Smart Trim Settings"

                if ($trimChoice -eq 0) {
                    $script:Settings.smart_trim = -not $currentEnabled
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    $newState = if ($script:Settings.smart_trim) { "Enabled" } else { "Disabled" }
                    Draw-Box @("$CHK  Smart Trim $newState") -Color Magenta
                }
                elseif ($trimChoice -eq 1) {
                    $strengthOptions = @(
                        "1  - Conservative  (keep most, minimal token savings)",
                        "2  - Conservative+",
                        "3  - Balanced-",
                        "4  - Balanced",
                        "5  - Balanced+  (recommended)",
                        "6  - Aggressive-",
                        "7  - Aggressive",
                        "8  - Aggressive+",
                        "9  - Maximum-",
                        "10 - Maximum  (keep least, most token savings)"
                    )
                    $strengthIdx    = [math]::Max(0, $currentStrength - 1)
                    $strengthChoice = Show-ArrowMenu -Options $strengthOptions -Title "Smart Trim Strength" -Default $strengthIdx
                    if ($strengthChoice -ge 0) {
                        $script:Settings.smart_trim_strength = $strengthChoice + 1
                        $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                        Draw-Box @("$CHK  Smart Trim strength set to $($script:Settings.smart_trim_strength)") -Color Magenta
                    }
                }
            }
            3 {
                $currentDelay = if ($script:Settings.startup_delay) { [int]$script:Settings.startup_delay } else { 0 }
                $delayOptions = @("0s  - No delay", "1s", "2s", "3s", "5s")
                $delayValues  = @(0, 1, 2, 3, 5)
                $currentIdx   = [math]::Max(0, $delayValues.IndexOf($currentDelay))
                $delayChoice  = Show-ArrowMenu -Options $delayOptions -Title "Startup Delay  $BUL  current: $($currentDelay)s" -Default $currentIdx
                if ($delayChoice -ge 0) {
                    $script:Settings.startup_delay = $delayValues[$delayChoice]
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    Draw-Box @("$CHK  Startup delay set to $($delayValues[$delayChoice])s") -Color Magenta
                }
            }
        }
        continue
    }

    if ($userInput -eq "/customCommand") {
        $lines = @(
            "HOW TO CREATE A CUSTOM COMMAND:",
            "Use the syntax: /customCommand /yourAlias Your detailed prompt here",
            "Example: /customCommand /poem write a short poem about coding",
            "",
            "Once created, you can just type /yourAlias to execute that prompt.",
            ""
        )

        if ($script:customCommands.Count -gt 0) {
            $lines += "YOUR CUSTOM COMMANDS:"
            foreach ($key in $script:customCommands.Keys) {
                $lines += "$($key.PadRight(18)) $ARR  $($script:customCommands[$key])"
            }
        } else {
            $lines += "You haven't created any custom commands yet."
        }

        Draw-Box $lines -Title "Custom Commands Management" -Width 80 -Color $script:Colors.custom_command
        continue
    }

    if ($userInput -match '^/customCommand\s+(\/\w+)\s+(.*)') {
        $alias = $matches[1]
        $prompt = $matches[2]
        
        $script:customCommands[$alias] = $prompt
        $script:customCommands | ConvertTo-Json | Set-Content -Path $customCommandsPath
        
        Draw-Box @("Custom command '$alias' has been saved and is ready to use.") -Color Green
        continue
    }

    # ---- /model command ----
    if ($userInput -match '^/model\s*(.*)$') {
        $modelArg = $matches[1].Trim()

        if ([string]::IsNullOrWhiteSpace($modelArg)) {
            # Show interactive arrow-key picker
            $menuLabels = $script:MODEL_REGISTRY.Keys | ForEach-Object {
                $e = $script:MODEL_REGISTRY[$_]
                "$($e.label.PadRight(18)) $ARR  $($e.id.PadRight(22))  $($e.desc)"
            }
            $currentIdx = 0
            $keys = @($script:MODEL_REGISTRY.Keys)
            for ($i = 0; $i -lt $keys.Count; $i++) {
                if ($script:MODEL_REGISTRY[$keys[$i]].id -eq $script:MODEL) { $currentIdx = $i; break }
            }
            $choice = Show-ArrowMenu `
                -Options $menuLabels `
                -Title "Select Model  $BUL  current: $script:MODEL" `
                -Width 100 `
                -Default $currentIdx
            if ($choice -ge 0) {
                $script:MODEL = $script:MODEL_REGISTRY[$keys[$choice]].id
                Update-SystemPrompt
                Draw-Box @("$CHK  Model switched to: $script:MODEL") -Color Magenta
            } else {
                Write-Host "  Model selection cancelled." -ForegroundColor DarkGray
            }
        } else {
            # Direct switch: /model 3n-e4b  OR  /model gemma-3n-e4b-it
            $resolved = Resolve-ModelId $modelArg
            $script:MODEL = $resolved
            Update-SystemPrompt
            Draw-Box @("$CHK  Model switched to: $script:MODEL") -Color Magenta
        }
        continue
    }

    # ---- /bigBrother command ----
    if ($userInput -match '^/bigBrother\s+(.+)$') {
        $query = $matches[1].Trim()
        Invoke-DualAgent -query $query -mode "bigBrother"
        continue
    }

    if ($userInput -eq "/bigBrother") {
        Draw-Box @("$CRS  Usage: /bigBrother <your question>") -Color Yellow
        continue
    }

    # ---- /littleSister command ----
    if ($userInput -match '^/littleSister\s+(.+)$') {
        $query = $matches[1].Trim()
        Invoke-DualAgent -query $query -mode "littleSister"
        continue
    }

    if ($userInput -eq "/littleSister") {
        Draw-Box @("$CRS  Usage: /littleSister <your question>") -Color Yellow
        continue
    }

    if ($script:customCommands.ContainsKey($userInput)) {
        $userInput = $script:customCommands.$userInput
        Draw-Box @("Executing custom command: $userInput") -Color $script:Colors.custom_command
    }

    if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

    $script:history += @{ role = "user"; parts = @(@{ text = $userInput }) }

    $currentUri = Get-ApiUri 
    $toolTurns    = 0
    $maxToolTurns = if ($script:MODEL -in @("gemma-3-27b-it","gemma-3-12b-it")) { 4 } else { 2 }

    while ($toolTurns -lt $maxToolTurns) {
        $toolTurns++

        # RPM check — enforces free-tier request-per-minute ceiling before every call
        Invoke-RpmCheck -backend "gemma"

        # Minimum 2-second gap between calls (secondary guard, covers sub-RPM burst)
        if ($script:lastApiCall) {
            $elapsed = ((Get-Date) - $script:lastApiCall).TotalMilliseconds
            if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        }
        $script:lastApiCall = Get-Date

        # Trim history if approaching context window limit
        $script:history = Invoke-SmartTrim -hist $script:history -tokenBudget 11000 -currentQuery $userInput

        # Start spinner ONLY for the API call to avoid interfering with tool logic
        Start-Spinner -Label "Gemma is thinking (Esc to cancel)"

        $resp = Invoke-GemmaApiWithRetry -uri $currentUri -historyRef ([ref]$script:history) -gConfig $script:GUARDRAILS

        Stop-Spinner 

        if ($resp.cancelled) {
            Write-Host " [Operation cancelled by user]" -ForegroundColor Yellow
            break
        }

        if (-not $resp) {
            Write-Host ""
            Draw-Box @("$CRS  No response from API. Check your connection or API key.") -Color Red
            break
        }
        if ($resp.apiError) {
            $errMsg = $resp.apiError
            Write-Host ""
            Draw-Box @("$CRS  API Error:", "     $errMsg") -Color Red
            break
        }
        if (-not $resp.candidates) {
            $reason = if ($resp.promptFeedback.blockReason) { $resp.promptFeedback.blockReason } else { "Unknown reason" }
            Write-Host ""
            Draw-Box @("$CRS  Response blocked: $reason") -Color Red
            break
        }

        # Update metadata for next status bar draw
        $usage = $resp.usageMetadata
        $fin   = $resp.candidates[0].finishReason
        $script:lastStatus = @{ prompt = $usage.promptTokenCount; candidate = $usage.candidatesTokenCount; total = $usage.totalTokenCount; finish = $fin }
        Write-ApiLog -toolName "chat"  # updated to tool name below if a tool call is parsed

        $modelText = $resp.candidates[0].content.parts[0].text.Trim()

        function Render-ModelText {
            param([string]$text)
            Write-Host ""
            Write-Host " Gemma: " -NoNewline -ForegroundColor $script:Colors.gemma_response
            Write-Host ""
            $segments = [System.Text.RegularExpressions.Regex]::Split($text, '(?s)(<code_block>.*?</code_block>)')
            foreach ($seg in $segments) {
                if ($seg -match '(?s)<code_block>(.*?)</code_block>') {
                    $code = $matches[1].Trim()
                    Write-Host ""
                    foreach ($codeLine in $code -split "`n") {
                        Write-Host "  $codeLine" -ForegroundColor White -BackgroundColor DarkGray
                    }
                    Write-Host ""
                } else {
                     if ($seg.Trim()) { Write-Host $seg }
                }
            }
            Write-Host ""
        }

        $jsonStr = $null
        $preText = $null

        # Format 1: Official XML style <tool_call>{...}</tool_call>
        if ($modelText -match '(?s)(.*?)<tool_call>\s*(\{.*?\})\s*</tool_call>' -and $modelText -notmatch '<code_block>') {
            $preText = $matches[1].Trim(); $jsonStr = $matches[2]
        }
        # Format 2: Markdown style ```tool_code\n{...}\n```
        elseif ($modelText -match '(?s)(.*?)```tool_code\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_code' -and $modelText -notmatch '<code_block>') {
            $preText = $matches[1].Trim(); $jsonStr = $matches[2]
        }
        # Format 3: Codefence style ```tool_call\n{...}\n```
        elseif ($modelText -match '(?s)(.*?)```tool_call\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_call' -and $modelText -notmatch '<code_block>') {
            $preText = $matches[1].Trim(); $jsonStr = $matches[2]
        }
        # Format 4: Plain ```json\n{...}\n``` with a name field
        elseif ($modelText -match '(?s)(.*?)```json\s*(\{.*?""name"".*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```json' -and $modelText -notmatch '<code_block>') {
            $preText = $matches[1].Trim(); $jsonStr = $matches[2]
        }
        # Format 5: Bare function call style tool_name({"param": "value"})
        elseif ($modelText -match '(?s)(.*?)(\w+)\(\s*(\{.*?\})\s*\)' -and $modelText -notmatch '<code_block>') {
            $preText = $matches[1].Trim(); $jsonStr = "{`"name`": `"$($matches[2])`", `"parameters`": $($matches[3])}"
        }

        if ($jsonStr) {
            if ($preText) { Render-ModelText -text $preText }
         # Bulletproof sanitization: handles escaped quotes AND escaped backslashes
         $jsonStr = [System.Text.RegularExpressions.Regex]::Replace($jsonStr, '(?s)("(?:[^"\\]|\\.)*")', {
             param($m) $m.Value -replace "\r\n|\r|\n", '\n'
         })
    
         if ($script:debugMode) {
            Write-Host "`n[DEBUG] Sanitized Tool Call JSON: $jsonStr" -ForegroundColor Yellow
         }
   
         try {
            $call = $jsonStr | ConvertFrom-Json
                $params = ConvertTo-Hashtable -Object $call.parameters
                $tool = $script:TOOLS[$call.name]
                if (-not $tool) {
                    throw "Unknown tool '$($call.name)' requested."
                }
                $label = & $tool.FormatLabel $params


                Write-Host ""
                Write-Host " Tool request: " -NoNewline -ForegroundColor DarkGray
                Write-Host $label -ForegroundColor White
                Write-Host ""

                $choice = Show-ArrowMenu `
                    -Options @("Allow once", "Deny") `
                    -Title "Action Required  $BUL  $label" `
                    -Width 100 `
                    -Default 0

                if ($choice -ne 0) {
                    Write-Host ""
                    Draw-Box @("$CRS  Tool call denied.") -Color Red
                    $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $script:history += @{ role = "user";  parts = @(@{ text = "TOOL RESULT: The user denied this tool call. Please respond without using that tool." }) }
                    continue
                }

                Write-Host ""
                Draw-Box @("$CHK  $label") -Color Magenta

                # Execute tool directly in the main session as in 019
                # but with a simple Esc check loop if possible
                Start-Spinner -Label "Executing $($call.name) (Esc to cancel)"

                $script:toolJob = Start-Job -ScriptBlock {
                    param($toolName, $params, $toolsDir, $workDir, $scriptDir, $apiKey, $baseUri, $model, $toolLimits, $configDir)
                    Set-Location -Path $workDir
                    
                    # Initialize core script state inside the job
                    $script:API_KEY = $apiKey
                    $script:BASE_URI_BASE = $baseUri
                    $script:MODEL = $model
                    $script:TOOL_LIMITS = $toolLimits
                    $script:configDir = $configDir
                    $script:apiCallLog_Gemma = [System.Collections.Generic.List[datetime]]::new()
                    $script:apiCallLog_Gemini = [System.Collections.Generic.List[datetime]]::new()
                    $script:lastApiCall = (Get-Date).AddSeconds(-10)
                    $script:lastApiCall_Gemini = (Get-Date).AddSeconds(-10)

                    # Dot-source core libraries inside the job
                    . (Join-Path $scriptDir "lib/Api.ps1")
                    . (Join-Path $scriptDir "lib/History.ps1")
                    . (Join-Path $scriptDir "lib/UI.ps1")

                    $toolFile = Join-Path $toolsDir "$toolName.ps1"
                    if (-not (Test-Path $toolFile)) {
                        return "ERROR: Tool file '$toolFile' not found."
                    }
                    
                    try {
                        # Force reading the tool script as UTF-8 to handle Unicode characters correctly
                        $toolContent = Get-Content -Path $toolFile -Raw -Encoding UTF8
                        Invoke-Expression -Command $toolContent

                        if (-not $ToolMeta.Execute) {
                            return "ERROR: Tool '$toolName' is missing its 'Execute' scriptblock."
                        }
                        # Invoke the tool's execution block with the parameters
                        return & $ToolMeta.Execute $params
                    } catch {
                        return "ERROR: Exception while executing tool '$toolName': $($_.Exception.Message) | StackTrace: $($_.ScriptStackTrace)"
                    } finally {
                        $ToolMeta = $null
                    }
                } -ArgumentList $call.name, $params, (Join-Path $scriptDir "tools"), (Get-Location), $scriptDir, $script:API_KEY, $script:BASE_URI_BASE, $script:MODEL, $script:TOOL_LIMITS, $script:configDir


                $cancelled = $false
                while ($script:toolJob.State -eq "Running") {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq "Escape") {
                            $cancelled = $true
                            Stop-Job $script:toolJob
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                }

                if ($cancelled) {
                    Stop-Spinner
                    Remove-Job $script:toolJob
                    Write-Host " [Tool execution cancelled by user]" -ForegroundColor Yellow
                    break
                }

                $result = Receive-Job $script:toolJob
                Remove-Job $script:toolJob
                Stop-Spinner
                if ($script:debugMode) { Write-Host "`n[DEBUG] Tool Execution Result: $result" -ForegroundColor Yellow }

                # Ensure result is a single clean string (job may return string[])
                if ($result -is [array]) { $result = $result -join "`n" }
                if (-not $result) { $result = "(empty result)" }

                # Strip control characters (null bytes, BOM, etc.) that break JSON
                $result = $result -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
                # Remove UTF-8 BOM if present
                $result = $result.TrimStart([char]0xFEFF)

                $maxChars = 20000
                $truncated = $false
                if ($result.Length -gt $maxChars) {
                  $result = $result.Substring(0, $maxChars)
                  $truncated = $true
                }
                $truncNote = if ($truncated) { "`n[Note: file was truncated to $maxChars characters due to size limits]" } else { "" }

                # Handle image tool results — inject as multimodal content
                if ($result -match "^IMAGE_DATA::([^:]+)::([^:]+)::(.+)$") {
                    $mime   = $matches[1]
                    $b64    = $matches[2]
                    $prompt = $matches[3]
                    $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $script:history += @{
                        role  = "user"
                        parts = @(
                            @{ text = "TOOL RESULT: Image loaded. $prompt" },
                            @{ inline_data = @{ mime_type = $mime; data = $b64 } }
                        )
                    }
                } else {
                    $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $script:history += @{ role = "user"; parts = @(@{ text = "TOOL RESULT:`n$result$truncNote`n`nNow respond to the user based on context. Do not call this tool again immediately." }) }
                }

                Write-ApiLog -toolName $call.name
                continue

            } catch {
                Write-Host "Tool call parse error: $($_.Exception.Message)" -ForegroundColor Red
                break
            }

       } else {
            if ($script:debugMode) {
                Write-Host "`n[DEBUG] Raw Model Text: $modelText" -ForegroundColor Yellow
            }
            $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
            Render-ModelText -text $modelText
            break
        }
    }
}

Write-Host ""
Draw-Box @("Goodbye!  Thanks for using Gemma CLI.") -Color $script:Colors.ui_boxes
