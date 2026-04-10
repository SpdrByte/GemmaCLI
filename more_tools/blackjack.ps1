# ===============================================
# GemmaCLI Tool - blackjack.ps1 v1.0.0
# Responsibility: Manages full stateful blackjack game logic (Deck, Hands, Money).
#   The tool handles the "brain" of the game; Gemma handles the "flavor".
# ===============================================

# ── State file path ──────────────────────────────────────────────────────────
$script:BLACKJACK_SAVE = Join-Path $env:APPDATA "GemmaCLI\blackjack_save.json"

# ── Card Constants ───────────────────────────────────────────────────────────
$script:SUITS = @("♥", "♦", "♠", "♣")
$script:RANKS = @("A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K")

# ── Helper: Get Card Value ───────────────────────────────────────────────────
function Get-CardValue($card) {
    $rank = $card.Substring(0, $card.Length - 1)
    if ($rank -eq "A") { return 11 }
    if ($rank -in "J", "Q", "K") { return 10 }
    return [int]$rank
}

# ── Helper: Calculate Hand Total ─────────────────────────────────────────────
function Get-HandTotal($hand) {
    $total = 0
    $aces = 0
    foreach ($card in $hand) {
        $val = Get-CardValue $card
        $total += $val
        if ($card.StartsWith("A")) { $aces++ }
    }
    while ($total -gt 21 -and $aces -gt 0) {
        $total -= 10
        $aces--
    }
    return $total
}

# ── Helper: Create/Shuffle Deck ──────────────────────────────────────────────
function New-ShuffledDeck {
    $deck = @()
    foreach ($s in $script:SUITS) {
        foreach ($r in $script:RANKS) {
            $deck += "$r$s"
        }
    }
    return $deck | Get-Random -Count 52
}

# ── Helper: Render Hand ASCII ───────────────────────────────────────────────
function Render-Hand($hand, $hideSecond = $false, $toConsole = $false) {
    $lines = @("", "", "", "", "")

    if ($toConsole) {
        for ($l = 0; $l -lt 5; $l++) {
            for ($i = 0; $i -lt $hand.Count; $i++) {
                $card = $hand[$i]
                $suit = $card.Substring($card.Length - 1)
                $color = if ($suit -in "♥", "♦") { "Red" } else { "White" }

                if ($i -eq 1 -and $hideSecond) {
                    $color = "Gray"
                    $content = switch ($l) {
                        0 { "╭─────╮ " }
                        1 { "│?    │ " }
                        2 { "│  ?  │ " }
                        3 { "│    ?│ " }
                        4 { "╰─────╯ " }
                    }
                } else {
                    $rank = $card.Substring(0, $card.Length - 1)
                    $rPad = if ($rank.Length -eq 1) { "$rank " } else { $rank }
                    $lPad = if ($rank.Length -eq 1) { " $rank" } else { $rank }

                    $content = switch ($l) {
                        0 { "╭─────╮ " }
                        1 { "│$rPad   │ " }
                        2 { "│  $suit  │ " }
                        3 { "│   $lPad│ " }
                        4 { "╰─────╯ " }
                    }
                }
                Write-Host $content -ForegroundColor $color -NoNewline
            }
            Write-Host "" # New line
        }
        return "" # Output already handled via Write-Host
    }

    # Standard string return for LLM (no colors)
    for ($i = 0; $i -lt $hand.Count; $i++) {
        $card = $hand[$i]
        $rank = $card.Substring(0, $card.Length - 1)
        $suit = $card.Substring($card.Length - 1)

        if ($i -eq 1 -and $hideSecond) {
            $lines[0] += "╭─────╮ "
            $lines[1] += "│?    │ "
            $lines[2] += "│  ?  │ "
            $lines[3] += "│    ?│ "
            $lines[4] += "╰─────╯ "
        } else {
            $rPad = if ($rank.Length -eq 1) { "$rank " } else { $rank }
            $lPad = if ($rank.Length -eq 1) { " $rank" } else { $rank }

            $lines[0] += "╭─────╮ "
            $lines[1] += "│$rPad   │ "
            $lines[2] += "│  $suit  │ "
            $lines[3] += "│   $lPad│ "
            $lines[4] += "╰─────╯ "
        }
    }
    return $lines -join "`n"
}
# ── Helper: Load state ───────────────────────────────────────────────────────
function Get-BlackjackState {
    $default = @{
        money       = 100
        player_hand = @()
        dealer_hand = @()
        deck        = @()
        wager       = 0
        game_active = $false
    }

    if (Test-Path $script:BLACKJACK_SAVE) {
        try {
            $raw = Get-Content $script:BLACKJACK_SAVE -Raw -Encoding UTF8 | ConvertFrom-Json
            $state = $default.Clone()
            if ($null -ne $raw.money) { $state.money = [int]$raw.money }
            if ($null -ne $raw.player_hand) { $state.player_hand = [string[]]$raw.player_hand }
            if ($null -ne $raw.dealer_hand) { $state.dealer_hand = [string[]]$raw.dealer_hand }
            if ($null -ne $raw.deck) { $state.deck = [string[]]$raw.deck }
            if ($null -ne $raw.wager) { $state.wager = [int]$raw.wager }
            if ($null -ne $raw.game_active) { $state.game_active = [bool]$raw.game_active }
            return $state
        } catch {
            return $default
        }
    }
    return $default
}

