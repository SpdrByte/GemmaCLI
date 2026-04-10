# ===============================================
# GemmaCLI Tool - arduino_boards.ps1 v0.3.0

# Responsibility: Board knowledge for the Arduino family.
#                 Lists boards, pins, protocols, metadata, and renders
#                 ASCII board diagrams with optional AEL pin highlighting.
#                 Does NOT generate or validate AEL — use ael_validate for that.
# Depends on: database/dev_boards.json
# ===============================================

# ====================== PIN TYPE COLOR MAP ======================
# Returns a ConsoleColor string for a given AEL pin type
function Get-PinColor {
    param([string]$pinType, [string[]]$protocols = @())

    # Protocol-specific color takes priority over base type
    foreach ($proto in $protocols) {
        switch -Wildcard ($proto.ToUpper()) {
            "I2C*"    { return "Blue"     }
            "UART*"   { return "Magenta"  }
            "SPI*"    { return "DarkCyan" }
            "PWM"     { return "Yellow"   }
            "ADC"     { return "Green"    }
        }
    }

    # Fall back to base type color
    switch ($pinType) {
        "POWER_OUT" { return "Yellow"   }
        "POWER_IN"  { return "Yellow"   }
        "GROUND"    { return "DarkGray" }
        "IO"        { return "Green"    }
        "INPUT"     { return "Cyan"     }
        "OUTPUT"    { return "Cyan"     }
        default     { return "White"    }
    }
}
# ====================== BOARD DATABASE LOADER ======================
function Load-BoardDatabase {
    param([string]$scriptDir)

    $dbPath = Join-Path $scriptDir "database/dev_boards.json"
    if (-not (Test-Path $dbPath)) {
        return @{ ok=$false; error="Board database not found at: $dbPath" }
    }

    try {
        $raw = Get-Content $dbPath -Raw | ConvertFrom-Json
        $db  = @{}
        foreach ($prop in $raw.PSObject.Properties) {
            $db[$prop.Name] = $prop.Value
        }
        return @{ ok=$true; db=$db }
    } catch {
        return @{ ok=$false; error="Failed to parse dev_boards.json: $($_.Exception.Message)" }
    }
}

