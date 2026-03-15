# ===============================================
# GemmaCLI Tool - ael_validate.ps1 v1.1.0
# Responsibility: Parses and validates AEL (ASCII Electronics Language) v0.3
#                 circuits. Returns structured JSON errors for LLM self-correction.
#                 Board-agnostic — works with any board definition.
# Depends on: database/boards.json, database/components.json
# ===============================================

# ====================== AEL GRAMMAR CONSTANTS ======================

$AEL_WIRE_RULES = @{
    # [sourceType][destType] = $true/false
    "OUTPUT"   = @{ "INPUT"="ok"; "IO"="ok"; "PASSIVE"="ok"; "GROUND"="ok" }
    "IO"       = @{ "INPUT"="ok"; "IO"="ok"; "PASSIVE"="ok"; "OUTPUT"="ok"; "GROUND"="ok" }
    "INPUT"    = @{ }   # INPUT cannot drive anything
    "PASSIVE"  = @{ "INPUT"="ok"; "IO"="ok"; "OUTPUT"="ok"; "PASSIVE"="ok"; "GROUND"="ok" }
}

$AEL_POWER_RULES = @{
    "POWER_OUT" = @{ "POWER_IN"="ok"; "GROUND"="ok"; "POWER_OUT"="ok" }
    "GROUND"    = @{ "GROUND"="ok" }
}

$AEL_BUS_RULES = @{
    "IO"    = @{ "IO"="ok" }
    "UART_TX" = @{ "UART_RX"="ok" }
    "UART_RX" = @{ "UART_TX"="ok" }
    "I2C_SDA" = @{ "I2C_SDA"="ok" }
    "I2C_SCL" = @{ "I2C_SCL"="ok" }
    "SPI_MOSI"= @{ "SPI_MISO"="ok"; "SPI_MOSI"="ok" }
    "SPI_MISO"= @{ "SPI_MOSI"="ok"; "SPI_MISO"="ok" }
    "SPI_SCK" = @{ "SPI_SCK"="ok" }
}

# Component library is loaded from database/components.json at validation time
# $AEL_COMPONENT_LIBRARY is populated by Load-ComponentLibrary

function Load-ComponentLibrary {
    param([string]$scriptDir)

    $dbPath = Join-Path $scriptDir "database/components.json"
    if (-not (Test-Path $dbPath)) {
        # Fallback minimal library if file missing
        return @{
            ok      = $true
            library = @{
                "LED"    = @{ pins = @{ "A"="PASSIVE"; "C"="PASSIVE" }; vcc_range=$null }
                "RES"    = @{ pins = @{ "A"="PASSIVE"; "B"="PASSIVE" }; vcc_range=$null }
                "BUTTON" = @{ pins = @{ "A"="PASSIVE"; "B"="PASSIVE" }; vcc_range=$null }
            }
            warning = "database/components.json not found — using minimal fallback library"
        }
    }

    try {
        $raw     = Get-Content $dbPath -Raw | ConvertFrom-Json
        $library = @{}

        foreach ($prop in $raw.PSObject.Properties) {
            # Skip the _notes meta key
            if ($prop.Name.StartsWith("_")) { continue }

            $entry   = $prop.Value
            $pinMap  = @{}
            foreach ($pinProp in $entry.pins.PSObject.Properties) {
                $pinMap[$pinProp.Name] = $pinProp.Value
            }

            $vccRange = $null
            if ($entry.vcc_range -and $entry.vcc_range.Count -eq 2) {
                $vccRange = @([float]$entry.vcc_range[0], [float]$entry.vcc_range[1])
            }

            $library[$prop.Name] = @{
                pins      = $pinMap
                vcc_range = $vccRange
                label     = if ($entry.label)       { $entry.label }       else { $prop.Name }
                description = if ($entry.description) { $entry.description } else { "" }
            }
        }

        return @{ ok=$true; library=$library; warning=$null }

    } catch {
        return @{ ok=$false; library=@{}; warning="Failed to parse components.json: $($_.Exception.Message)" }
    }
}

# ====================== PARSER ======================

