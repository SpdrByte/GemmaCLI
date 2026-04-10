# tools/insulin_calc.ps1 v1.1.0
# Responsibility: High-accuracy insulin dose calculator for diabetics.
#                 Uses a verified nutritional database and requires double-entry
#                 for high-risk parameters. Triggers audio warnings.

function Invoke-InsulinCalcTool {
    param(
        [string]$food_item,
        [double]$amount = 1,
        [double]$carbs_manual_1 = 0,
        [double]$carbs_manual_2 = 0,
        [double]$icr = 0           # Removed default for safety
    )

    $esc = [char]27
    $reset = "$esc[0m"

    # ── Safety Check: ICR is Mandatory ───────────────────────────────────────
    if ($icr -le 0) {
        return "ERROR: Insulin-to-Carb Ratio (ICR) is missing or invalid. You MUST ask the user for their personalized ICR (e.g., 1 unit per 10g) before calculating a dose."
    }
    
    # ── Double Verification Check (Only if manual carbs provided) ────────────
    if ($carbs_manual_1 -gt 0 -and ($carbs_manual_1 -ne $carbs_manual_2)) {
        return "CONSOLE::PLAY_SOUND:Windows Critical Stop::END_CONSOLE::ERROR: Carb count mismatch ($carbs_manual_1 vs $carbs_manual_2). For safety, calculations have been aborted. Please re-enter the values carefully."
    }

    $dbPath = Join-Path $script:scriptDir "database\nutrition.json"
    $verifiedCarbs = $null
    $source = "Manual Entry"

    # ── Verified Source Lookup ───────────────────────────────────────────────
    if ($food_item -and (Test-Path $dbPath)) {
        Write-Host "  $esc[2mSearching database for '$food_item'...$reset"
        $db = Get-Content $dbPath -Raw | ConvertFrom-Json
        $inputClean = $food_item.ToLower().Replace("'","").Replace(" ","_")
        $inputTokens = $food_item.ToLower().Split(" '", [System.StringSplitOptions]::RemoveEmptyEntries)
        
        $entry = $null
        $key = ""
        $bestMatchScore = 0

        foreach ($prop in $db.PSObject.Properties) {
            $dbKey = $prop.Name.ToLower()
            
            # Exact Match
            if ($inputClean -eq $dbKey) {
                $entry = $prop.Value
                $key = $prop.Name
                break
            }

            # Token Overlap Score
            $tokenMatches = 0
            foreach ($t in $inputTokens) {
                $pattern = [regex]::Escape($t)
                if ($dbKey -match $pattern) { $tokenMatches++ }
            }
            
            if ($tokenMatches -gt $bestMatchScore) {
                $bestMatchScore = $tokenMatches
                $entry = $prop.Value
                $key = $prop.Name
            }
        }

        # Stricter requirement: must have at least one token match or part-match
        if ($bestMatchScore -eq 0 -and $inputClean -notmatch $key) {
            $entry = $null
        }

        if ($entry) {
            if ($entry.carbs_per_100g) {
                $verifiedCarbs = [math]::Round(($entry.carbs_per_100g * $amount / 100), 1)
            } elseif ($entry.carbs_per_item) {
                $verifiedCarbs = [math]::Round(($entry.carbs_per_item * $amount), 1)
            }
            $source = "VERIFIED DATABASE ($key)"
        }
    }

    # If database lookup fails and no manual carbs, error out
    if ($null -eq $verifiedCarbs -and $carbs_manual_1 -eq 0) {
        $warningSound = "PLAY_SOUND:Windows Hardware Fail"
        return "CONSOLE::$warningSound::END_CONSOLE::ERROR: Could not find '$food_item' in database and no manual carb count provided. Please provide a carb estimate or choose a common item (Apple, Pizza, Big Mac, etc.)."
    }

    $finalCarbs = if ($null -ne $verifiedCarbs) { $verifiedCarbs } else { $carbs_manual_1 }
    $warningSound = ""

    if ($null -eq $verifiedCarbs) {
        $warningSound = "PLAY_SOUND:Windows Hardware Fail"
        $source = "UNVERIFIED (User Provided)"
    }

    # ── Calculation ──────────────────────────────────────────────────────────
    $dose = [math]::Round(($finalCarbs / $icr), 1)

    # ── High Dose Warning (> 10 units)
    if ($dose -ge 10.0) {
        $warningSound = "PLAY_SOUND:Windows Battery Critical"
    }

    # ── Visual Output ────────────────────────────────────────────────────────
    $lines = @(
        "DIABETIC CALCULATION SUMMARY",
        "----------------------------",
        "Food Item:  $(if ($food_item) { $food_item } else { 'N/A' })",
        "Amount:     $amount",
        "Carbs:      $finalCarbs g ($source)",
        "ICR Ratio:  1:$icr",
        "",
        "ESTIMATED DOSE: $dose UNITS"
    )
    
    $boxColor = if ($dose -ge 10.0) { "Red" } else { "Green" }
    Draw-Box -Lines $lines -Title "Medical Calculation" -Color $boxColor

    $disclaimer = "$esc[2mDISCLAIMER: This tool is a calculation aid only. Always verify results against your glucose monitor and doctor's instructions.$reset"
    Write-Host "`n  $disclaimer"

    return "CONSOLE::$warningSound::END_CONSOLE::OK: Calculated $dose units of insulin for $finalCarbs grams of carbs ($source)."
}

# ── Self-registration ────────────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "insulin_calc"
    Icon             = "💉"
    RendersToConsole = $true
    Category         = @("Health", "Utility")
    Behavior         = "Calculate insulin doses for food. MANDATORY: You MUST ask the user for their personalized Insulin-to-Carb Ratio (ICR) before using this tool. Never assume a default ratio. 1. If you know the food name, provide 'food_item' and 'amount' - the tool will look up verified counts. 2. If the food is not common or you have a specific count from a label, provide 'carbs_manual_1' and 'carbs_manual_2' (MUST MATCH). Do NOT hallucinate carb counts; if you don't know the food and the user didn't provide a count, ask for clarification instead of guessing."
    Description      = "Calculates insulin dose with database lookup and safety verification. Requires matching double-entry if manual carbs are provided and mandatory user-verified ICR."
    Parameters       = @{
        food_item      = "string - optional. Name of food to lookup (Apple, Banana, Pizza, Big Mac, etc.)."
        amount         = "number - optional. Quantity of food. Default: 1."
        carbs_manual_1 = "number - optional. Carb count from label (Entry 1)."
        carbs_manual_2 = "number - optional. Carb count from label (Entry 2 - must match Entry 1)."
        icr            = "number - REQUIRED. Personalized Insulin-to-Carb Ratio (e.g. 10 for 1 unit per 10g carbs). You MUST verify this with the user."
    }
    Example          = "<tool_call>{ ""name"": ""insulin_calc"", ""parameters"": { ""food_item"": ""pepperoni pizza"", ""amount"": 2 } }</tool_call>"
    FormatLabel      = { param($p)
        if ($p.carbs_manual_1 -gt 0) { "$($p.carbs_manual_1)g carbs (Manual)" }
        else { "lookup '$($p.food_item)' ($($p.amount))" }
    }
    Execute          = { param($params) Invoke-InsulinCalcTool @params }
}
