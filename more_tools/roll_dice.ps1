# ===============================================
# GemmaCLI Tool - roll_dice.ps1 v0.2.0
# Responsibility: Parses and rolls dice expressions with visual ASCII feedback.
# ===============================================

function Get-DiceArt {
    param([int]$sides, [int]$value)

    # Pad value for consistent centering (handles up to 99)
    $v = $value.ToString()
    if ($value -lt 10) { $v = " $v" }
    elseif ($value -gt 99) { $v = "++" }

    switch ($sides) {
        4 {
            return @(
                "    .    ",
                "   / \   ",
                "  /$v \  ",
                " /_____\ "
            )
        }
        6 {
            return @(
                "┌-------┐",
                "|       |",
                "|  $v   |",
                "|       |",
                "└-------┘"
            )
        }

        8 {
            return @(
                "   / \   ",
                "  /$v \  ",
                " /_____\ ",
                " \     / ",
                "  \   /  ",
                "   \ /   "
            )
        }
        10 {
            return @(
                "    .    ",
                "   / \   ",
                "  /$v \  ",
                " /_____\ ",
                " \     / ",
                "  \___/  "
            )
        }
        12 {
            return @(
                "  .───.  ",
                " /     \ ",
                "/   $v  \",
                "\       /",
                " \     / ",
                "  '───'  "
            )
        }
        20 {
            return @(
                " ⟋  | ⟍ ",
                "⌜ˉˉ/\ˉˉ⌝",
                "│ /$v\ │",
                "│/____\│",
                " ⟍\ ˍ/⟋ "
            )
        }

        default {
            return @(
                "┌────┐",
                "│ d$($sides.ToString().PadRight(2))│",
                "│$v  │",
                "└────┘"
            )
        }
    }
}

function Invoke-RollTool {
    param([string]$expression)

    $expression = $expression.Trim().ToLower() -replace '\s', ''
    if ([string]::IsNullOrWhiteSpace($expression)) {
        return "ERROR: No dice expression provided. Example: 2d6, 1d20+5"
    }

    if ($expression -notmatch '^(\d*)d(\d+)([+-]\d+)?$') {
        return "ERROR: Invalid dice expression '$expression'."
    }

    $count     = if ($matches[1] -eq "") { 1 } else { [int]$matches[1] }
    $sides     = [int]$matches[2]
    $modifier  = if ($matches[3]) { [int]$matches[3] } else { 0 }

    if ($count -lt 1 -or $count -gt 100) { return "ERROR: Dice count must be 1-100." }
    if ($sides -lt 2 -or $sides -gt 10000) { return "ERROR: Dice sides must be 2-10000." }

    # --- Roll ---
    $rolls = @()
    for ($i = 0; $i -lt $count; $i++) {
        $rolls += Get-Random -Minimum 1 -Maximum ($sides + 1)
    }

    $rawTotal = ($rolls | Measure-Object -Sum).Sum
    $total    = $rawTotal + $modifier

    # --- Build ASCII Art ---
    $maxArt = [Math]::Min($count, 8) # Show up to 8 dice visually
    $allDiceArt = @()
    for ($i = 0; $i -lt $maxArt; $i++) {
        $allDiceArt += ,(Get-DiceArt -sides $sides -value $rolls[$i])
    }

    $height = $allDiceArt[0].Count
    $combinedArtLines = @()
    for ($row = 0; $row -lt $height; $row++) {
        $line = " "
        for ($d = 0; $d -lt $allDiceArt.Count; $d++) {
            $line += $allDiceArt[$d][$row] + "  "
        }
        $combinedArtLines += $line
    }

    $asciiOutput = $combinedArtLines -join "`n"
    if ($count -gt 8) { $asciiOutput += "`n ... (and $($count - 8) more dice)" }

    # --- Result String ---
    $rollsDisplay = $rolls -join ", "
    $modDisplay   = if ($modifier -gt 0) { " + $modifier" }
                    elseif ($modifier -lt 0) { " - $([Math]::Abs($modifier))" }
                    else { "" }

    $breakdown = if ($count -gt 1) { "Rolls: [$rollsDisplay] = $rawTotal$modDisplay" }
                 else              { "Roll: $rollsDisplay$modDisplay" }

    $isCrit     = ($sides -eq 20 -and $count -eq 1 -and $rolls[0] -eq 20)
    $isCritFail = ($sides -eq 20 -and $count -eq 1 -and $rolls[0] -eq 1)
    $flavour = ""
    if ($isCrit)     { $flavour = " NATURAL 20 - CRITICAL HIT!" }
    elseif ($isCritFail) { $flavour = " NATURAL 1 - CRITICAL FAIL!" }

    $finalText = "🎲 $($expression.ToUpper())$modDisplay | $breakdown | Total: $total$flavour"

    return "CONSOLE::$asciiOutput`n$finalText::END_CONSOLE::$finalText"
}

# --- Registration ---
$ToolMeta = @{
    Name        = "roll_dice"
    RendersToConsole = $false
    Category    = @("Gaming/Entertainment")
    Behavior    = "Rolls dice using standard RPG notation (e.g. 2d6, 1d20+5). Returns visual ASCII dice and a full breakdown."
    Description = "Evaluates dice expressions. Returns rolls, visual art, total, and crit flags."
    Parameters  = @{ expression = "string - e.g. '2d6', '1d20+5', 'd8'" }
    Example     = "<tool_call>{ ""name"": ""roll_dice"", ""parameters"": { ""expression"": ""1d20+5"" } }</tool_call>"
    FormatLabel = { param($p) "🎲 RollDice -> $($p.expression)" }
    Execute     = { param($params) Invoke-RollTool -expression $params.expression }
    ToolUseGuidanceMajor = @"
        - When to use 'roll_dice': Any time a random dice-based result is needed.
        - Interaction: The tool returns visual ASCII art for the user and text for you.
        - Natural 20s and 1s are highlighted. Narrate results dramatically!
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Roll dice with visual feedback.
        - Provide 'expression' like '2d6' or '1d20'.
"@
}