function Parse-AEL {
    param([string]$aelText, [hashtable]$componentLibrary = @{})

    $parsed = @{
        boards     = @{}   # alias -> board_id
        components = @{}   # id -> { type, attrs, pins }
        wires      = @()   # { line, src, dst }
        powers     = @()   # { line, src, dst }
        buses      = @()   # { line, src, dst }
        nets       = @{}   # name -> [pins]
        errors     = [System.Collections.Generic.List[hashtable]]::new()
        raw_lines  = @()
    }

    $lineNum = 0
    foreach ($rawLine in ($aelText -split "`n")) {
        $lineNum++
        $line = $rawLine.Trim()
        $parsed.raw_lines += $line

        # Skip blanks and comments
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith("#"))               { continue }

        # ---- BOARD ----
        if ($line -match '^BOARD\s+(\S+)\s+AS\s+(\S+)$') {
            $boardId = $matches[1].ToLower()
            $alias   = $matches[2].ToLower()
            $parsed.boards[$alias] = $boardId
            continue
        }
        if ($line -match '^BOARD\s+(\S+)$') {
            $boardId = $matches[1].ToLower()
            $parsed.boards[$boardId] = $boardId
            continue
        }

        # ---- COMP ----
        if ($line -match '^COMP\s+(\S+)\s+(\S+)(.*)$') {
            $compId   = $matches[1]
            $compType = $matches[2].ToUpper()
            $attrStr  = $matches[3].Trim()

            $attrs = @{}
            $attrMatches = [regex]::Matches($attrStr, '(\w+)=([\w%\.]+)')
            foreach ($m in $attrMatches) {
                $attrs[$m.Groups[1].Value] = $m.Groups[2].Value
            }

            if (-not $componentLibrary.ContainsKey($compType)) {
                $parsed.errors.Add(@{
                    line       = $lineNum
                    token      = $compType
                    code       = "UNKNOWN_COMPONENT"
                    severity   = "ERROR"
                    message    = "Component type '$compType' is not in the component library"
                    suggestion = "Known types: $($componentLibrary.Keys -join ', ')"
                })
            }

            $libEntry = $componentLibrary[$compType]
            $parsed.components[$compId] = @{
                type     = $compType
                attrs    = $attrs
                pins     = if ($libEntry) { $libEntry.pins } else { @{} }
                vcc_range= if ($libEntry) { $libEntry.vcc_range } else { $null }
                line     = $lineNum
            }
            continue
        }

        # ---- WIRE ----
        if ($line -match '^WIRE\s+(\S+)\s*->\s*(\S+)$') {
            $parsed.wires += @{ line=$lineNum; src=$matches[1]; dst=$matches[2] }
            continue
        }

        # ---- POWER ----
        if ($line -match '^POWER\s+(\S+)\s*->\s*(\S+)$') {
            $parsed.powers += @{ line=$lineNum; src=$matches[1]; dst=$matches[2] }
            continue
        }

        # ---- BUS ----
        if ($line -match '^BUS\s+(\S+)\s*->\s*(\S+)$') {
            $parsed.buses += @{ line=$lineNum; src=$matches[1]; dst=$matches[2] }
            continue
        }

        # ---- NET ----
        if ($line -match '^NET\s+(\S+)\s+(.+)$') {
            $netName = $matches[1]
            $pins    = $matches[2] -split '\s+' | Where-Object { $_ -ne '' }
            $parsed.nets[$netName] = $pins
            continue
        }

        # ---- Unknown ----
        $parsed.errors.Add(@{
            line       = $lineNum
            token      = $line.Split(' ')[0]
            code       = "UNKNOWN_STATEMENT"
            severity   = "ERROR"
            message    = "Unrecognised statement: '$line'"
            suggestion = "Valid keywords: BOARD, COMP, WIRE, POWER, BUS, NET"
        })
    }

    return $parsed
}

# ====================== PIN RESOLVER ======================

