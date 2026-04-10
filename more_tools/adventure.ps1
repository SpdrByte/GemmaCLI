# ===============================================
# GemmaCLI Tool - adventure.ps1 v0.4.0
# Responsibility: Manages state for a text adventure / RPG game session.
#   Gemma acts as Dungeon Master. This tool handles the mechanical layer:
#   characters, dice rolls, inventory, HP, combat turns, locations, and save state.
# ===============================================

# ── State file path ──────────────────────────────────────────────────────────
$script:ADVENTURE_SAVE = Join-Path $env:APPDATA "GemmaCLI\adventure_save.json"
$script:ADVENTURE_FLAG = Join-Path $env:APPDATA "GemmaCLI\adventure_welcomed.flag"

# ── Helper: Deep-clone a hashtable from a PSCustomObject ────────────────────
function ConvertFrom-PSObject($obj) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        return @($obj | ForEach-Object { ConvertFrom-PSObject $_ })
    }
    if ($obj -is [PSCustomObject]) {
        $ht = @{}
        $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = ConvertFrom-PSObject $_.Value }
        return $ht
    }
    return $obj
}

# ── Helper: Load state ───────────────────────────────────────────────────────
function Get-AdventureState {
    $state = @{
        characters = @{}   # keyed by name (lowercase). Each entry is a hashtable.
        locations  = @{}   # keyed by name (lowercase).
        log        = @("A new adventure begins...")
        last_log   = 0
        turn       = 0
        combat     = @{
            active     = $false
            round      = 0
            turn_index = 0
            order      = @()   # array of character names in initiative order
        }
    }

    if (-not (Test-Path $script:ADVENTURE_SAVE)) { return $state }

    try {
        $raw = Get-Content $script:ADVENTURE_SAVE -Raw -Encoding UTF8 | ConvertFrom-Json

        if ($null -ne $raw.turn)  { $state.turn = [int]$raw.turn }
        if ($null -ne $raw.log)   { $state.log  = @($raw.log) }

        # Characters
        if ($null -ne $raw.characters) {
            $raw.characters.PSObject.Properties | ForEach-Object {
                $state.characters[$_.Name] = ConvertFrom-PSObject $_.Value
            }
        }

        # Locations
        if ($null -ne $raw.locations) {
            $raw.locations.PSObject.Properties | ForEach-Object {
                $state.locations[$_.Name] = ConvertFrom-PSObject $_.Value
            }
        }

        # Combat block
        if ($null -ne $raw.combat) {
            $c = $raw.combat
            if ($null -ne $c.active)     { $state.combat.active     = [bool]$c.active }
            if ($null -ne $c.round)      { $state.combat.round      = [int]$c.round }
            if ($null -ne $c.turn_index) { $state.combat.turn_index = [int]$c.turn_index }
            if ($null -ne $c.order)      { $state.combat.order      = @($c.order) }
        }
        if ($null -ne $raw.last_log) { $state.last_log = [int]$raw.last_log }

    } catch {
        # Corrupt save — return defaults, next write will heal the file.
    }

    return $state
}

# ── Helper: Save state ───────────────────────────────────────────────────────
function Save-AdventureState($state) {
    $dir = Split-Path $script:ADVENTURE_SAVE -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $state | ConvertTo-Json -Depth 8 | Set-Content $script:ADVENTURE_SAVE -Encoding UTF8
}

# ── Helper: Roll dice ────────────────────────────────────────────────────────
# Returns @{ total = int; rolls = int[]; notation = string; raw_string = string }
function Invoke-DiceRoll([string]$notation) {
    if ($notation -match '^(\d*)d(\d+)$') {
        $numDice = if ($Matches[1]) { [int]$Matches[1] } else { 1 }
        $sides   = [int]$Matches[2]
        $rolls   = @()
        $total   = 0
        for ($i = 0; $i -lt $numDice; $i++) {
            $r = Get-Random -Minimum 1 -Maximum ($sides + 1)
            $rolls += $r
            $total += $r
        }
        return @{
            total      = $total
            rolls      = $rolls
            notation   = $notation
            raw_string = "Rolled $notation → [$($rolls -join ', ')] = $total"
        }
    }
    return $null
}

# ── Helper: Extract die from weapon string e.g. "Shortsword-d6" → "d6" ──────
function Get-WeaponDie([string]$weapon) {
    if ($weapon -match '-(\d*d\d+)$') { return $Matches[1] }
    return "d4"   # fallback for unarmed / unknown
}

# ── Helper: Get character (case-insensitive) ─────────────────────────────────
function Get-Character($state, [string]$name) {
    $key = $name.ToLower().Trim()
    if ($state.characters.ContainsKey($key)) { return $state.characters[$key] }
    return $null
}