# ====================== ASCII BOARD DIAGRAM RENDERER ======================
function Render-BoardDiagram {
    param(
        [string]$boardId,
        [object]$boardObj,
        [string[]]$usedPins   # raw pin names currently in use e.g. @("D2","GND","5V")
    )

    if (-not $boardObj.layout) {
        Write-Host "  No layout defined for '$boardId' in dev_boards.json" -ForegroundColor Yellow
        return
    }

    $leftPins  = @($boardObj.layout.left)
    $rightPins = @($boardObj.layout.right)
    $rows      = [Math]::Max($leftPins.Count, $rightPins.Count)

    # 1. Measure longest pin names
    $leftMax = 2
    foreach ($p in $leftPins)  { if ($p.Length -gt $leftMax)  { $leftMax  = $p.Length } }
    $rightMax = 2
    foreach ($p in $rightPins) { if ($p.Length -gt $rightMax) { $rightMax = $p.Length } }

    # 2. Dynamic Body Width based on label
    $boardLabel  = $boardObj.label.ToUpper()
    $bodyWidth   = [Math]::Max(15, $boardLabel.Length + 2)
    
    # 3. Calculate Wing Lengths
    # Wing must cover: Label(3) + Gutter(2) + LeftMax + Marker(1) + Gap(1) = LeftMax + 6
    $leftWingW   = $leftMax + 6
    $rightWingW  = $rightMax + 6

    # Top border symbols
    $borderLine  = [string][char]0x2500   # ─
    $TL          = [string][char]0x256D   # ╭
    $TR          = [string][char]0x256E   # ╮
    $BL          = [string][char]0x2570   # ╰
    $BR          = [string][char]0x256F   # ╯
    $V           = [string][char]0x2502   # │

    # Centering the label in the body
    $labelPad    = [Math]::Max(0, $bodyWidth - $boardLabel.Length)
    $lPad        = [Math]::Floor($labelPad / 2)
    $rPad        = $labelPad - $lPad
    
    $titleBar    = $TL + ($borderLine * $leftWingW) + $TL + (" " * $lPad) + $boardLabel + (" " * $rPad) + $TR + ($borderLine * $rightWingW) + $TR

    Write-Host ""
    Write-Host ("  " + $titleBar) -ForegroundColor White

    for ($i = 0; $i -lt $rows; $i++) {
        $rowNum    = "L$($i+1)".PadLeft(3)
        $lPin      = if ($i -lt $leftPins.Count)  { $leftPins[$i]  } else { "" }
        $rPin      = if ($i -lt $rightPins.Count) { $rightPins[$i] } else { "" }
        $rRowNum   = "R$($i+1)".PadRight(3)

        # Look up pin data
        $lPinData  = if ($lPin -and $boardObj.pins.PSObject.Properties[$lPin]) { $boardObj.pins.PSObject.Properties[$lPin].Value } else { $null }
        $rPinData  = if ($rPin -and $boardObj.pins.PSObject.Properties[$rPin]) { $boardObj.pins.PSObject.Properties[$rPin].Value } else { $null }
        $lType     = if ($lPinData) { $lPinData.type }      else { "IO" }
        $rType     = if ($rPinData) { $rPinData.type }      else { "IO" }
        $lProtos   = if ($lPinData -and $lPinData.protocols) { @($lPinData.protocols) } else { @() }
        $rProtos   = if ($rPinData -and $rPinData.protocols) { @($rPinData.protocols) } else { @() }
        $lColor    = Get-PinColor -pinType $lType -protocols $lProtos
        $rColor    = Get-PinColor -pinType $rType -protocols $rProtos

        $lUsed     = ($usedPins -contains $lPin) -and ($lPin -ne "")
        $rUsed     = ($usedPins -contains $rPin) -and ($rPin -ne "")
        $lMark     = if ($lUsed) { "*" } else { " " }
        $rMark     = if ($rUsed) { "*" } else { " " }

        # Print row
        Write-Host "  " -NoNewline
        Write-Host $rowNum -NoNewline -ForegroundColor DarkGray
        Write-Host "  " -NoNewline # Gutter

        # Left Pin
        if ($lUsed) {
            Write-Host $lPin.PadRight($leftMax) -NoNewline -ForegroundColor White -BackgroundColor DarkGreen
            Write-Host $lMark -NoNewline -ForegroundColor Green
        } else {
            Write-Host $lPin.PadRight($leftMax) -NoNewline -ForegroundColor $lColor
            Write-Host $lMark -NoNewline -ForegroundColor DarkGray
        }

        # Body Walls and Gap
        Write-Host " $V" -NoNewline -ForegroundColor DarkGray
        Write-Host (" " * $bodyWidth) -NoNewline -ForegroundColor DarkGray
        Write-Host "$V " -NoNewline -ForegroundColor DarkGray

        # Right Pin
        if ($rUsed) {
            Write-Host $rMark -NoNewline -ForegroundColor Green
            Write-Host $rPin.PadLeft($rightMax) -NoNewline -ForegroundColor White -BackgroundColor DarkGreen
        } else {
            Write-Host $rMark -NoNewline -ForegroundColor DarkGray
            Write-Host $rPin.PadLeft($rightMax) -NoNewline -ForegroundColor $rColor
        }

        Write-Host "  " -NoNewline # Gutter
        Write-Host $rRowNum -ForegroundColor DarkGray
    }

    # Bottom border
    $bottomBar = $BL + ($borderLine * $leftWingW) + $BL + ($borderLine * $bodyWidth) + $BR + ($borderLine * $rightWingW) + $BR
    Write-Host ("  " + $bottomBar) -ForegroundColor White
    Write-Host ""

    # Legend
    Write-Host "  " -NoNewline
    Write-Host "IO " -NoNewline -ForegroundColor Green
    Write-Host " POWER " -NoNewline -ForegroundColor Yellow
    Write-Host " GND " -NoNewline -ForegroundColor DarkGray
    Write-Host " UART " -NoNewline -ForegroundColor Magenta
    Write-Host " I2C " -NoNewline -ForegroundColor Blue
    Write-Host " SPI " -NoNewline -ForegroundColor DarkCyan
    Write-Host " ADC " -NoNewline -ForegroundColor Green
    if ($usedPins.Count -gt 0) {
        Write-Host "  * = in use" -NoNewline -ForegroundColor Green
    }
    Write-Host ""
    Write-Host ""
}

