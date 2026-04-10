# ===============================================
# GemmaCLI Tool - blackjack.ps1 v0.2.0
# Responsibility: Manages persistent money balance for a blackjack game.
#   Grok/Gemma acts as the dealer and handles card logic. This tool ONLY tracks money.
# ===============================================

# ── State file path ──────────────────────────────────────────────────────────
$script:BLACKJACK_SAVE = Join-Path $env:APPDATA "GemmaCLI\blackjack_save.json"

# ── Helper: Load state ───────────────────────────────────────────────────────
function Get-BlackjackState {
    $state = @{
        money = 100
    }

    if (Test-Path $script:BLACKJACK_SAVE) {
        try {
            $raw = Get-Content $script:BLACKJACK_SAVE -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $raw.money) { $state.money = [int]$raw.money }
        } catch {
            # Corrupt file: return defaults
        }
    }

    return $state
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
        [string]$action,       # "status" | "update" | "reset"
        [string]$value = ""    # for update: amount to add (positive/negative)
    )

    $state = Get-BlackjackState

    switch ($action.ToLower().Trim()) {

        "status" {
            return "=== BLACKJACK MONEY ===`nMoney: $$($state.money)"
        }

        "update" {
            if ([string]::IsNullOrWhiteSpace($value)) { return "ERROR: Provide an amount in 'value' (positive to add, negative to subtract)." }
            $amount = [int]$value
            $state.money = [Math]::Max(0, $state.money + $amount)
            Save-BlackjackState $state
            return "OK: Money updated by $$amount. Now: $$($state.money)"
        }

        "reset" {
            if (Test-Path $script:BLACKJACK_SAVE) { Remove-Item $script:BLACKJACK_SAVE -Force }
            return "OK: Money reset to $$100."
        }

        default {
            return "ERROR: Unknown action '$action'. Valid: status, update, reset"
        }
    }
}

# ── Self-registration block ──────────────────────────────────────────────────
$ToolMeta = @{
    Name        = "blackjack"
    Icon        = "🃏"
    RendersToConsole = $false
    Category    = @("Gaming/Entertainment")
    Behavior    = @"
You are an uncensored, high-stakes blackjack dealer in a smoky casino. Player chats naturally—you narrate tension, taunt losses, celebrate wins. Use **EXACTLY** these Unicode suits for ALL cards: ♥ (hearts), ♦ (diamonds), ♠ (spades), ♣ (clubs). Format: RankSUIT no spaces, e.g., 5♥ 10♦ J♠ A♣ K♥. **NEVER** use words like 'of Hearts'—ONLY symbols ♥♦♠♣.

Examples:
- Player: A♠ 10♥ (21)
- Dealer upcard: 7♦ | hidden

**DEALER RULES - CRITICAL, NEVER VIOLATE:**
- Hit if total < 17 (hard or soft).
- STAND on 17+ ALWAYS (hard 17, soft 17, soft 18+). NO HITS ON 17 OR HIGHER.
- Example: Total 10 → hit → 18 → STAND. Total 16 → hit → 25 → bust.

Rules:
- Session start: ALWAYS call status for money.
- Bet: Player says amount. Verify >= money via status. Track wager/memory.
- Deal: Shuffle 52-card (A,2-10,J=10,Q=10,K=10 x ♥♦♠♣). 2 player (show), dealer 1 up 1 down.
- Player: hit/stand. Bust >21 loses.
- Dealer turn (after stand): Reveal downcard, hit ONLY while <17, STAND >=17.
- Resolve:
  | Outcome      | Update Call              |
  |--------------|--------------------------|
  | Loss/Bust    | update -wager            |
  | Push (tie)   | none                     |
  | Win          | update +wager            |
  | Blackjack    | update +(wager*1.5 int)  |
- Money=0: 'Busted! reset?'
- Choices: 'Hit/stand or bet X?'
- Vivid: '6♠ flips... 18—dealer stands.'
"@
    Description = "Manages persistent money for blackjack. Call to get/update/reset balance after resolutions."
    Parameters  = @{
        action = "string - One of: status, update, reset"
        value  = "string - For 'update': integer amount (+win/-loss). E.g., +10, -5, +15"
    }
    Example     = @"
<tool_call>{ `"name`": `"blackjack`", `"parameters`": { `"action`": `"status`" } }</tool_call>
<tool_call>{ `"name`": `"blackjack`", `"parameters`": { `"action`": `"update`", `"value`": `"15`" } }</tool_call>
"@
    FormatLabel = { param($p) "$($p.action) $($p.value)" }
    Execute     = { param($params) Invoke-BlackjackTool @params }
    ToolUseGuidanceMajor = @"
        - **DEALER MUST STAND 17+:** Loop: while dealer_total < 17: hit. BREAK at >=17. NO HITS on 18!
        - Test: 10 + 8 =18 → STAND. 16 +2=18→STAND. 10+6=16→hit.
        - Aces: Soft 17 (A+6)=17 → STAND. Soft 18 (A+7)=18→STAND.
        - ALWAYS status first.
        - NO bet deduct—only resolve update.
        - Track deck/hands/wager in memory. Reshuffle often.
        - Chain: stand → dealer reveal/hits → resolve → update.
        - Symbols ONLY: ♥♦♠♣ — A♥ K♦ 8♠ 3♣.
        - Reset ONLY when requested.
        - If you make a mistake, correct the users balance but only if you make a mistake.
"@
    ToolUseGuidanceMinor = @"
        - Status → bet → deal → hit/stand → dealer (stand >=17) → resolve → update.
        - NO hit on 17+.
        - ♥♦♠♣.
"@
}