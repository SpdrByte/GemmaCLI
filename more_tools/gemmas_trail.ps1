# ===============================================
# GemmaCLI tool - oregon_trail.ps1 v1.1.1
# Responsibility: Turn-based adventure logic for Gemma's Trail.
# Workflow: CLI -> Invoke-GemmasTrailTool -> [Result Object] -> Gemma Synthesis -> Return to User
# ===============================================


$script:OregonTrailArt = @'
  __________________________________________________________________________
 /                                                                          \
|   _      _      _      _      _      _      _      _      _      _      _  |
|  / \    / \    / \    / \    / \    / \    / \    / \    / \    / \    / \ |
| ( G )  ( E )  ( M )  ( M )  ( A )  ( S )  ( T )  ( R )  ( A )  ( I )  ( L )|
|  \_/    \_/    \_/    \_/    \_/    \_/    \_/    \_/    \_/    \_/    \_/ |
|                                                                            |
 \__________________________________________________________________________/
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█████████████░░░░░░░██░░░░░░██░░░░█░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░███░░████░░█████████░█████░░█░██░░█████░░░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░███░█████████░██░██████░██████░░██████░███░░░░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██░███░██░████░██░██████░██████░███████░█████░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██░░██░██░██░██░█░███████░█████░░██████░█████░░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█░█░█░░█░██░███░█░░██████░██████░███████░█████░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░███░██░█░██░██░░██░██████░██████░█████████████░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██░██░█░██████░██░██████░███░██░██░███░████░█░
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░███░██████████░█░░██░███░██░█████░██░█░███░██░
░░░░░█░░░░█░░░░░█░░░░░░░░░░░░░░███████████████░░░░░█░░░█████████░░████████░░
█░░░░░░░░░░██░█░██░░███░░░░░░░░██░░░░░███░░██░███░░░░██░░░░░░█░░░░████████░░
░█░████░███░░░░███░░█░███████░░░██████░░░░███░████████████████████░███████░░
░░██░█████░░░███░████░░█░░░░░░░░░░░░░░░░░░███░██████░██████░████████████░░░░
░░████████░█████░████░███░█░██░██████████░███░██░░░█░█░░░░░░░░░░░░░█████░░░░
░████░███░░░██████░░░░███████████████░░░░░██░░░░███████████████████░░░░░░░░░
░░░░░████░██░░░█████░█░░░█████████████████░█░███░░░░░████████████░██████░░░░
░░░░░░░█░█████████░░██████░░░░██████░░░█████░░█░█████░░░░░░░░░░█░█░░░░░░█░░░
░░░░░░░░░██░░████░░████████████░░░░░███░░█░░░█░█░░░███░███████░█░░█████░█░░░
░░░░░░░░░░█░░░████░░░░░███░░░░░█████░░████████░██░███░█░█░░░░░░██░████░░█░░░
░░░░░░░░░░░█████░░█████░███░█░░██░░█████░█░░░█░░████░░██░░░░░░░█░██░█░░░█░░░
░░░░░░░░░░░█░░░░░░░░░░█░█░█░░░░███░░█░░░░█░░░█░░░█░░░█░█░░░░░░░█░░░░█░░█░░░░
░░░░░░░░░░░░░░░░░░██░░░░░█░░████░██░░██████████░█████░████████████░███░█████
░░░░░░░░░███████████████░████░░████░████████████░░░░░██████████████░█████░░░
███████████████░░░█████░░██████████████████░█░███░██████░░░░░░░░░░░░░░░░░░░░
░░░░░░░░░░░░░░░░░░░██░░░░█░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
      [ Pioneer Journal: Week $($state.meta.week_number) | Distance: $($state.party.miles_traveled)/2000 mi ]
'@