function Resolve-Pin {
    param(
        [string]$pinRef,
        [hashtable]$parsed,
        [hashtable]$boardData   # loaded from boards.json — alias -> board object
    )
    # pinRef format: alias.PINNAME  or  compId.PINNAME

    if ($pinRef -notmatch '^(\S+)\.(\S+)$') {
        return @{ ok=$false; error="Invalid pin reference format '$pinRef' — expected owner.PIN e.g. esp.5V. Board pins must use the board alias as prefix e.g. esp.5V not just 5V" }
    }

    $owner   = $matches[1]
    $pinName = $matches[2]

    # Is it a board alias?
    if ($parsed.boards.ContainsKey($owner)) {
        $boardId = $parsed.boards[$owner]
        if (-not $boardData.ContainsKey($boardId)) {
            return @{ ok=$false; error="Board '$boardId' not found in database" }
        }
        $board = $boardData[$boardId]
        if (-not $board.pins.ContainsKey($pinName)) {
            $available = ($board.pins.Keys | Sort-Object) -join ', '
            return @{ ok=$false; error="Pin '$pinName' does not exist on board '$boardId'. Available: $available" }
        }
        $pin = $board.pins[$pinName]
        return @{
            ok       = $true
            type     = $pin.type
            voltage  = if ($pin.voltage) { $pin.voltage } else { $null }
            owner    = $owner
            pinName  = $pinName
            isBoardPin = $true
        }
    }

    # Is it a component?
    if ($parsed.components.ContainsKey($owner)) {
        $comp = $parsed.components[$owner]
        if (-not $comp.pins.ContainsKey($pinName)) {
            $available = ($comp.pins.Keys) -join ', '
            return @{ ok=$false; error="Pin '$pinName' does not exist on component '$owner' ($($comp.type)). Available: $available" }
        }
        $pinType = $comp.pins[$pinName]
        return @{
            ok      = $true
            type    = $pinType
            voltage = $null
            owner   = $owner
            pinName = $pinName
            isBoardPin = $false
        }
    }

    return @{ ok=$false; error="Unknown owner '$owner' — not a declared board alias or component" }
}

# ====================== VALIDATOR ======================