# ====================== MAIN FUNCTION ======================
function Invoke-ArduinoBoards {
    param(
        [string]$action,
        [string]$board,
        [string]$protocol,
        [string]$pin,
        [string]$ael,
        [string]$scriptDir,
        [string]$vendor = "Arduino"
    )

    $action = $action.Trim().ToLower()
    Stop-Spinner

    # --- Load DB ---
    $load = Load-BoardDatabase -scriptDir $scriptDir
    if (-not $load.ok) { return $load.error }
    
    # Filter DB by vendor if specified
    $db = @{}
    if ($vendor) {
        foreach ($id in $load.db.Keys) {
            if ($load.db[$id].vendor -match $vendor) {
                $db[$id] = $load.db[$id]
            }
        }
    } else {
        $db = $load.db
    }

    if ($db.Count -eq 0) {
        return "ERROR: No boards found for vendor '$vendor'."
    }

    # ---- LIST BOARDS ----
    if ($action -eq "list_boards") {
        $lines = @("Supported boards (Vendor: $vendor)", "")
        foreach ($id in ($db.Keys | Sort-Object)) {
            $b        = $db[$id]
            $pinCount = ($b.pins.PSObject.Properties | Measure-Object).Count
            $lines   += "  $($id.PadRight(28)) $($b.label)   ($pinCount pins)"
        }
        Draw-Box -Lines $lines -Title "Board Database" -Color Cyan
        $result = ($db.Keys | Sort-Object | ForEach-Object {
            $b = $db[$_]
            @{ id=$_; label=$b.label; pin_count=($b.pins.PSObject.Properties | Measure-Object).Count; vendor=$b.vendor }
        }) | ConvertTo-Json -Depth 5
        return "CONSOLE::Board list rendered.::END_CONSOLE::$result"
    }

    # --- All remaining actions require a board ---
    if ([string]::IsNullOrWhiteSpace($board)) {
        return "ERROR: 'board' parameter required for action '$action'. Use action='list_boards' to see available boards."
    }

    $boardId = $board.Trim().ToLower()
    if (-not $db.ContainsKey($boardId)) {
        $available = ($db.Keys | Sort-Object) -join ", "
        return "ERROR: Board '$boardId' not found. Available: $available"
    }
    $boardObj = $db[$boardId]

    # ---- DIAGRAM ----
    if ($action -eq "diagram") {
        Stop-Spinner
        # Parse used pins from AEL if provided
        $usedPins = @()
        if (-not [string]::IsNullOrWhiteSpace($ael)) {
            $matches2 = [regex]::Matches($ael, '\b\w+\.(\w+)\b')
            foreach ($m in $matches2) {
                $pinName = $m.Groups[1].Value
                if ($boardObj.pins.PSObject.Properties[$pinName]) {
                    if ($usedPins -notcontains $pinName) { $usedPins += $pinName }
                }
            }
        }

        Render-BoardDiagram -boardId $boardId -boardObj $boardObj -usedPins $usedPins

        $result = @{
            board      = $boardId
            label      = $boardObj.label
            used_pins  = $usedPins
            layout     = $boardObj.layout
        } | ConvertTo-Json -Depth 5

        $usedNote = if ($usedPins.Count -gt 0) { " Used pins: $($usedPins -join ', ')." } else { "" }
        return "CONSOLE::Board diagram rendered for $($boardObj.label).$usedNote::END_CONSOLE::$result`n→ INSTRUCTION: The board diagram has already been drawn to the terminal. Do NOT redraw. Acknowledge result briefly."
    }

    # ---- LIST PINS ----
    if ($action -eq "list_pins") {
        $lines  = @("$($boardObj.label)", "")
        foreach ($pinProp in ($boardObj.pins.PSObject.Properties | Sort-Object Name)) {
            $p      = $pinProp.Value
            $proto  = if ($p.protocols -and $p.protocols.Count -gt 0) { " [$($p.protocols -join ', ')]" } else { "" }
            $volt   = if ($p.voltage) { " $($p.voltage)V" } else { "" }
            $lines += "  $($pinProp.Name.PadRight(12)) $($p.type.PadRight(12))$volt$proto"
        }
        Draw-Box -Lines $lines -Title "Pins: $boardId" -Color Cyan
        $result = @{ board=$boardId; label=$boardObj.label; pins=$boardObj.pins } | ConvertTo-Json -Depth 6
        return "CONSOLE::Board list rendered.::END_CONSOLE::$result"
    }

    # ---- FILTER BY PROTOCOL ----
    if ($action -eq "filter_protocol") {
        if ([string]::IsNullOrWhiteSpace($protocol)) {
            return "ERROR: 'protocol' parameter required for action 'filter_protocol'. Example: I2C, SPI, UART"
        }
        $protoUpper = $protocol.Trim().ToUpper()
        $matched    = @{}
        foreach ($pinProp in $boardObj.pins.PSObject.Properties) {
            $p = $pinProp.Value
            if ($p.protocols) {
                $protos = @($p.protocols) | ForEach-Object { $_.ToUpper() }
                if ($protos | Where-Object { $_ -like "*$protoUpper*" }) {
                    $matched[$pinProp.Name] = $p
                }
            }
        }
        $lines = @("$($boardObj.label) — $protoUpper capable pins", "")
        if ($matched.Count -eq 0) {
            $lines += "  No pins found supporting '$protoUpper'"
        } else {
            foreach ($pinName in ($matched.Keys | Sort-Object)) {
                $p      = $matched[$pinName]
                $proto  = "[$($p.protocols -join ', ')]"
                $lines += "  $($pinName.PadRight(12)) $($p.type.PadRight(12)) $proto"
            }
        }
        Draw-Box -Lines $lines -Title "$protoUpper Pins: $boardId" -Color Cyan
        $result = @{ board=$boardId; protocol=$protoUpper; pins=$matched } | ConvertTo-Json -Depth 6
        return "CONSOLE::Board list rendered.::END_CONSOLE::$result"
    }

    # ---- CHECK PIN ----
    if ($action -eq "check_pin") {
        if ([string]::IsNullOrWhiteSpace($pin)) {
            return "ERROR: 'pin' parameter required for action 'check_pin'. Example: D2, 5V, GND"
        }
        $pinName = $pin.Trim()
        $pinData = $null
        foreach ($pinProp in $boardObj.pins.PSObject.Properties) {
            if ($pinProp.Name -eq $pinName) { $pinData = $pinProp.Value; break }
        }
        if (-not $pinData) {
            $similar    = $boardObj.pins.PSObject.Properties | Where-Object { $_.Name -like "*$pinName*" } | ForEach-Object { $_.Name }
            $suggestion = if ($similar) { "Did you mean: $($similar -join ', ')?" } else { "Use action='list_pins' to see all pins." }
            $lines      = @("Pin '$pinName' does NOT exist on $($boardObj.label)", "", $suggestion)
            Draw-Box -Lines $lines -Title "Pin Check: $boardId" -Color Red
            return (@{ board=$boardId; pin=$pinName; exists=$false; message="Pin '$pinName' not found. $suggestion" } | ConvertTo-Json -Depth 4)
        }
        $proto = if ($pinData.protocols -and $pinData.protocols.Count -gt 0) { @($pinData.protocols) } else { @() }
        $lines = @(
            "Pin '$pinName' on $($boardObj.label)", "",
            "  Type       $($pinData.type)",
            "  Voltage    $(if ($pinData.voltage) { "$($pinData.voltage)V" } else { 'N/A' })",
            "  Protocols  $(if ($proto.Count -gt 0) { $proto -join ', ' } else { 'None' })"
        )
        Draw-Box -Lines $lines -Title "Pin Check: $boardId" -Color Green
        $result = @{ board=$boardId; pin=$pinName; exists=$true; type=$pinData.type; voltage=$pinData.voltage; protocols=$proto } | ConvertTo-Json -Depth 4
        return "CONSOLE::Board list rendered.::END_CONSOLE::$result"
    }

    # ---- PIN METADATA ----
    if ($action -eq "pin_metadata") {
        if ([string]::IsNullOrWhiteSpace($pin)) {
            return "ERROR: 'pin' parameter required for action 'pin_metadata'."
        }
        $pinName = $pin.Trim()
        $pinData = $null
        foreach ($pinProp in $boardObj.pins.PSObject.Properties) {
            if ($pinProp.Name -eq $pinName) { $pinData = $pinProp.Value; break }
        }
        if (-not $pinData) {
            return "ERROR: Pin '$pinName' not found on '$boardId'. Use action='list_pins' to see all pins."
        }
        $proto   = if ($pinData.protocols -and $pinData.protocols.Count -gt 0) { @($pinData.protocols) } else { @() }
        $aelType = $pinData.type
        $notes   = @()
        if ($pinData.notes)          { $notes += $pinData.notes }
        if ($aelType -eq "IO")        { $notes += "Digital I/O pin" }
        if ($aelType -eq "POWER_OUT") { $notes += "Power rail — use POWER keyword in AEL" }
        if ($aelType -eq "GROUND")    { $notes += "Ground reference — use POWER or NET in AEL" }
        $lines = @(
            "$boardId  $ARR  $pinName", "",
            "  AEL Type     $aelType",
            "  Voltage      $(if ($pinData.voltage) { "$($pinData.voltage)V" } else { 'N/A' })",
            "  Protocols    $(if ($proto.Count -gt 0) { $proto -join ', ' } else { 'None' })"
        )
        if ($notes.Count -gt 0) {
            $lines += ""
            $lines += "  Notes:"
            foreach ($n in $notes) { $lines += "    $BUL $n" }
        }
        Draw-Box -Lines $lines -Title "Pin Metadata" -Color Cyan
        $result = @{ board=$boardId; pin=$pinName; ael_type=$aelType; voltage=$pinData.voltage; protocols=$proto; notes=$notes } | ConvertTo-Json -Depth 4
        return "CONSOLE::Board list rendered.::END_CONSOLE::$result"
    }

    return "ERROR: Unknown action '$action'. Valid actions: list_boards, list_pins, filter_protocol, check_pin, pin_metadata, diagram"
}