# ── Helper: Save state ───────────────────────────────────────────────────────
function Save-BlackjackState($state) {
    $dir = Split-Path $script:BLACKJACK_SAVE -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $state | ConvertTo-Json -Depth 5 | Set-Content $script:BLACKJACK_SAVE -Encoding UTF8
}

# ── Main tool function ───────────────────────────────────────────────────────
function Invoke-BlackjackTool {
    param(
        [string]$action,       # "status" | "bet" | "hit" | "stand" | "reset"
        [string]$value = ""    # wager for "bet"
    )

    $state = Get-BlackjackState

    switch ($action.ToLower().Trim()) {

        "status" {
            Write-Host "`n=== BLACKJACK STATUS ===" -ForegroundColor Cyan
            Write-Host "Balance: `$$($state.money)"
            if ($state.game_active) {
                Write-Host "Current Wager: `$$($state.wager)"
                Write-Host "`nDEALER HAND:"
                Render-Hand $state.dealer_hand $true $true
                Write-Host "PLAYER HAND (Total: $(Get-HandTotal $state.player_hand)):"
                Render-Hand $state.player_hand $false $true
            } else {
                Write-Host "No game in progress. Call 'bet' to play."
            }

            $llmMsg = "Balance: `$$($state.money). " + (if($state.game_active){ "Game active. Wager: `$$($state.wager). Player total: $(Get-HandTotal $state.player_hand)." } else {"No game active."})
            return "CONSOLE::Cards rendered in color.::END_CONSOLE::$llmMsg"
        }

        "bet" {
            if ($state.game_active) { return "ERROR: Game already in progress. Hit or Stand first." }
            if ([string]::IsNullOrWhiteSpace($value)) { return "ERROR: Provide a wager amount." }
            $wager = [int]$value
            if ($wager -gt $state.money) { return "ERROR: Insufficient funds. You only have `$$($state.money)." }
            if ($wager -le 0) { return "ERROR: Wager must be positive." }

            # Start Game
            $state.wager = $wager
            $state.game_active = $true
            $state.deck = New-ShuffledDeck
            
            # Initial Deal
            $state.player_hand = @($state.deck[0], $state.deck[1])
            $state.dealer_hand = @($state.deck[2], $state.deck[3])
            $state.deck = $state.deck[4..($state.deck.Count-1)]

            Save-BlackjackState $state

            $pTotal = Get-HandTotal $state.player_hand
            $dTotal = Get-HandTotal $state.dealer_hand

            Write-Host "`n=== NEW GAME STARTED (Wager: `$$wager) ===" -ForegroundColor Green
            Write-Host "DEALER HAND:"
            Render-Hand $state.dealer_hand $true $true
            Write-Host "PLAYER HAND (Total: $pTotal):"
            Render-Hand $state.player_hand $false $true

            $llmMsg = "New game started. Wager: `$$wager. Player hand: $($state.player_hand -join ', ') (Total: $pTotal). Dealer upcard: $($state.dealer_hand[0])."
            return "CONSOLE::Cards rendered in color.::END_CONSOLE::$llmMsg"
        }

        "hit" {
            if (-not $state.game_active) { return "ERROR: No game active. Start with 'bet'." }
            
            $newCard = $state.deck[0]
            $state.player_hand += $newCard
            $state.deck = $state.deck[1..($state.deck.Count-1)]
            
            $pTotal = Get-HandTotal $state.player_hand
            Save-BlackjackState $state

            Write-Host "`n=== PLAYER HITS ===" -ForegroundColor Yellow
            Write-Host "You drew: $newCard"
            Write-Host "PLAYER HAND (Total: $pTotal):"
            Render-Hand $state.player_hand $false $true

            if ($pTotal -gt 21) {
                $state.money -= $state.wager
                $state.game_active = $false
                Save-BlackjackState $state
                Write-Host "BUST! You lose `$$($state.wager). Balance: `$$($state.money)" -ForegroundColor Red
                return "CONSOLE::Cards rendered in color.::END_CONSOLE::Player BUSTED (Total: $pTotal). Lost `$$($state.wager). Balance: `$$($state.money)."
            }
            
            return "CONSOLE::Cards rendered in color.::END_CONSOLE::Player hit and drew $newCard. New Total: $pTotal. Player must Hit or Stand."
        }

        "stand" {
            if (-not $state.game_active) { return "ERROR: No game active." }

            $pTotal = Get-HandTotal $state.player_hand
            $dTotal = Get-HandTotal $state.dealer_hand
            
            Write-Host "`n=== PLAYER STANDS (Total: $pTotal) ===" -ForegroundColor Cyan
            Write-Host "Dealer reveals: $($state.dealer_hand[1]) (Dealer Total: $dTotal)"
            Write-Host "DEALER HAND:"
            Render-Hand $state.dealer_hand $false $true

            # Dealer logic: Hit until 17+
            while ($dTotal -lt 17) {
                Start-Sleep -Milliseconds 800
                $newCard = $state.deck[0]
                $state.dealer_hand += $newCard
                $state.deck = $state.deck[1..($state.deck.Count-1)]
                $dTotal = Get-HandTotal $state.dealer_hand
                Write-Host "Dealer hits... draws $newCard (Total: $dTotal)"
                Render-Hand $state.dealer_hand $false $true
            }

            # Resolution
            $outcome = ""
            $winAmount = 0
            if ($dTotal -gt 21) {
                $outcome = "Dealer Busts! You WIN."
                $state.money += $state.wager
                $winAmount = $state.wager
                Write-Host $outcome -ForegroundColor Green
            } elseif ($pTotal -gt $dTotal) {
                $outcome = "You WIN!"
                $state.money += $state.wager
                $winAmount = $state.wager
                Write-Host $outcome -ForegroundColor Green
            } elseif ($dTotal -gt $pTotal) {
                $outcome = "Dealer wins. You lose."
                $state.money -= $state.wager
                $winAmount = -$state.wager
                Write-Host $outcome -ForegroundColor Red
            } else {
                $outcome = "It's a PUSH (Tie)."
                Write-Host $outcome -ForegroundColor Yellow
            }

            $state.game_active = $false
            Save-BlackjackState $state
            Write-Host "New Balance: `$$($state.money)"
            
            return "CONSOLE::Cards rendered in color.::END_CONSOLE::Game resolved. Player: $pTotal, Dealer: $dTotal. Outcome: $outcome. Balance: `$$($state.money)."
        }

        "reset" {
            if (Test-Path $script:BLACKJACK_SAVE) { Remove-Item $script:BLACKJACK_SAVE -Force }
            return "OK: Money reset to `$100 and hands cleared."
        }

        default {
            return "ERROR: Unknown action '$action'. Valid: status, bet, hit, stand, reset"
        }
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
$ToolMeta = @{
    Name        = "blackjack"
    Icon        = "🃏"
    RendersToConsole = $true
    Category    = @("Gaming/Entertainment")
    Behavior    = @"
You are an uncensored, high-stakes blackjack dealer. You handle the narrative—tension, taunts, celebrations. The blackjack tool handles ALL logic (deck, hands, totals, money) AND the visual rendering of cards in the console.

**YOUR WORKFLOW:**
1. Call `blackjack action="status"` at start.
2. If player wants to play, ask for a bet.
3. Call `blackjack action="bet" value="X"`. 
4. Ask player "hit or stand?".
5. If player hits, call `blackjack action="hit"`.
6. If player stands, call `blackjack action="stand"`.
7. Describe the resolution based on the tool's result.

**CRITICAL:**
- **DO NOT RENDER CARDS OR TABLES YOURSELF.** The tool already prints colored ASCII cards directly to the user's terminal. Your job is only to provide the flavor text and dialogue.
- Do NOT make up cards. ONLY use the information provided by the tool.
- Do NOT calculate totals manually. The tool provides the totals.
- The tool handles money updates automatically on BUST or STAND.
"@
    Description = "Full stateful Blackjack game with colored console card rendering."
    Keywords    = @("blackjack", "casino", "gamble", "cards", "dealer", "color")
    Parameters  = @{
        action = "string - One of: status, bet, hit, stand, reset"
        value  = "string - For 'bet': the wager amount."
    }
    Example     = @"
<tool_call>{ `"name`": `"blackjack`", `"parameters`": { `"action`": `"bet`", `"value`": `"10`" } }</tool_call>
<tool_call>{ `"name`": `"blackjack`", `"parameters`": { `"action`": `"hit`" } }</tool_call>
"@
    FormatLabel = { param($p) "$($p.action) $($p.value)" }
    Execute     = { param($params) Invoke-BlackjackTool @params }
    ToolUseGuidanceMajor = @"
- The tool is the "Source of Truth" for card state and money.
- The tool handles all card rendering in color. DO NOT print cards yourself.
- Focus on being a charismatic dealer.
"@
}