function Invoke-AELValidate {
    param(
        [string]$aelText,
        [string]$scriptDir
    )

    $errors  = [System.Collections.Generic.List[hashtable]]::new()
    $warnings= [System.Collections.Generic.List[hashtable]]::new()

    # --- Load component library ---
    $compLoad = Load-ComponentLibrary -scriptDir $scriptDir
    $AEL_COMPONENT_LIBRARY = $compLoad.library
    if ($compLoad.warning) {
        $warnings.Add(@{
            line       = 0
            token      = "components.json"
            code       = "COMPONENT_LIBRARY_WARNING"
            severity   = "WARNING"
            message    = $compLoad.warning
            suggestion = "Add database/components.json for full component validation"
        })
    }
    if (-not $compLoad.ok) {
        return (@{
            valid    = $false
            errors   = @(@{
                line       = 0
                token      = "components.json"
                code       = "COMPONENT_LIBRARY_FAILED"
                severity   = "ERROR"
                message    = $compLoad.warning
                suggestion = "Ensure database/components.json exists and is valid JSON"
            })
            warnings = @()
            summary  = "Component library load failed"
        } | ConvertTo-Json -Depth 10)
    }

    # --- Load board database ---
    $dbPath = Join-Path $scriptDir "database/boards.json"
    $boardData = @{}
    if (Test-Path $dbPath) {
        try {
            $raw = Get-Content $dbPath -Raw | ConvertFrom-Json
            foreach ($prop in $raw.PSObject.Properties) {
                $board = $prop.Value
                $pinMap = @{}
                foreach ($pinProp in $board.pins.PSObject.Properties) {
                    $p = $pinProp.Value
                    $pinMap[$pinProp.Name] = @{
                        type      = $p.type
                        voltage   = if ($p.voltage) { [float]$p.voltage } else { $null }
                        protocols = if ($p.protocols) { @($p.protocols) } else { @() }
                    }
                }
                $boardData[$prop.Name] = @{
                    id          = $prop.Name
                    label       = $board.label
                    pins        = $pinMap
                    default_vcc = if ($board.default_vcc) { [float]$board.default_vcc } else { 3.3 }
                }
            }
        } catch {
            return (@{
                valid    = $false
                errors   = @(@{
                    line       = 0
                    token      = "boards.json"
                    code       = "DATABASE_LOAD_FAILED"
                    severity   = "ERROR"
                    message    = "Failed to load board database: $($_.Exception.Message)"
                    suggestion = "Ensure database/boards.json exists and is valid JSON"
                })
                warnings = @()
                summary  = "Database load failed"
            } | ConvertTo-Json -Depth 10)
        }
    } else {
        $warnings.Add(@{
            line       = 0
            token      = "boards.json"
            code       = "DATABASE_NOT_FOUND"
            severity   = "WARNING"
            message    = "Board database not found at database/boards.json — board pin validation skipped"
            suggestion = "Add database/boards.json for full validation"
        })
    }

    # --- Parse ---
    $parsed = Parse-AEL -aelText $aelText -componentLibrary $AEL_COMPONENT_LIBRARY

    # Carry parse-time errors
    foreach ($e in $parsed.errors) { $errors.Add($e) }

    # --- Check: at least one BOARD declared ---
    if ($parsed.boards.Count -eq 0) {
        $warnings.Add(@{
            line       = 1
            token      = "BOARD"
            code       = "NO_BOARD_DECLARED"
            severity   = "WARNING"
            message    = "No BOARD declaration found"
            suggestion = "Add: BOARD esp32c3_supermini AS esp"
        })
    }

    # --- Track pin usage for PIN_ALREADY_ASSIGNED ---
    $pinUsage = @{}   # pinRef -> lineNum

    function Check-PinUsage {
        param([string]$pinRef, [int]$lineNum)
        if ($pinUsage.ContainsKey($pinRef)) {
            $warnings.Add(@{
                line       = $lineNum
                token      = $pinRef
                code       = "PIN_ALREADY_ASSIGNED"
                severity   = "WARNING"
                message    = "Pin '$pinRef' is already used at line $($pinUsage[$pinRef])"
                suggestion = "Choose a different pin or if sharing a pin is intentional (e.g. GND), use NET instead e.g: NET GND esp.GND regulator.GND battery.N"
            })
        } else {
            $pinUsage[$pinRef] = $lineNum
        }
    }

    # --- Validate WIREs ---
    foreach ($w in $parsed.wires) {
        $srcInfo = Resolve-Pin -pinRef $w.src -parsed $parsed -boardData $boardData
        $dstInfo = Resolve-Pin -pinRef $w.dst -parsed $parsed -boardData $boardData

        if (-not $srcInfo.ok) {
            $errors.Add(@{ line=$w.line; token=$w.src; code="UNKNOWN_PIN"; severity="ERROR"
                message=$srcInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }
        if (-not $dstInfo.ok) {
            $errors.Add(@{ line=$w.line; token=$w.dst; code="UNKNOWN_PIN"; severity="ERROR"
                message=$dstInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }

        Check-PinUsage $w.src $w.line
        Check-PinUsage $w.dst $w.line

        $srcType = $srcInfo.type
        $dstType = $dstInfo.type

        # GROUND as destination is always valid for WIRE from passives
        if ($dstType -eq "GROUND") {
            if ($srcType -notin @("PASSIVE","IO","OUTPUT")) {
                $errors.Add(@{
                    line       = $w.line
                    token      = "$($w.src) -> $($w.dst)"
                    code       = "INVALID_SIGNAL_DIRECTION"
                    severity   = "ERROR"
                    message    = "Cannot connect $srcType pin '$($w.src)' to GROUND via WIRE"
                    suggestion = "Use POWER keyword for power rail connections e.g: POWER $($w.src) -> $($w.dst)"
                })
            }
            continue
        }

        $allowed = $AEL_WIRE_RULES[$srcType]
        if (-not $allowed -or -not $allowed.ContainsKey($dstType)) {
            $errors.Add(@{
                line       = $w.line
                token      = "$($w.src) -> $($w.dst)"
                code       = "INVALID_SIGNAL_DIRECTION"
                severity   = "ERROR"
                message    = "$srcType pin '$($w.src)' cannot drive $dstType pin '$($w.dst)'"
                suggestion = "Reverse the connection or check pin types"
            })
        }
    }

    # --- Validate POWERs ---
    foreach ($p in $parsed.powers) {
        $srcInfo = Resolve-Pin -pinRef $p.src -parsed $parsed -boardData $boardData
        $dstInfo = Resolve-Pin -pinRef $p.dst -parsed $parsed -boardData $boardData

        if (-not $srcInfo.ok) {
            $errors.Add(@{ line=$p.line; token=$p.src; code="UNKNOWN_PIN"; severity="ERROR"
                message=$srcInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }
        if (-not $dstInfo.ok) {
            $errors.Add(@{ line=$p.line; token=$p.dst; code="UNKNOWN_PIN"; severity="ERROR"
                message=$dstInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }

        Check-PinUsage $p.src $p.line
        Check-PinUsage $p.dst $p.line

        $srcType = $srcInfo.type
        $dstType = $dstInfo.type

        $allowed = $AEL_POWER_RULES[$srcType]
        if (-not $allowed -or -not $allowed.ContainsKey($dstType)) {
            $errors.Add(@{
                line       = $p.line
                token      = "$($p.src) -> $($p.dst)"
                code       = "PIN_TYPE_MISMATCH"
                severity   = "ERROR"
                message    = "POWER connection invalid: $srcType -> $dstType"
                suggestion = "POWER source must be POWER_OUT, destination must be POWER_IN or GROUND"
            })
            continue
        }

        # Voltage check — only if source has a known voltage
        if ($srcInfo.voltage -and $dstInfo -and -not $dstInfo.isBoardPin) {
            $compId   = $dstInfo.owner
            $comp     = $parsed.components[$compId]
            if ($comp -and $comp.vcc_range) {
                $vMin = $comp.vcc_range[0]
                $vMax = $comp.vcc_range[1]
                $srcV = $srcInfo.voltage
                if ($srcV -lt $vMin -or $srcV -gt $vMax) {
                    $errors.Add(@{
                        line       = $p.line
                        token      = $p.src
                        code       = "VOLTAGE_MISMATCH"
                        severity   = "ERROR"
                        message    = "$compId ($($comp.type)) expects ${vMin}-${vMax}V but '$($p.src)' provides ${srcV}V"
                        suggestion = "Use a $vMin-$vMax V power pin instead of '$($p.src)'"
                    })
                }
            }
        }
    }

    # --- Validate BUSes ---
    foreach ($b in $parsed.buses) {
        $srcInfo = Resolve-Pin -pinRef $b.src -parsed $parsed -boardData $boardData
        $dstInfo = Resolve-Pin -pinRef $b.dst -parsed $parsed -boardData $boardData

        if (-not $srcInfo.ok) {
            $errors.Add(@{ line=$b.line; token=$b.src; code="UNKNOWN_PIN"; severity="ERROR"
                message=$srcInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }
        if (-not $dstInfo.ok) {
            $errors.Add(@{ line=$b.line; token=$b.dst; code="UNKNOWN_PIN"; severity="ERROR"
                message=$dstInfo.error; suggestion="Check spelling and BOARD/COMP declarations" })
            continue
        }

        Check-PinUsage $b.src $b.line

        $srcType = $srcInfo.type
        $dstType = $dstInfo.type

        $allowed = $AEL_BUS_RULES[$srcType]
        if (-not $allowed -or -not $allowed.ContainsKey($dstType)) {
            $errors.Add(@{
                line       = $b.line
                token      = "$($b.src) -> $($b.dst)"
                code       = "UNSUPPORTED_BUS"
                severity   = "ERROR"
                message    = "BUS connection invalid: $srcType -> $dstType. BUS requires bidirectional pin types (IO, UART_TX/RX, I2C_SDA/SCL)"
                suggestion = "Use WIRE for unidirectional signals. BUS is for I2C, SPI, UART"
            })
        }
    }

    # --- Validate NETs ---
    foreach ($netName in $parsed.nets.Keys) {
        $netPins = $parsed.nets[$netName]
        if ($netPins.Count -lt 2) {
            $warnings.Add(@{
                line       = 0
                token      = "NET $netName"
                code       = "FLOATING_NET"
                severity   = "WARNING"
                message    = "NET '$netName' has only $($netPins.Count) member(s) — a net needs at least 2 pins to be meaningful"
                suggestion = "Add more pins to NET $netName or remove if unused"
            })
        }
        foreach ($pinRef in $netPins) {
            $info = Resolve-Pin -pinRef $pinRef -parsed $parsed -boardData $boardData
            if (-not $info.ok) {
                $errors.Add(@{
                    line       = 0
                    token      = $pinRef
                    code       = "UNKNOWN_PIN"
                    severity   = "ERROR"
                    message    = "NET '$netName' references unknown pin: $($info.error)"
                    suggestion = "Check spelling and BOARD/COMP declarations"
                })
            }
        }
    }

    # --- Build result ---
    $allErrors   = @($errors)
    $allWarnings = @($warnings)
    $valid       = ($allErrors.Count -eq 0)

    $summary = if ($valid -and $allWarnings.Count -eq 0) {
        "Circuit is valid. No errors or warnings."
    } elseif ($valid) {
        "Circuit is valid with $($allWarnings.Count) warning(s)."
    } else {
        "$($allErrors.Count) error(s), $($allWarnings.Count) warning(s) found."
    }

    $result = @{
        valid    = $valid
        errors   = $allErrors
        warnings = $allWarnings
        summary  = $summary
    }

    return ($result | ConvertTo-Json -Depth 10)
}

# ====================== CONSOLE RENDERER ======================

function Render-ValidationResult {
    param([string]$jsonResult)

    $r = $jsonResult | ConvertFrom-Json

    if ($r.valid -and $r.warnings.Count -eq 0) {
        Draw-Box @("$CHK  $($r.summary)") -Color Green
        return
    }

    if ($r.valid) {
        Draw-Box @("$CHK  $($r.summary)") -Color Yellow
    } else {
        Draw-Box @("$CRS  $($r.summary)") -Color Red
    }

    Write-Host ""

    foreach ($e in $r.errors) {
        Write-Host "  [$($e.severity)] Line $($e.line) [$($e.code)]" -ForegroundColor Red
        Write-Host "    $($e.message)" -ForegroundColor White
        if ($e.suggestion) {
            Write-Host "    $ARR $($e.suggestion)" -ForegroundColor DarkYellow
        }
        Write-Host "    Token: $($e.token)" -ForegroundColor DarkGray
        Write-Host ""
    }

    foreach ($w in $r.warnings) {
        Write-Host "  [WARNING] $($w.code)" -ForegroundColor Yellow
        Write-Host "    $($w.message)" -ForegroundColor White
        if ($w.suggestion) {
            Write-Host "    $ARR $($w.suggestion)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

# ====================== TOOL REGISTRATION ======================

$ToolMeta = @{
    Name        = "ael_validate"
    Behavior    = "Validates AEL (ASCII Electronics Language) v0.3 circuit definitions. Parses BOARD, COMP, WIRE, POWER, BUS, and NET statements and returns structured JSON errors for self-correction. Board-agnostic — use with any board in the database."
    Description = "Parses and validates an AEL circuit string. Returns JSON with errors and warnings including line numbers, error codes, and fix suggestions."
    Parameters  = @{
        ael = "string - the full AEL circuit text to validate"
    }
    Example     = @"
<tool_call>{ "name": "ael_validate", "parameters": { "ael": "BOARD esp32c3_supermini AS esp\nCOMP led1 LED\nCOMP r1 RES value=220R\nWIRE esp.GPIO2 -> led1.A\nWIRE led1.C -> r1.A\nWIRE r1.B -> esp.GND" } }</tool_call>
"@
    FormatLabel = { param($p)
        $lines = ($p.ael -split "`n").Count
        "AEL Validate  $ARR  $lines line(s)"
    }
    Execute     = {
        param($params)
        if ([string]::IsNullOrWhiteSpace($params.ael)) {
            return '{"valid":false,"errors":[{"line":0,"token":"ael","code":"EMPTY_INPUT","severity":"ERROR","message":"No AEL text provided","suggestion":"Provide a complete AEL circuit definition"}],"warnings":[],"summary":"Empty input."}'
        }
        $json = Invoke-AELValidate -aelText $params.ael -scriptDir $scriptDir

        # Render validation result to console
        try { Render-ValidationResult -jsonResult $json } catch {}

        # Auto-render diagram if circuit is valid
        $parsed = $json | ConvertFrom-Json
        if ($parsed.valid) {
            try {
                # Load renderer from sibling tool file
                $renderFile = Join-Path $scriptDir "tools/ael_render.ps1"
                if (Test-Path $renderFile) {
                    $renderContent = Get-Content $renderFile -Raw -Encoding UTF8
                    Invoke-Expression $renderContent
                    Write-Host ""
                    Invoke-AELRender -aelText $params.ael | Out-Null
                }
            } catch {
                # Renderer unavailable — validation result still returned cleanly
            }
        }

        return "CONSOLE::AEL Validation complete::END_CONSOLE::$json"
    }
    ToolUseGuidanceMajor = @"
- When to use 'ael_validate': After generating any AEL circuit. Always validate before presenting a circuit to the user.
- Input: the raw AEL text block.
- Output: JSON with 'valid' (bool), 'errors' (array), 'warnings' (array), 'summary' (string).
- Each error has: line, token, code, severity, message, suggestion.
- Self-correction: If errors are returned, fix the circuit using the 'suggestion' field and call ael_validate again. Max 3 attempts.
- Error codes: UNKNOWN_PIN, UNKNOWN_COMPONENT, INVALID_SIGNAL_DIRECTION, VOLTAGE_MISMATCH, PIN_ALREADY_ASSIGNED, UNSUPPORTED_BUS, FLOATING_NET, PIN_TYPE_MISMATCH, UNKNOWN_STATEMENT, NO_BOARD_DECLARED.
"@
    ToolUseGuidanceMinor = @"
- Purpose: Validate AEL circuit syntax and electrical rules.
- Always validate AEL before showing it to the user.
- Use 'suggestion' field to self-correct errors.
"@
}