# ====================== TOOL REGISTRATION ======================

$ToolMeta = @{
    Name        = "arduino_boards"
    Icon        = "🔌"
    RendersToConsole = $true
    Category    = @("Physical Computing")
    Relationships = @{
        "ael_validate" = "Use this synergy for advanced physical computing workflows. When the user requests a circuit, first use 'arduino_boards' to find valid pin names and protocol-capable pins (PWM, I2C, etc.). Generate the AEL circuit, then call 'ael_validate' to verify it. ONLY after a successful validation should you call 'arduino_boards' with action='diagram' and the 'ael' parameter to show the user the final, verified wiring diagram."
    }
    Behavior    = "Provides pin maps, protocol capabilities, voltage data, and ASCII board diagrams for the Arduino family. Call this ONLY when the user explicitly requests circuit help, pin information, or a board diagram for an Arduino board. Do NOT call proactively or at session start."
    Description = "Query Arduino board data: list boards, list pins, filter by protocol, check pin existence, get pin metadata, or render an ASCII board diagram with optional AEL pin highlighting."
    Parameters  = @{
        action   = "string - one of: list_boards | list_pins | filter_protocol | check_pin | pin_metadata | diagram"
        board    = "string (optional for list_boards) - board id e.g. arduino_uno"
        protocol = "string (required for filter_protocol) - e.g. I2C, SPI, UART, PWM, ADC"
        pin      = "string (required for check_pin, pin_metadata) - e.g. D2, A0, GND"
        ael      = "string (optional for diagram) - AEL circuit text; used pins will be highlighted on the diagram"
        vendor   = "string (optional) - filter boards by vendor, default 'Arduino'"
    }
    Example     = @"
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "list_boards" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "diagram", "board": "arduino_uno" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "diagram", "board": "arduino_uno", "ael": "BOARD arduino_uno AS ard\nCOMP led1 LED\nWIRE ard.D13 -> led1.A\nWIRE led1.C -> ard.GND" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "list_pins", "board": "arduino_uno" } }</tool_call>
<tool_call>{ "name": "arduino_boards", "parameters": { "action": "filter_protocol", "board": "arduino_uno", "protocol": "PWM" } }</tool_call>
"@
    FormatLabel = { param($p)
        $b   = if ($p.board) { " $ARR $($p.board)" } else { "" }
        $vndr = if ($p.vendor -and $p.vendor -ne "Arduino") { " [$($p.vendor)]" } else { "" }
        $pin = if ($p.pin)   { " [$($p.pin)]" }       else { "" }
        "$($p.action)$b$vndr$pin"
    }
    Execute     = {
        param($params)
        $vndr = "Arduino"; if ($params.vendor) { $vndr = $params.vendor }
        Invoke-ArduinoBoards `
            -action   $params.action `
            -board    $params.board `
            -protocol $params.protocol `
            -pin      $params.pin `
            -ael      $params.ael `
            -scriptDir $scriptDir `
            -vendor   $vndr
    }
    ToolUseGuidanceMajor = @"
- When to use 'arduino_boards': ALWAYS use when the user explicitly asks for a circuit, pin information, or a board diagram for an Arduino board. Do not draw your own. 
- action='diagram' renders a colour-coded ASCII board layout. Pass 'ael' to highlight which pins are in use.
- action='list_boards' — no other params needed
- action='list_pins' — requires 'board'
- action='filter_protocol' — requires 'board' and 'protocol' (I2C, SPI, UART, PWM, ADC)
- action='check_pin' — requires 'board' and 'pin'
- action='pin_metadata' — requires 'board' and 'pin'
- action='diagram' — requires 'board'; 'ael' is optional for pin highlighting
- AEL pin reference format: alias.PINNAME e.g. ard.D13
"@
    ToolUseGuidanceMinor = @"
- Purpose: Arduino board pin data and diagrams.
- Use diagram action after generating validated AEL to show the user which pins are in use.
- Use filter_protocol to find I2C/SPI/UART/PWM pins before writing BUS statements.
"@
}
