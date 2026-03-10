# ===============================================
# GemmaCLI Tool - roll_dice.ps1 v0.1.0
# Responsibility: Parses and rolls any dice expression (e.g. 2d6, 1d20+5, 4d8-2)
#                 Returns a detailed breakdown so Gemma can narrate or react.
# ===============================================

function Invoke-RollTool {
    param(
        [string]$expression
    )

    $expression = $expression.Trim().ToLower() -replace '\s', ''

    if ([string]::IsNullOrWhiteSpace($expression)) {
        return "ERROR: No dice expression provided. Example: 2d6, 1d20+5, 4d8-2"
    }

    # --- Parse expression: supports XdY, XdY+Z, XdY-Z ---
    # Also supports just dY (treated as 1dY)
    if ($expression -notmatch '^(\d*)d(\d+)([+-]\d+)?$') {
        return "ERROR: Invalid dice expression '$expression'. Use format like 2d6, 1d20+5, d8, 3d10-1."
    }

    $countStr  = $matches[1]
    $sidesStr  = $matches[2]
    $modStr    = $matches[3]

    $count     = if ($countStr -eq "" -or $countStr -eq $null) { 1 } else { [int]$countStr }
    $sides     = [int]$sidesStr
    $modifier  = if ($modStr) { [int]$modStr } else { 0 }

    # --- Validation ---
    if ($count -lt 1 -or $count -gt 100) {
        return "ERROR: Dice count must be between 1 and 100. Got: $count"
    }
    if ($sides -lt 2 -or $sides -gt 10000) {
        return "ERROR: Dice sides must be between 2 and 10000. Got: $sides"
    }

    # --- Roll ---
    $rolls = @()
    for ($i = 0; $i -lt $count; $i++) {
        $rolls += Get-Random -Minimum 1 -Maximum ($sides + 1)
    }

    $rawTotal = ($rolls | Measure-Object -Sum).Sum
    $total    = $rawTotal + $modifier

    # --- Build result string ---
    $rollsDisplay = $rolls -join ", "
    $modDisplay   = if ($modifier -gt 0) { " + $modifier" }
                    elseif ($modifier -lt 0) { " - $([Math]::Abs($modifier))" }
                    else { "" }

    $breakdown = if ($count -gt 1) { "Rolls: [$rollsDisplay] = $rawTotal$modDisplay" }
                 else              { "Roll: $rollsDisplay$modDisplay" }

    # --- Flavour context ---
    $isCrit    = ($sides -eq 20 -and $count -eq 1 -and $rolls[0] -eq 20)
    $isCritFail= ($sides -eq 20 -and $count -eq 1 -and $rolls[0] -eq 1)
    $isMax     = ($rolls | Where-Object { $_ -eq $sides }).Count -eq $count
    $isMin     = ($rolls | Where-Object { $_ -eq 1 }).Count -eq $count

    $flavour = ""
    if ($isCrit)     { $flavour = " NATURAL 20 - CRITICAL HIT!" }
    elseif ($isCritFail) { $flavour = " NATURAL 1 - CRITICAL FAIL!" }
    elseif ($isMax)  { $flavour = " Maximum roll!" }
    elseif ($isMin -and $count -gt 1) { $flavour = " All ones... rough." }

    return "🎲 $($expression.ToUpper())$modDisplay | $breakdown | Total: $total$flavour"
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "roll_dice"
    Behavior    = "Rolls dice using standard RPG notation. Use when the user asks to roll dice, make a check, or needs a random number in dice format. Returns a full breakdown so you can narrate or comment on the result."
    Description = "Parses and evaluates a dice expression (e.g. 2d6, 1d20+5, d8, 4d10-2). Returns individual roll values, modifier, total, and flavour flags like critical hits or fumbles."
    Parameters  = @{
        expression = "string - A dice expression in standard notation. Examples: '2d6', '1d20+5', 'd8', '4d10-2', '3d6+3'"
    }
    Example     = "<tool_call>{ ""name"": ""roll_dice"", ""parameters"": { ""expression"": ""1d20+5"" } }</tool_call>"
    FormatLabel = { param($p) "🎲 RollDice -> $($p.expression)" }
    Execute     = {
        param($params)
        Invoke-RollTool -expression $params.expression
    }
    ToolUseGuidanceMajor = @"
        - When to use 'roll_dice': Use any time the user asks to roll dice, make an ability check, attack roll, damage roll, or any random dice-based result. Also use when the user says things like 'roll for it', 'let fate decide', or 'what do I get on a d20'.
        - Parameters for 'roll':
          - 'expression': The dice expression. Infer it from context if not stated explicitly:
            - 'roll a d20' -> '1d20'
            - 'roll with advantage' -> call roll twice with '1d20' and pick the higher
            - 'roll 2d6 damage' -> '2d6'
            - 'roll a perception check' -> '1d20' (or ask if they have a modifier)
        - The tool returns individual dice values, the total, and special flags (critical hit, critical fail, max roll).
        - Use the result to narrate, react dramatically, or continue a roleplay scene. A natural 20 deserves excitement. A natural 1 deserves suffering.
        - Supports up to 100 dice and up to d10000.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Roll dice using standard RPG notation and get a full breakdown.
        - Provide 'expression' like '2d6', '1d20+5', or 'd8'.
        - Returns rolls, modifier, total, and crit/fumble flags for you to react to.
"@
}