# ── Helper: Format a character sheet ─────────────────────────────────────────
function Format-CharacterSheet($c) {
    # Ensure we handle potential hashtables in equipment/consumables gracefully
    $formatItems = {
        param($items)
        if (-not $items -or $items.Count -eq 0) { return "(none)" }
        return ($items | ForEach-Object { 
            if ($_ -is [System.Collections.IDictionary]) { "Object" } else { $_ } 
        }) -join ", "
    }

    $equip = &$formatItems $c.equipment
    $cons  = &$formatItems $c.consumables
    
    $sexStr = if ($c.sex -and $c.sex -ne "unknown") { " ($($c.sex))" } else { "" }
    $extra = if ($c.type -eq "player") { "Gold:        $($c.gold)" } else { "Disposition: $($c.disposition)" }
    $notesStr = if ($c.notes) { "`n  Description: $($c.notes)" } else { "" }

    return @"
  [$($c.type.ToUpper())] $($c.name)$sexStr
  HP:          $($c.hp) / $($c.max_hp)
  AC:          $($c.ac)
  Location:    $($c.location)
  Weapon:      $($c.weapon)
  Armor:       $($c.armor)
  Equipment:   $equip
  Consumables: $cons
  $extra$notesStr
"@
}

function Get-LogNudge($state) {
    $turnsSince = $state.turn - $state.last_log
    if ($turnsSince -gt 10) {
        return "`n→ REMINDER: Nothing has been logged in $turnsSince turns. Summarize recent events with a log call."
    }
    return ""
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN TOOL FUNCTION
# ════════════════════════════════════════════════════════════════════════════
function Invoke-AdventureTool {
    param(
        [string]$action,
        [string]$value = ""
    )

    $state = Get-AdventureState
    $v     = $value.Trim()

    switch ($action.ToLower().Trim()) {

        # ────────────────────────────────────────────────────────────────────
        # STATUS  —  full world snapshot
        # ────────────────────────────────────────────────────────────────────
        "status" {
            $players = @($state.characters.Values | Where-Object { $_.type -eq "player" })

            # Fresh game — show disclaimer once to player (console only) and direct Gemma to create characters
            if ($state.turn -eq 0 -and -not (Test-Path $script:ADVENTURE_FLAG)) {
                New-Item -Path $script:ADVENTURE_FLAG -ItemType File -Force | Out-Null
                $consoleMsg  = "CONSOLE::"
                $consoleMsg += "`n  +-Adventure Tool v.0.2x (in development SpdrByte.com)-----------+"
                $consoleMsg += "`n  |  If Gemma forgets to:                                         |"
                $consoleMsg += "`n  |   - Add/remove an item when you pick up or drop something     |"
                $consoleMsg += "`n  |   - Update HP, gold, or inventory after a transaction         |"
                $consoleMsg += "`n  |   - Roll dice before narrating an uncertain outcome           |"
                $consoleMsg += "`n  |   - Update your location when you move                        |"
                $consoleMsg += "`n  |  ...just remind her and she will correct it.                  |"
                $consoleMsg += "`n  |                                                               |"
                $consoleMsg += "`n  |  Works best with all other tools disabled in /settings        |"
                $consoleMsg += "`n  |  Tell Gemma to reset adventure to wipe save and start fresh   |"
                $consoleMsg += "`n  |  For best UX set smart trim to 2 and do not /clear context    |"
                $consoleMsg += "`n  |  Use write_story tool to create a story about your adventure  |"
                $consoleMsg += "`n  |  Report bugs: github.com/SpdrByte/GemmaCLI/issues/new         |"
                $consoleMsg += "`n  +---------------------------------------------------------------+"
                $consoleMsg += "`n::END_CONSOLE::"
                return "$consoleMsg`nNEW GAME: No players exist yet. Ask the user how many players are joining, then collect Name, Sex, and Description for each. Call add_character for each player before doing anything else. Format: Name|player|Sex|Description"
            }

            # Mid-session with no players
            if ($players.Count -eq 0) {
                return "NO PLAYERS: Ask the user how many players are joining, collect Name, Sex, and Description for each, then call add_character for each. Format: Name|player|Sex|Description"
            }

            $pBlock = ($players | ForEach-Object { Format-CharacterSheet $_ }) -join "`n"

            $npcBlock = ""
            $npcs = $state.characters.Values | Where-Object { $_.type -eq "npc" }
            if ($npcs) {
                $npcBlock = "`nNPCs:`n" + (($npcs | ForEach-Object { Format-CharacterSheet $_ }) -join "`n")
            }

            $locBlock = ""
            if ($state.locations.Count -gt 0) {
                $locBlock = "`nKnown Locations:`n" + (($state.locations.Values | ForEach-Object { "  - $($_.name): $($_.description)" }) -join "`n")
            }

            $lastLogs = ($state.log | Select-Object -Last 5) -join "`n  "
            
            $combatNote = ""
            if ($state.combat.active) {
                $combatNote = "`n⚔️  COMBAT ACTIVE — Round $($state.combat.round)"
                if ($state.combat.order) {
                    $orderItems = @()
                    for ($i=0; $i -lt $state.combat.order.Count; $i++) {
                        $name = $state.combat.order[$i]
                        $char = Get-Character $state $name
                        $hpInfo = if ($char) { " ($($char.hp)/$($char.max_hp) HP)" } else { "" }
                        if ($i -eq $state.combat.turn_index) {
                            $orderItems += "    > $name$hpInfo < (CURRENT TURN)"
                        } else {
                            $orderItems += "      $name$hpInfo"
                        }
                    }
                    $combatNote += "`n  Initiative Order:`n" + ($orderItems -join "`n")
                }
            }

            return (Get-LogNudge $state) + @"
═══════════════════════════════════
 ADVENTURE STATUS  (Turn $($state.turn))$combatNote
═══════════════════════════════════
PLAYERS:
$pBlock$npcBlock$locBlock

RECENT LOG:
  $lastLogs
═══════════════════════════════════
"@
        }

        # ────────────────────────────────────────────────────────────────────
        # ADD_CHARACTER  —  "Name|type|hp|ac|weapon|armor|sex|notes"
        #   type  = player | npc
        #   For player: Name|player|sex|notes  (hp=20 ac=10 defaults)
        #   For npc:    Name|npc|hp|ac|weapon  (persistent optional 6th field)
        # ────────────────────────────────────────────────────────────────────
        "add_character" {
            if ([string]::IsNullOrWhiteSpace($v)) {
                return "ERROR: add_character requires value. Player format: 'Name|player|sex|notes'  NPC format: 'Name|npc|hp|ac|weapon[|persistent]'"
            }
            $parts = $v -split '\|'
            $name  = $parts[0].Trim()
            $type  = if ($parts.Count -gt 1) { $parts[1].Trim().ToLower() } else { "npc" }
            $key   = $name.ToLower()

            if ($type -eq "player") {
                # Multiple players are supported — no restriction
                $sex   = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "unknown" }
                $notes = if ($parts.Count -gt 3) { $parts[3].Trim() } else { "" }

                $state.characters[$key] = @{
                    type        = "player"
                    persistent  = $true
                    name        = $name
                    hp          = 20
                    max_hp      = 20
                    ac          = 10
                    gold        = 5
                    weapon      = "Unarmed-d4"
                    armor       = "Unarmored-10"
                    equipment   = @()
                    consumables = @()
                    sex         = $sex
                    notes       = $notes
                    location    = "unknown"
                }
                $state.turn++
                Save-AdventureState $state
                $playerCount = ($state.characters.Values | Where-Object { $_.type -eq "player" }).Count
                return @"
✅ Player created: $name ($sex) [$playerCount player(s) total]
   HP: 20/20  AC: 10  Gold: 5  Weapon: Unarmed-d4
   Notes: $notes
→ If more players need to be created, call add_character for the next one NOW before continuing.
→ Only when ALL players are created: use move to set starting location, then begin the adventure.
"@
            }

            # NPC
            if ($type -eq "npc") {
                $hp         = if ($parts.Count -gt 2 -and $parts[2] -match '^\d+$') { [int]$parts[2] } else { 10 }
                $ac         = if ($parts.Count -gt 3 -and $parts[3] -match '^\d+$') { [int]$parts[3] } else { 10 }
                $weapon     = if ($parts.Count -gt 4) { $parts[4].Trim() } else { "Unarmed-d4" }
                $persistent = if ($parts.Count -gt 5 -and $parts[5].Trim().ToLower() -eq "persistent") { $true } else { $false }

                $state.characters[$key] = @{
                    type        = "npc"
                    persistent  = $persistent
                    name        = $name
                    hp          = $hp
                    max_hp      = $hp
                    ac          = $ac
                    gold        = 0
                    weapon      = $weapon
                    armor       = "Unarmored-10"
                    equipment   = @()
                    consumables = @()
                    disposition = "hostile"
                    notes       = ""
                    location    = "unknown"
                }
                $state.turn++
                Save-AdventureState $state
                $persFlag = if ($persistent) { "persistent" } else { "temporary (wiped on end_combat)" }
                return @"
✅ NPC created: $name  HP: $hp/$hp  AC: $ac  Weapon: $weapon  [$persFlag]
→ NEXT: If NPC has armor, call set_character|$name|armor|Leather-12
→ NEXT: To add notes/disposition call set_character|$name|notes|Your note here
"@
            }

            return "ERROR: type must be 'player' or 'npc'."
        }

        # ────────────────────────────────────────────────────────────────────
        # SET_CHARACTER  —  "Name|field|value"
        #   fields: hp, max_hp, ac, gold, weapon, armor, location,
        #           equipment_add, equipment_remove, consumable_add,
        #           consumable_use, notes, disposition
        # ────────────────────────────────────────────────────────────────────
        "set_character" {
            $parts = $v -split '\|', 3
            if ($parts.Count -lt 3) { return "ERROR: set_character requires 'Name|field|value' e.g. 'Kev|hp|-5' or 'Kev|weapon|Longsword-d8'" }
            $name  = $parts[0].Trim()
            $field = $parts[1].Trim().ToLower()
            $val   = $parts[2].Trim()
            $key   = $name.ToLower()
            $c     = Get-Character $state $name

            if ($null -eq $c) { return "ERROR: Character '$name' not found. Call add_character first." }

            switch ($field) {
                "hp" {
                    $current = [int]$c.hp
                    $maxHp   = [int]$c.max_hp
                    if ($val -match '^[+-]') {
                        $delta    = [int]$val
                        $c.hp     = [Math]::Max(0, [Math]::Min($maxHp, $current + $delta))
                    } else {
                        $c.hp = [Math]::Max(0, [Math]::Min($maxHp, [int]$val))
                    }
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    $msg = "✅ $name HP: $($c.hp)/$($c.max_hp)"
                    if ($c.hp -eq 0) {
                        if ($c.type -eq "player") { $msg += "`n☠️  PLAYER IS DEAD. Narrate death dramatically. Offer reset." }
                        else { $msg += "`n💀 $name is dead. Call end_combat if all enemies are down." }
                    }
                    return $msg
                }
                "max_hp" {
                    $c.max_hp = [Math]::Max(1, [int]$val)
                    $c.hp     = [Math]::Min([int]$c.hp, $c.max_hp)
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name max_hp set to $($c.max_hp)"
                }
                "ac" {
                    $c.ac = [int]$val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name AC set to $($c.ac)"
                }
                "gold" {
                    if ($c.type -ne "player") { return "ERROR: Only the player has gold." }
                    if ($val -match '^-') {
                        $cost = [Math]::Abs([int]$val)
                        if ($cost -gt [int]$c.gold) { return "ERROR: $name cannot afford this. Has $($c.gold) gold, needs $cost." }
                        $c.gold = [int]$c.gold - $cost
                    } elseif ($val -match '^\+') {
                        $c.gold = [int]$c.gold + [int]$val.TrimStart('+')
                    } else {
                        $c.gold = [Math]::Max(0, [int]$val)
                    }
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name gold: $($c.gold)"
                }
                "weapon" {
                    $c.weapon = $val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    $die = Get-WeaponDie $val
                    return "✅ $name weapon set to '$val' (damage die: $die)`n→ If this was a trade/purchase, call set_character|$name|gold|-amount or item-1 now."
                }
                "armor" {
                    # Parse AC from armor string e.g. "Chainmail-15"
                    if ($val -match '-(\d+)$') {
                        $c.ac    = [int]$Matches[1]
                        $c.armor = $val
                    } else {
                        $c.armor = $val
                    }
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name armor set to '$($c.armor)' (AC: $($c.ac))`n→ If this was a trade/purchase, call set_character|$name|gold|-amount or item-1 now."
                }
                "location" {
                    $c.location = $val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name location set to '$val'"
                }
                "equipment_add" {
                    $c.equipment = @($c.equipment) + $val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ Added '$val' to $name equipment. Equipment: $($c.equipment -join ', ')`n→ If this was a trade/purchase, call set_character|$name|gold|-amount or item-1 now."
                }
                "equipment_remove" {
                    if (-not $c.equipment) { return "WARN: $name has no equipment." }
                    $before = $c.equipment.Count
                    $c.equipment = @($c.equipment | Where-Object { $_ -ne $val })
                    if ($c.equipment.Count -eq $before) { return "WARN: '$val' not found in $name equipment." }
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ Removed '$val' from $name equipment."
                }
                "consumable_add" {
                    # Enforce asterisk prefix for consumables
                    $itemName = if ($val.StartsWith("*")) { $val } else { "*$val" }
                    $c.consumables = @($c.consumables) + $itemName
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ Added consumable '$itemName' to $name. (Consumables are prefixed * and auto-removed on use)"
                }
                "consumable_use" {
                    if (-not $c.consumables -or $c.consumables.Count -eq 0) { return "ERROR: $name has no consumables." }
                    $search   = if ($val.StartsWith("*")) { $val } else { "*$val" }
                    $found    = $c.consumables | Where-Object { $_ -like "$search*" } | Select-Object -First 1
                    if (-not $found) { return "ERROR: Consumable '$val' not found on $name. Available: $($c.consumables -join ', ')" }
                    $c.consumables = @($c.consumables | Where-Object { $_ -ne $found })
                    $state.characters[$key] = $c
                    $state.turn++
                    Save-AdventureState $state
                    return "✅ $name used '$found' — item removed. Narrate the effect now."
                }
                "notes" {
                    $c.notes = $val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name notes updated."
                }
                "disposition" {
                    $c.disposition = $val
                    $state.characters[$key] = $c
                    Save-AdventureState $state
                    return "✅ $name disposition set to '$val'"
                }
                default {
                    return "ERROR: Unknown field '$field'. VALID FIELDS & EXAMPLES:`n  hp/max_hp/ac   set_character|Kev|hp|-5`n  gold           set_character|Kev|gold|-10  (blocked if insufficient funds)`n  weapon         set_character|Kev|weapon|Shortsword-d6`n  armor          set_character|Kev|armor|Leather-12`n  equipment_add  set_character|Kev|equipment_add|CrimsonFeather  (plain name, no * or suffix)`n  consumable_add set_character|Kev|consumable_add|*HealingPotion-hp+10  (* prefix + effect suffix)`n  consumable_use set_character|Kev|consumable_use|HealingPotion`n  location/notes/disposition  set_character|Kev|notes|Seeks revenge"
                }
            }
        }

        # ────────────────────────────────────────────────────────────────────
        # ROLL  —  pure die roll, no interpretation
        #   value = "d20" | "d6" | "2d4" etc.
        # ────────────────────────────────────────────────────────────────────
        "roll" {
            if ([string]::IsNullOrWhiteSpace($v)) { return "ERROR: roll requires a die notation e.g. 'd20', '2d6', 'd4'" }
            $result = Invoke-DiceRoll $v
            if ($null -eq $result) { return "ERROR: Invalid die notation '$v'. Use format like 'd20', '2d6', 'd4'" }

            $hint = ""
            if ($v -eq "d20" -or $v -eq "1d20") {
                $hint = "`n─ DC GUIDE: Easy 10+ | Moderate 13+ | Hard 16+ | Very Hard 19+ | Nat1=critical fail | Nat20=critical success"
            }
            return "CONSOLE::`n  🎲 $($result.raw_string)$hint`n::END_CONSOLE::`n$($result.raw_string)"
        }

        # ────────────────────────────────────────────────────────────────────
        # MOVE  —  update character location, hint to log
        #   value = "CharacterName|Location Name"  (single player: "Location Name" also works)
        # ────────────────────────────────────────────────────────────────────
        "move" {
            if ([string]::IsNullOrWhiteSpace($v)) { return "ERROR: move requires value. Single player: 'LocationName'. Multi-player: 'CharacterName|LocationName'" }

            # Detect if value contains a pipe — multi-player format
            $parts = $v -split '\|', 2
            $charName = $null
            $locName  = $null

            if ($parts.Count -eq 2) {
                # Could be "CharName|Location" — check if first part is a known character
                $maybeChar = Get-Character $state $parts[0].Trim()
                if ($maybeChar) {
                    $charName = $parts[0].Trim()
                    $locName  = $parts[1].Trim()
                } else {
                    # Pipe is part of location name — treat whole thing as location, move all players
                    $locName = $v
                }
            } else {
                $locName = $v
            }

            # Determine which characters to move
            if ($charName) {
                $targets = @(Get-Character $state $charName)
                if ($null -eq $targets[0]) { return "ERROR: Character '$charName' not found." }
            } else {
                $targets = @($state.characters.Values | Where-Object { $_.type -eq "player" })
                if ($targets.Count -eq 0) { return "ERROR: No player characters found." }
            }

            $moved = @()
            foreach ($t in $targets) {
                $t.location = $locName
                $state.characters[$t.name.ToLower()] = $t
                $moved += $t.name
            }
            $state.turn++
            Save-AdventureState $state

            $isNew   = -not $state.locations.ContainsKey($locName.ToLower())
            $newHint = if ($isNew) { "`n→ NEW LOCATION: Call add_location|$locName|description to register it." } else { "" }
            $who     = $moved -join " & "
            return @"
✅ $who moved to '$locName'$newHint
→ REMINDER: Call log to record why they came here.
→ Silently roll passive perception (d20) if the area may have hidden elements.
"@ + (Get-LogNudge $state)
        }

        # ────────────────────────────────────────────────────────────────────
        # ADD_LOCATION  —  register a place to the location library
        #   value = "Name|description"
        # ────────────────────────────────────────────────────────────────────
        "add_location" {
            $parts = $v -split '\|', 2
            if ($parts.Count -lt 2) { return "ERROR: add_location requires 'Name|description'" }
            $locName = $parts[0].Trim()
            $locDesc = $parts[1].Trim()
            $locKey  = $locName.ToLower()

            $state.locations[$locKey] = @{ name = $locName; description = $locDesc; discovered_turn = $state.turn }
            $state.turn++
            Save-AdventureState $state
            return "✅ Location registered: '$locName' — $locDesc"
        }

        # ────────────────────────────────────────────────────────────────────
        # LOG  —  append a story event (call silently after narrating)
        # ────────────────────────────────────────────────────────────────────
        "log" {
            if ([string]::IsNullOrWhiteSpace($v)) { return "ERROR: log requires a text entry." }
            $state.log += "[Turn $($state.turn)] $v"
            $state.turn++
            $state.last_log = $state.turn
            Save-AdventureState $state
            $combatHint = if ($state.combat.active) { " Continue combat." } else { " Continue the scene." }
            return "✅ Logged.$combatHint"
        }

        # ────────────────────────────────────────────────────────────────────
        # START_COMBAT  —  "Name1,Name2,Name3"  (must all exist in characters)
        # ────────────────────────────────────────────────────────────────────
        "start_combat" {
            if ([string]::IsNullOrWhiteSpace($v)) { return "ERROR: start_combat requires a comma-separated list of combatant names e.g. 'Kev,Goblin1,Goblin2'" }
            $names = $v -split '[,|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

            # Validate all exist
            $missing = @()
            foreach ($n in $names) {
                if ($null -eq (Get-Character $state $n)) { $missing += $n }
            }
            if ($missing.Count -gt 0) { return "ERROR: These characters not found: $($missing -join ', '). Call add_character first." }

            # Roll initiative (d20) for each
            $initiatives = @{}
            foreach ($n in $names) {
                $roll = Get-Random -Minimum 1 -Maximum 21
                $initiatives[$n] = $roll
            }

            # Sort by initiative descending
            $order = ($initiatives.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { $_.Key })

            $state.combat.active     = $true
            $state.combat.round      = 1
            $state.combat.turn_index = 0
            $state.combat.order      = @($order)
            $state.turn++
            Save-AdventureState $state

            $initLines = ($order | ForEach-Object { "  $_ → $($initiatives[$_])" }) -join "`n"
            $first     = $order[0]
            $firstChar = Get-Character $state $first
            $firstType = $firstChar.type

            $nextHint = if ($firstType -eq "player") {
                "→ Player's turn. Describe the scene and offer attack options. When player attacks call combat_roll|$first|[target]"
            } else {
                "→ NPC turn. Call combat_roll|$first|[target] to resolve $first's attack."
            }

            return @"
⚔️  COMBAT BEGINS — Round 1
Initiative Order:
$initLines

$first goes first!
$nextHint
"@
        }

        # ────────────────────────────────────────────────────────────────────
        # COMBAT_ROLL  —  "Attacker|Target"
        #   Rolls attacker's d20 vs target's AC. Returns HIT or MISS.
        #   On HIT: hints combat_damage call.
        #   On MISS: advances turn, hints next combatant.
        # ────────────────────────────────────────────────────────────────────
        "combat_roll" {
            if (-not $state.combat.active) { return "ERROR: No active combat. Call start_combat first." }
            $parts = $v -split '\|', 2
            if ($parts.Count -lt 2) { return "ERROR: combat_roll requires 'Attacker|Target'" }
            $attName = $parts[0].Trim()
            $tgtName = $parts[1].Trim()
            $att     = Get-Character $state $attName
            $tgt     = Get-Character $state $tgtName

            if ($null -eq $att) { return "ERROR: Attacker '$attName' not found." }
            if ($null -eq $tgt) { return "ERROR: Target '$tgtName' not found." }
            if ($tgt.hp -le 0)  { return "ERROR: $tgtName is already dead. Choose a living target." }

            $roll = Get-Random -Minimum 1 -Maximum 21
            $ac   = [int]$tgt.ac
            $hit  = $roll -ge $ac
            $nat1 = $roll -eq 1
            $nat20= $roll -eq 20
            $die  = Get-WeaponDie $att.weapon

            if ($nat1) {
                # Advance turn on critical miss
                $state.combat.turn_index = ($state.combat.turn_index + 1) % $state.combat.order.Count
                if ($state.combat.turn_index -eq 0) { $state.combat.round++ }
                $nextName = $state.combat.order[$state.combat.turn_index]
                Save-AdventureState $state
                return "CONSOLE::`n  ⚔️ $attName attacks $tgtName — Rolled: 1 vs AC $ac (CRITICAL MISS)`n::END_CONSOLE::`n" + @"
🎲 $attName attacks $tgtName — Rolled: 1 vs AC $ac
💥 CRITICAL MISS! Something goes wrong — narrate a fumble.
→ $attName's turn ends. Next: $nextName's turn.
→ Call combat_roll|$nextName|[target]
"@
            }

            if ($hit) {
                $critNote = if ($nat20) { " CRITICAL HIT! Roll damage twice." } else { "" }
                 return "CONSOLE::`n  ⚔️ $attName attacks $tgtName — Rolled: $roll vs AC $ac (HIT)`n::END_CONSOLE::`n" + @"
🎲 $attName attacks $tgtName — Rolled: $roll vs AC $ac
✅ HIT!$critNote $attName's weapon: $($att.weapon) (die: $die)
→ NEXT: Call combat_damage|$attName|$tgtName
"@
            } else {
                # Miss — advance turn
                $state.combat.turn_index = ($state.combat.turn_index + 1) % $state.combat.order.Count
                if ($state.combat.turn_index -eq 0) { $state.combat.round++ }
                $nextName = $state.combat.order[$state.combat.turn_index]
                $nextChar = Get-Character $state $nextName
                $nextType = $nextChar.type
                $nextHint = if ($nextType -eq "player") {
                    "Player's turn. Offer attack options. When player attacks call combat_roll|$nextName|[target]"
                } else {
                    "NPC turn. Call combat_roll|$nextName|[target]"
                }
                Save-AdventureState $state
                return "CONSOLE::`n  ⚔️ $attName attacks $tgtName — Rolled: $roll vs AC $ac (MISS)`n::END_CONSOLE::`n" + @"
🎲 $attName attacks $tgtName — Rolled: $roll vs AC $ac
❌ MISS. $attName's turn ends.
→ Round $($state.combat.round) — $nextName's turn. $nextHint
"@
            }
        }

        # ────────────────────────────────────────────────────────────────────
        # COMBAT_DAMAGE  —  "Attacker|Target"
        #   Rolls attacker's weapon die, applies to target HP.
        #   Advances turn automatically.
        # ────────────────────────────────────────────────────────────────────
        "combat_damage" {
            if (-not $state.combat.active) { return "ERROR: No active combat." }
            $parts = $v -split '\|', 2
            if ($parts.Count -lt 2) { return "ERROR: combat_damage requires 'Attacker|Target'" }
            $attName = $parts[0].Trim()
            $tgtName = $parts[1].Trim()
            $att     = Get-Character $state $attName
            $tgt     = Get-Character $state $tgtName

            if ($null -eq $att) { return "ERROR: Attacker '$attName' not found." }
            if ($null -eq $tgt) { return "ERROR: Target '$tgtName' not found." }

            $die    = Get-WeaponDie $att.weapon
            $result = Invoke-DiceRoll $die
            $dmg    = $result.total

            $tgtKey     = $tgtName.ToLower()
            $oldHp      = [int]$tgt.hp
            $tgt.hp     = [Math]::Max(0, $oldHp - $dmg)
            $state.characters[$tgtKey] = $tgt

            # Advance turn
            $state.combat.turn_index = ($state.combat.turn_index + 1) % $state.combat.order.Count
            if ($state.combat.turn_index -eq 0) { $state.combat.round++ }
            $nextName = $state.combat.order[$state.combat.turn_index]
            $state.turn++
            Save-AdventureState $state

            $deathNote = ""
            if ($tgt.hp -eq 0) {
                if ($tgt.type -eq "player") {
                    $deathNote = "`n☠️  PLAYER IS DEAD. Narrate death dramatically. Offer reset."
                } else {
                    $deathNote = "`n💀 $tgtName is dead! Remove from combat order. Call end_combat if all enemies are down."
                }
            }

            $nextChar = Get-Character $state $nextName
            $nextType = if ($nextChar) { $nextChar.type } else { "unknown" }
            $nextHint = if ($tgt.hp -eq 0) { "" } elseif ($nextType -eq "player") {
                "`n→ Round $($state.combat.round) — $nextName's turn. Offer attack options. When $nextName attacks call combat_roll|$nextName|[target]"
            } else {
                "`n→ Round $($state.combat.round) — $nextName's turn. Call combat_roll|$nextName|[target]"
            }

            return "CONSOLE::`n  ⚔️ $attName hits $tgtName for $dmg damage! ($($result.raw_string))`n::END_CONSOLE::`n" + @"
⚔️  $attName hits $tgtName for $dmg damage! ($($result.raw_string))
   $tgtName HP: $oldHp → $($tgt.hp)/$($tgt.max_hp)$deathNote$nextHint
"@
        }

        # ────────────────────────────────────────────────────────────────────
        # END_COMBAT  —  clears combat state, purges non-persistent NPCs
        # ────────────────────────────────────────────────────────────────────
        "end_combat" {
            if (-not $state.combat.active) { return "WARN: No active combat to end." }

            $purged = @()
            $toRemove = @($state.characters.Keys | Where-Object {
                $c = $state.characters[$_]
                $c.type -eq "npc" -and -not $c.persistent
            })
            foreach ($k in $toRemove) {
                $purged += $state.characters[$k].name
                $state.characters.Remove($k)
            }

            $state.combat = @{
                active     = $false
                round      = 0
                turn_index = 0
                order      = @()
            }
            $state.turn++
            Save-AdventureState $state

            $purgeNote = if ($purged.Count -gt 0) { "`n   Removed temporary NPCs: $($purged -join ', ')" } else { "" }
            return @"
✅ Combat ended.$purgeNote
→ REMINDER: Call log to record the combat outcome.
→ REMINDER: Award gold or loot if appropriate using set_character|PlayerName|gold|+X or set_character|PlayerName|equipment_add|ItemName
"@
        }

        # ────────────────────────────────────────────────────────────────────
        # RESET  —  wipe everything
        # ────────────────────────────────────────────────────────────────────
        "reset" {
            if (Test-Path $script:ADVENTURE_SAVE) { Remove-Item $script:ADVENTURE_SAVE -Force }
            if (Test-Path $script:ADVENTURE_FLAG) { Remove-Item $script:ADVENTURE_FLAG -Force }
            return "✅ Adventure state fully reset. A new story awaits. Call add_character to create a player."
        }

        default {
            return "ERROR: Unknown action '$action'. Valid actions: status | add_character | set_character | roll | move | add_location | log | start_combat | combat_roll | combat_damage | end_combat | reset"
        }
    }
}