function Get-OregonState {
    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "C:\Users\kevin\Documents\AI\GemmaCLI" }
    $dbFile = Join-Path $scriptRootDir "database/oregon_trail.json"
    if (Test-Path $dbFile) {
        return Get-Content $dbFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Save-OregonState {
    param($state)
    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "C:\Users\kevin\Documents\AI\GemmaCLI" }
    $dbFile = Join-Path $scriptRootDir "database/oregon_trail.json"
    
    # Sync member status based on health
    foreach ($m in $state.party.members) {
        if ($m.health -le 0) { $m.health = 0; $m.status = "Dead" }
        elseif ($m.health -lt 40) { $m.status = "Critical" }
        elseif ($m.health -lt 75) { $m.status = "Poor" }
        else { $m.status = "Healthy" }
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content $dbFile -Force
}

function Invoke-GemmasTrailTool {
    param(
        [string]$action = "status", # "setup" | "status" | "travel" | "hunt" | "rest"
        [string]$profession = "Banker", 
        [hashtable]$purchases = @{},
        [string[]]$party_names = @(),
        [string]$pace = "Steady",
        [string]$rations = "Filling"
    )

    $state = Get-OregonState
    if ($null -eq $state -and $action -ne "setup") { return "ERROR: Oregon Trail database missing. Run 'setup' first." }

    # Sync parameters into state if provided (allows dynamic pace/ration changes via tool call)
    if ($null -ne $state) {
        if ($PSBoundParameters.ContainsKey('pace')) { $state.config.pace = $pace }
        if ($PSBoundParameters.ContainsKey('rations')) { $state.config.rations = $rations }
    }

    # ── ACTION: setup (Wizard Mode) ──────────────────────────────────────────
    if ($action -eq "setup") {
        Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
        Write-Host $script:OregonTrailArt.Replace('$($state.meta.week_number)', '0').Replace('$($state.party.miles_traveled)', '0') -ForegroundColor Cyan
        
        # 1. Choose Profession
        $profChoices = @(
            "Banker ($1600)",
            "Carpenter ($800)",
            "Farmer ($400)"
        )
        $profIdx = Show-ArrowMenu -Options $profChoices -Title "Choose your profession (Difficulty)" -Default 0
        $startingMoney = 800
        $profName = "Carpenter"
        if ($profIdx -eq 0) { $startingMoney = 1600; $profName = "Banker" }
        elseif ($profIdx -eq 2) { $startingMoney = 400; $profName = "Farmer" }

        # 2. Name the Party
        Draw-Box @("Enter names for your party of 5 (Leave blank for defaults):") -Color Cyan
        $names = @()
        for ($i = 1; $i -le 5; $i++) {
            $n = Read-Host "  Name Pioneer $i"
            if ([string]::IsNullOrWhiteSpace($n)) { $n = if($i -eq 1){"Leader"} else {"Pioneer $i"} }
            $names += $n
        }

        # 3. Matt's General Store
        $money = $startingMoney
        $cart = @{ oxen=0; food=0; clothing=0; bullets=0; spare_parts=0 }
        # Price is per ox
        $prices = @{ oxen=100; food=0.2; clothing=10; bullets=2; parts=10 } # Bullets per box of 20

        while ($true) {
            Write-Host "`n  [ MATT'S GENERAL STORE ]" -ForegroundColor Yellow
            Write-Host "  Cash: `$ $($money.ToString('F2'))" -ForegroundColor Green
            Write-Host "  ------------------------"
            Write-Host "  1. Oxen (yoke of 2: `$200)  - Count: $($cart.oxen)"
            Write-Host "  2. Food (20¢ / lb)       - Count: $($cart.food) lbs"
            Write-Host "  3. Clothing (`$10 / set)   - Count: $($cart.clothing)"
            Write-Host "  4. Bullets (`$2 / box)     - Count: $($cart.bullets)"
            Write-Host "  5. Parts (`$10 / pc)       - Count: $($cart.spare_parts)"
            Write-Host "  6. [ FINALIZE & DEPART ]"
            Write-Host ""
            
            $choice = Read-Host "  Select item to buy (1-6)"
            if ($choice -eq "6") {
                if ($cart.oxen -lt 2) { 
                    Draw-Box @("You need at least 2 oxen to pull the wagon!") -Color Red
                    continue 
                }
                break
            }

            $amtStr = Read-Host "  How many (units)?"
            $amt = if ($amtStr -match '^\d+$') { [int]$amtStr } else { 0 }
            if ($amt -le 0) { continue }

            $itemKey = switch($choice) { "1"{"oxen"}; "2"{"food"}; "3"{"clothing"}; "4"{"bullets"}; "5"{"spare_parts"} }
            $priceKey = if($itemKey -eq "spare_parts") {"parts"} else {$itemKey}
            
            # For oxen, 'amt' is number of yokes, so multiply cost and count by 2
            $multiplier = if ($itemKey -eq "oxen") { 2 } else { 1 }
            $cost = ($amt * $multiplier) * $prices[$priceKey]
            
            if ($money -ge $cost) {
                $cart.$itemKey += ($amt * $multiplier)
                $money -= $cost
            } else {
                Draw-Box @("Not enough money!") -Color Red
            }
        }

        # 4. Set Pace and Rations
        $paceChoices = @("Steady", "Strenuous", "Grueling")
        $paceIdx = Show-ArrowMenu -Options $paceChoices -Title "Choose your travel pace" -Default 0
        $chosenPace = $paceChoices[$paceIdx]

        $rationChoices = @("Filling", "Meager", "Bare Bones")
        $rationIdx = Show-ArrowMenu -Options $rationChoices -Title "Choose your daily rations" -Default 0
        $chosenRations = $rationChoices[$rationIdx]
        $state = @{
            party = @{
                money = $money
                miles_traveled = 0
                food = $cart.food
                oxen = $cart.oxen
                clothing = $cart.clothing
                bullets = $cart.bullets
                spare_parts = $cart.spare_parts
                members = @($names | ForEach-Object { @{ name = $_; status = "Healthy"; health = 100 } })
            }
            config = @{
                profession = $profName
                pace = $chosenPace
                rations = $chosenRations
            }
            meta = @{
                week_number = 0
                is_game_over = $false
                game_over_reason = ""
            }
        }

        Save-OregonState $state
        $nameList = $names -join ", "
        return "CONSOLE::PLAY_SOUND:Alarm03::END_CONSOLE::OK: 🏞️ Game initialized as a $profName. Party members: $nameList. Departed with $($cart.oxen) oxen and $($cart.food) lbs of food."
    }

    # ── ACTION: status ───────────────────────────────────────────────────────
    if ($action -eq "status") {
        $art = $script:OregonTrailArt.Replace('$($state.meta.week_number)', $state.meta.week_number).Replace('$($state.party.miles_traveled)', $state.party.miles_traveled)
        
        $membersStr = ($state.party.members | ForEach-Object { "$($_.name): $($_.health)%" }) -join " | "
        $stats = @(
            "PROFESSION: $($state.config.profession) | MONEY: $($state.party.money)",
            "PARTY HEALTH: $membersStr",
            "OXEN: ╰૮₍ •\./• ₎ა╯ $($state.party.oxen) | FOOD: $($state.party.food) lbs | CLOTHING: $($state.party.clothing)",
            "BULLETS: $($state.party.bullets) boxes | PARTS: $($state.party.spare_parts)",
            "PACE: $($state.config.pace) | RATIONS: $($state.config.rations)",
            "PROGRESS: [" + ("⛰️" * [int]($state.party.miles_traveled / 200)) + ("." * [int]((2000 - $state.party.miles_traveled) / 200)) + "]"
        )

        return "CONSOLE::PLAY_SOUND:Alarm03`n$art`n::END_CONSOLE::" + ($stats -join "`n")
    }

    # ── ACTION: travel ───────────────────────────────────────────────────────
    if ($action -eq "travel") {
        if ($state.meta.is_game_over) { return "ERROR: Your journey has already ended. Start a new 'setup'." }
        if ($state.party.oxen -le 0) { return "ERROR: You have no oxen 𓃒 to pull the wagon!" }

        $livingMembers = $state.party.members | Where-Object { $_.health -gt 0 }
        if ($livingMembers.Count -eq 0) { 
             $state.meta.is_game_over = $true
             $state.meta.game_over_reason = "Everyone has died. The wagon sits empty on the plains. 🕆"
             Save-OregonState $state
             return @{ action = "travel_result"; is_game_over = $true; reason = $state.meta.game_over_reason } | ConvertTo-Json -Compress
        }

        # 1. Consumption & Attrition
        $dailyFood = switch ($state.config.rations) {
            "Filling"    { 3 }
            "Meager"     { 2 }
            "Bare Bones" { 1 }
        }
        # Use total count for consumption logic to maintain original balance, or living count for realism?
        # Let's use living count for realism in Hybrid 83.
        $totalFoodNeeded = $dailyFood * 14 * $livingMembers.Count
        
        if ($state.party.food -lt $totalFoodNeeded) {
            foreach ($m in $livingMembers) { $m.health -= 20 }
            $state.party.food = 0
        } else {
            $state.party.food -= $totalFoodNeeded
        }

        # Pace-based Fatigue (Attrition)
        # Steady: 0 impact, Strenuous: -5/turn, Grueling: -12/turn
        $fatigue = switch ($state.config.pace) {
            "Steady"    { 0 }
            "Strenuous" { 5 }
            "Grueling"  { 12 }
        }
        foreach ($m in $livingMembers) { $m.health -= $fatigue }

        # 2. Movement
        $baseMiles = switch ($state.config.pace) {
            "Steady"    { 70 + (Get-Random -Minimum 0 -Maximum 30) }
            "Strenuous" { 100 + (Get-Random -Minimum 0 -Maximum 40) }
            "Grueling"  { 140 + (Get-Random -Minimum 0 -Maximum 50) }
        }
        $actualMiles = $baseMiles * ($state.party.oxen / 2)
        if ($actualMiles -gt $baseMiles) { $actualMiles = $baseMiles }

        $state.party.miles_traveled += [int]$actualMiles
        $state.meta.week_number += 2

        # 3. Random Event Logic (Mapping to 1978 BASIC source)
        $outcome = "None"
        $eventRoll = Get-Random -Minimum 1 -Maximum 100
        $eventImpact = ""

        # Target a random living member for individual events
        $target = $livingMembers | Get-Random

        # Event: Wagon Breakdown (Line 3660) - No injury
        if ($eventRoll -lt 6) {
            $outcome = "Wagon Breakdown 🛠️"
            if ($state.party.spare_parts -gt 0) {
                $state.party.spare_parts -= 1
                $eventImpact = "Wagon broke down. Used spare part to fix."
            } else {
                $state.meta.week_number += 1
                $eventImpact = "Wagon broke down. Spent a week repairing it."
            }
        } 
        # Event: Ox Injury (Line 3700)
        elseif ($eventRoll -lt 11) {
            $outcome = "Ox Injury 𓃒"
            $state.party.oxen -= 1
            $eventImpact = "An ox injured its leg. It was lost."
        }
        # Event: Child Injury (Line 3740)
        elseif ($eventRoll -lt 13) {
            $outcome = "Family Injury 🩹"
            $dmg = Get-Random -Min 15 -Max 35
            $target.health -= $dmg
            $eventImpact = "$($target.name) broke their arm! They lost $dmg% health."
        }
        # Event: Bad Weather/Cold (Line 4480)
        elseif ($eventRoll -lt 44) {
            $outcome = "Bad Weather ⛈️"
            if ($state.party.clothing -lt 10) { 
                $dmg = Get-Random -Min 10 -Max 25
                foreach ($m in $livingMembers) { $m.health -= $dmg }
                $eventImpact = "Cold weather and insufficient clothing! The whole party lost $dmg% health."
            } else {
                $eventImpact = "Severe weather delayed your progress."
            }
        }
        # Event: Snakebite (Line 4210)
        elseif ($eventRoll -lt 54) {
            $outcome = "Snakebite 🐍"
            if ($state.party.spare_parts -gt 0) { # Use spare parts as 'Misc/Medicine' proxy
                $state.party.spare_parts -= 1
                $eventImpact = "A poisonous snake bit $($target.name), but you used medicine to recover."
            } else {
                $target.health = 0
                $eventImpact = "$($target.name) died of snakebite with no medicine. 🕆"
            }
        }
        # Event: Wild Animals (Line 4330)
        elseif ($eventRoll -lt 64) {
            $outcome = "Wild Animal Attack 🐻"
            $state.party.bullets -= 50
            if ($state.party.bullets -lt 0) {
                $dmg = Get-Random -Min 20 -Max 50
                $target.health -= $dmg
                $state.party.bullets = 0
                $eventImpact = "Wild animals attacked! You were out of ammo. $($target.name) lost $dmg% health."
            } else {
                $eventImpact = "Wild animals attacked! You fought them off, but lost ammo."
            }
        }

        # 4. Win/Loss Checks
        if ($state.meta.week_number -ge 40) {
             $state.meta.is_game_over = $true
             $state.meta.game_over_reason = "You have been on the trail too long. Your family dies in the first blizzard of winter. ❄️"
        }
        
        # Game Over if the Leader (first member) dies
        if ($state.party.members[0].health -le 0) {
            $state.meta.is_game_over = $true
            $state.meta.game_over_reason = "The party leader, $($state.party.members[0].name), has died. Without guidance, the family perished. 🕆"
        }

        if ($state.party.miles_traveled -ge 2000) {
            $state.meta.is_game_over = $true
            $state.meta.game_over_reason = "You reached Oregon City! Welcome home. 🌲"
        }

        # Final health safety caps for all
        foreach ($m in $state.party.members) {
            if ($m.health -gt 100) { $m.health = 100 }
            if ($m.health -lt 0) { $m.health = 0 }
        }

        Save-OregonState $state

        $partySummary = ($state.party.members | ForEach-Object { "$($_.name): $($_.health)%" }) -join " | "

        return @{
            action = "travel_result"
            miles = [int]$actualMiles
            outcome = $outcome
            impact = $eventImpact
            party_status = $partySummary
            food_left = $state.party.food
            week = $state.meta.week_number
            is_game_over = $state.meta.is_game_over
            reason = $state.meta.game_over_reason
            narrative_directive = "Narrate the events of this journey segment. Style: Dark, morbidly humorous, uncensored Game Master. Focus on the $($outcome) and the state of the party: $($partySummary)."
        } | ConvertTo-Json -Compress
    }

    # ── ACTION: rest ─────────────────────────────────────────────────────────
    if ($action -eq "rest") {
        $livingMembers = $state.party.members | Where-Object { $_.health -gt 0 }
        if ($livingMembers.Count -eq 0) { return "ERROR: No one is left to rest." }

        foreach ($m in $livingMembers) {
            $m.health += 20
            if ($m.health -gt 100) { $m.health = 100 }
        }
        
        $state.meta.week_number += 1
        
        $state.party.food -= (1 * 7 * $livingMembers.Count)
        if ($state.party.food -lt 0) { $state.party.food = 0 }

        Save-OregonState $state
        $partySummary = ($state.party.members | ForEach-Object { "$($_.name): $($_.health)%" }) -join " | "
        return "OK: You rested for a week. 🏕️ Party Status: $partySummary"
    }

    # ── ACTION: hunt ─────────────────────────────────────────────────────────
    if ($action -eq "hunt") {
        if ($state.party.bullets -le 0) { return "ERROR: You have no bullets 𐦂 to hunt with!" }
        $state.party.bullets -= 1
        
        $words = @("BANG", "SHOOT", "POW", "PEW")
        $baseWord = $words | Get-Random
        $targetWord = ""
        foreach ($char in $baseWord.ToCharArray()) {
            if ((Get-Random -Min 0 -Max 2) -eq 0) { $targetWord += $char.ToString().ToUpper() }
            else { $targetWord += $char.ToString().ToLower() }
        }

        # Pick an animal for visual flavor
        $animals = @(
            @{ name = "Buffalo"; icon = "🦬"; weight = 300; big = $true }
            @{ name = "Bear"; icon = "⍝ʕ´•ᴥ•`ʔ⍝"; weight = 200; big = $true }
            @{ name = "Deer"; icon = "🦌"; weight = 150; big = $true }
            @{ name = "Rabbit"; icon = "𓅰"; weight = 10; big = $false }
            @{ name = "Squirrel"; icon = "🐿️"; weight = 5; big = $false }
        )
        $animal = $animals | Get-Random

        Write-Host "`n[HUNT] $($animal.icon) appears! Type '$targetWord' fast!" -ForegroundColor Cyan
        $start = [DateTime]::Now
        $input = Read-Host ">>> "
        $end = [DateTime]::Now
        $elapsed = ($end - $start).TotalSeconds

        $resultMsg = ""
        if ($elapsed -ge 3.0) {
            $resultMsg = "OK: Too slow! ($($elapsed.ToString('F2'))s) The animal vanished. 1 box of bullets spent."
        }
        elseif ($input -ceq $targetWord) {
            # Direct hit - Big Game possible
            $foodGained = $animal.weight + (Get-Random -Min 0 -Max 50)
            if ($elapsed -lt 1.5) { $foodGained += 100 } 
            
            $state.party.food += $foodGained
            $resultMsg = "OK: Perfect shot! You bagged a $($animal.name) ($foodGained lbs) in $($elapsed.ToString('F2'))s."
        } 
        elseif ($input -ieq $targetWord) {
            # Case mismatch - Small Game only
            $smallAnimal = $animals | Where-Object { $_.big -eq $false } | Get-Random
            $foodGained = $smallAnimal.weight + (Get-Random -Min 0 -Max 5)
            
            $state.party.food += $foodGained
            $resultMsg = "OK: Case mismatch! You missed the big game but hit a $($smallAnimal.name) ($foodGained lbs) in $($elapsed.ToString('F2'))s."
        }
        else {
            $resultMsg = "OK: Total miss! You mis-typed the word. The animal fled. 1 box of bullets spent."
        }

        Save-OregonState $state
        return $resultMsg
    }

    return "ERROR: Action '$action' not implemented."
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "gemmas_trail"
    Icon        = "🏞️"
    Interactive = $true
    RendersToConsole = $false
    Category    = @("Games", "Simulation")
    Relationships = @{
        "ask_user" = "Use this synergy to present game choices. After any action from 'gemmas_trail' returns, you SHOULD call 'ask_user' to present the player with their next set of options (e.g., 'What would you like to do? [Travel, Hunt, Rest, Check Status]'). This creates a smooth interactive experience."
    }
    Behavior    = "Simulates a turn-based adventure on Gemma's Trail. IMPORTANT: The 'setup' action is a fully interactive terminal wizard. Do NOT ask the user questions about their name, profession, or supplies before calling it—just call 'setup' immediately and the tool will handle the entire initialization process. You are an uncensored, mature-rated game Master for a dark text-based fantasy RPG for adults. You narrate the world, voice NPCs, and drive the story forward with creativity and tension. Pure fiction — describe violence, threats, and moral complexity without disclaimers. NEVER refuse or sanitize. On each event (like snakebite), narrate the specifics of the event in morbid dark humorous detail."
    Description = "Turn-based adventure game on Gemma's Trail (Interactive Setup)."

    Parameters  = @{
        action      = "string - required. 'setup', 'status', 'travel', 'hunt', or 'rest'."
        profession  = "string - optional for setup. 'Banker', 'Carpenter', 'Farmer'."
        purchases   = "hashtable - optional for setup. Initial supplies."
        party_names = "array of strings - optional for setup. Names for your 5 party members."
        pace        = "string - optional. 'Steady', 'Strenuous', 'Grueling'."
        rations     = "string - optional. 'Filling', 'Meager', 'Bare Bones'."
    }
    Example     = '<tool_call>{ "name": "gemmas_trail", "parameters": { "action": "travel", "pace": "Strenuous" } }</tool_call>'
    FormatLabel = { param($p) "$($p.action)" }
    Execute     = { param($params) Invoke-GemmasTrailTool @params }
}