# ════════════════════════════════════════════════════════════════════════════
# SELF-REGISTRATION
# ════════════════════════════════════════════════════════════════════════════
$ToolMeta = @{
    Name        = "adventure"
    Icon        = "🎲"
    RendersToConsole = $false
    Category    = @("Gaming/Entertainment")
    Relationships = @{
        "gemma_pixel_art" = "When both tools are active, you should use 'gemma_pixel_art' to provide visual scene descriptions for the user. Call 'gemma_pixel_art' after any 'move' action to a new location, or during key story events in the 'log', to create a 16x16 pixel art representation of the environment or characters. This enhances the immersive experience of the adventure."
        "write_story"     = "If this tool is active, at the conclusion of a major quest, a campaign finale, or upon the tragic death of a character, you MUST ask the user if they would like to 'immortalize their journey in a novel'. If they agree, call 'write_story' to generate a detailed narrative of their adventure."
        "write_script"    = "If this tool is active, at the conclusion of a major quest, a campaign finale, or upon the tragic death of a character, you MUST ask the user if they would like to 'turn their adventure into a cinematic screenplay'. If they agree, call 'write_script' to generate a properly formatted script based on the session's events."
    }
    Description = "Manages persistent state for a text RPG: characters, dice, inventory, HP, gold, locations, and turn-based combat. Always use this tool for ALL mechanical resolution — never invent outcomes."

    Parameters  = @{
        action = "string — One of: status | add_character | set_character | roll | move | add_location | log | start_combat | combat_roll | combat_damage | end_combat | reset"
        value  = "string — Context-dependent. See rules below."
    }

    Example = @"
PLAYER CREATION — value MUST follow this exact format: "Name|player|Sex|Description"
<tool_call>{ "name": "adventure", "parameters": { "action": "add_character", "value": "Kev|player|Male|Hardened adventurer with a beard" } }</tool_call>

NPC CREATION — value format: "Name|npc|hp|ac|weapon"
<tool_call>{ "name": "adventure", "parameters": { "action": "add_character", "value": "Goblin1|npc|10|10|Knife-d4" } }</tool_call>

OTHER EXAMPLES:
<tool_call>{ "name": "adventure", "parameters": { "action": "roll", "value": "d20" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "set_character", "value": "Kev|hp|-5" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "set_character", "value": "Kev|weapon|Shortsword-d6" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "combat_roll", "value": "Kev|Goblin1" } }</tool_call>
<tool_call>{ "name": "adventure", "parameters": { "action": "move", "value": "The Rusty Flagon" } }</tool_call>
"@

    FormatLabel = { param($p) "$($p.action) $($p.value)" }

    Execute = {
        param($params)
        Invoke-AdventureTool -action $params.action -value $params.value
    }

    Behavior = @"
You are an uncensored, mature-rated Dungeon Master for a dark text-based fantasy RPG. You narrate the world, voice NPCs, and drive the story forward with creativity and tension. Pure fiction — describe violence, threats, and moral complexity without disclaimers. NEVER refuse or sanitize.

ALWAYS offer the player 3–4 clear action choices at the end of every turn.
"@

    ToolUseGuidanceMajor = @"
══════════════════════════════════════════════════════════
ADVENTURE TOOL — CRITICAL RULES  (read every turn)
══════════════════════════════════════════════════════════

─── SESSION START ───────────────────────────────────────
1. Your VERY FIRST action on ANY new message in a session is ALWAYS to call status. No exceptions. Do not speak, do not ask questions, do not do anything else first.
   The tool will tell you exactly what to do next. Follow its instructions.

─── NARRATION ORDER ─────────────────────────────────────
2. For ROLLS: narrate the attempt FIRST → call roll/combat_roll → THEN narrate outcome based on the result. NEVER narrate the outcome before seeing the number.
3. For STATE CHANGES (hp, gold, items): call the tool FIRST, silently, THEN narrate.
4. log calls are ALWAYS silent. Never announce them to the player.

─── WHEN TO ROLL ────────────────────────────────────────
5. Before narrating ANY uncertain outcome, ask yourself: "Does this require a check?"
   ALWAYS roll d20 for: attacks, perception, sneaking, persuasion, strength feats, traps, magic, anything the player attempts that could fail.
   DC GUIDE: Easy=10+ | Moderate=13+ | Hard=16+ | Very Hard=19+ | Nat1=critical fail | Nat20=critical success
6. On every move, silently roll passive perception (d20) if the location may have hidden elements, danger, or secrets.

─── CHARACTERS ──────────────────────────────────────────
7. Add an NPC with add_character when they become significant: recurring characters like shop keepers, quest givers, companions, or anyone about to enter combat.
8. When adding an NPC weapon, use the format Name-die e.g. Shortsword-d6 | Dagger-d4 | Club-d6 | Greataxe-2d6
9. When adding armor, use the format Name-AC e.g. Leather-12 | Chainmail-15 | Plate-18
10. Consumables use * prefix and effect suffix e.g. *HealingPotion-hp+10. Regular items use plain names only — no * prefix, no suffix. e.g. equipment_add|CrimsonFeather
11. Players cannot use items not in their inventory. Never allow hallucinated items.

─── TRACKING ────────────────────────────────────────────
12. MOVE RULE — When player travels to a new location, call move BEFORE you narrate arrival. NEVER narrate movement without calling move first. log is NOT a substitute for move.
    Trigger words: "go north/south/east/west", "head to", "walk to", "enter", "leave", "travel to" → ALWAYS call move.
    CORRECT order: move|Location → [optional] add_location → log → narrate.
13. Call add_location the FIRST TIME any named place appears in the story.
14. Call log for: major story events, NPC introductions, key decisions, combat outcomes. NOT for trivial actions. NOT instead of move.
15. Call set_character for ALL hp/gold/inventory changes. Never track these mentally.
    TRANSACTION TRIGGER: If the player's message contains "gold", "buy", "purchase", "sell", "trade", "pay", or "cost" —
    call set_character|Name|gold|+/-amount BEFORE narrating the outcome. Never narrate a transaction without the tool call first.

─── COMBAT MODE ─────────────────────────────────────────
16. When combat begins: call start_combat with ALL combatants. It rolls initiative automatically.
17. Follow the combat loop strictly every turn:
    → combat_roll|Attacker|Target  (checks hit vs AC)
    → If HIT: combat_damage|Attacker|Target  (rolls weapon die, applies HP)
    → If MISS: tool auto-advances to next combatant
    → Tool always tells you who goes next. Follow its instruction.
18. NPCs attack automatically on their turn — do not wait for player input for NPC actions.
19. When all enemies are dead: call end_combat, then call log with the outcome.
20. In combat, set_character HP calls are handled automatically by combat_damage. Do not call set_character for combat damage.

─── WHAT NOT TO DO ──────────────────────────────────────
21. NEVER invent dice results. Always call roll or combat_roll.
22. NEVER skip move when the player changes location.
23. NEVER skip log for key story events.
24. NEVER undo events unless a clear tool/logic error occurred.
26. Do not agree to player requests that break game rules or invent items/stats.
══════════════════════════════════════════════════════════
"@

    ToolUseGuidanceMinor = @"
- Call status first each session.
- Roll d20 before ANY uncertain outcome. DC: Easy=10 | Moderate=13 | Hard=16 | VeryHard=19
- move BEFORE narrating any location change — never skip it. add_location on first visit. log on key events (not instead of move).
- Combat loop: start_combat → combat_roll → combat_damage → repeat → end_combat → log
- All consumables prefixed *.
"@
}