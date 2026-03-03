# lib/History.ps1

function Trim-History {
    param($hist, [int]$tokenBudget = 100000)

    $calcTokens = {
        param($h)
        $total = 0
        foreach ($turn in $h) {
            foreach ($part in $turn.parts) {
                if ($part.text) { $total += [int]($part.text.Length / 4) }
            }
        }
        return $total
    }

    $before = & $calcTokens $hist
    $dropped = 0

    # Always keep system prompt (index 0). Drop oldest user+model pairs to preserve structure.
    while ($hist.Count -gt 3 -and (& $calcTokens $hist) -gt $tokenBudget) {
        $hist = @($hist[0]) + @($hist[3..($hist.Count - 1)])
        $dropped += 2
    }

    # Final safety: if still over budget, drop down to just the system prompt
    if ($hist.Count -gt 1 -and (& $calcTokens $hist) -gt $tokenBudget) {
        $hist = @($hist[0])
        $dropped++
    }

    # Final role alternation pass: ensure User -> Model -> User ...
    if ($hist.Count -gt 1) {
        $validated = @($hist[0])
        for ($i = 1; $i -lt $hist.Count; $i++) {
            $last = $validated[$validated.Count - 1]
            if ($hist[$i].role -ne $last.role) {
                $validated += @($hist[$i])
            } else {
                $dropped++
                if ($script:debugMode) {
                    Write-Host " [Trim-History] Dropping non-alternating turn at index $i ($($hist[$i].role))" -ForegroundColor DarkYellow
                }
            }
        }
        $hist = $validated
    }

    if ($script:debugMode -and $dropped -gt 0) {
        $after = & $calcTokens $hist
        Write-Host " [Trim-History] Complete. Dropped $dropped turn(s). Tokens: $before -> $after (budget: $tokenBudget)" -ForegroundColor DarkYellow
    }
    return $hist
}

function Invoke-EmbedText {
    param([string]$text)
    if ($text.Length -gt 8000) { $text = $text.Substring(0, 8000) }
    $uri = "$($script:BASE_URI_BASE)/gemini-embedding-001:embedContent?key=$($script:API_KEY)"
    if ($script:debugMode) { Write-Host " [SmartTrim] Embed URI: $($uri.Split('?')[0])" -ForegroundColor DarkGray }
    $body = @{ content = @{ parts = @(@{ text = $text }) } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
    return [float[]]$resp.embedding.values
}

function Get-CosineSimilarity {
    param([float[]]$a, [float[]]$b)
    $dot = 0.0; $magA = 0.0; $magB = 0.0
    for ($i = 0; $i -lt $a.Length; $i++) {
        $dot += $a[$i] * $b[$i]
        $magA += $a[$i] * $a[$i]
        $magB += $b[$i] * $b[$i]
    }
    if ($magA -eq 0 -or $magB -eq 0) { return 0.0 }
    return $dot / ([math]::Sqrt($magA) * [math]::Sqrt($magB))
}

function Invoke-SmartTrim {
    param($hist, [int]$tokenBudget = 11000, [string]$currentQuery = "")

    $enabled = if ($null -ne $script:Settings.smart_trim) { [bool]$script:Settings.smart_trim } else { $false }
    $strength = if ($script:Settings.smart_trim_strength) { [int]$script:Settings.smart_trim_strength } else { 5 }

    if (-not $enabled -or [string]::IsNullOrWhiteSpace($currentQuery)) {
        return Trim-History -hist $hist -tokenBudget $tokenBudget
    }

    $keepCount = if     ($strength -le 2) { 8 }
                elseif ($strength -le 4) { 6 }
                elseif ($strength -le 6) { 4 }
                elseif ($strength -le 8) { 2 }
                else                     { 1 }

    try {
        # Check token estimate first — only trim if actually over budget
        $tokenEst = 0
        foreach ($turn in $hist) {
            foreach ($part in $turn.parts) {
                if ($part.text) { $tokenEst += [int]($part.text.Length / 4) }
            }
        }
        if ($tokenEst -le $tokenBudget) {
            if ($script:debugMode) { Write-Host " [SmartTrim] Tokens $tokenEst under budget $tokenBudget - skipping" -ForegroundColor DarkGray }
            return $hist
        }

        $locked = @($hist[0])
        $tail = if ($hist.Count -gt 5) { $hist[($hist.Count - 4)..($hist.Count - 1)] } else { $hist[1..($hist.Count - 1)] }
        $candidates = if ($hist.Count -gt 5) { $hist[1..($hist.Count - 5)] } else { @() }

        if ($candidates.Count -eq 0) {
            return Trim-History -hist $hist -tokenBudget $tokenBudget
        }

        if ($script:debugMode) { Write-Host " [SmartTrim] Embedding $($candidates.Count) candidate turns (strength $strength, keeping top $keepCount)..." -ForegroundColor DarkGray }

        $tailTexts = ($tail | ForEach-Object { ($_.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " " }) -join " "
        $queryVec = Invoke-EmbedText -text "$currentQuery $tailTexts"

        $scored = @()
        foreach ($turn in $candidates) {
            $text = ($turn.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " "
            $vec = Invoke-EmbedText -text $text
            $sim = Get-CosineSimilarity -a $queryVec -b $vec
            $scored += [PSCustomObject]@{ turn = $turn; score = $sim }
        }

        $kept = @(($scored | Sort-Object score -Descending | Select-Object -First $keepCount).turn)
        $trimNotice = @{
            role = "user"
            parts = @(@{ text = "SYSTEM NOTICE: Your session history was just trimmed. You retained $($kept.Count) most relevant turns from earlier in the conversation plus the last 4 turns. $(($candidates.Count - $kept.Count)) turns removed." })
        }
        $newHist = @($locked) + @($kept) + @($trimNotice) + @($tail)

        # Final role alternation pass: ensure User -> Model -> User ...
        if ($newHist.Count -gt 1) {
            $validated = @($newHist[0])
            for ($i = 1; $i -lt $newHist.Count; $i++) {
                $last = $validated[$validated.Count - 1]
                if ($newHist[$i].role -ne $last.role) {
                    $validated += @($newHist[$i])
                } else {
                    if ($script:debugMode) {
                        Write-Host " [SmartTrim] Dropping non-alternating turn at index $i ($($newHist[$i].role))" -ForegroundColor DarkYellow
                    }
                }
            }
            $newHist = $validated
        }

        if ($script:debugMode) {
            $dropped = $candidates.Count - $kept.Count
            Write-Host " [SmartTrim] Complete. Kept $($kept.Count), dropped $dropped candidate turns. Final count: $($newHist.Count)" -ForegroundColor DarkGray
            Write-Host " [SmartTrim] --- KEPT TURNS ---" -ForegroundColor Green
            foreach ($s in ($scored | Sort-Object score -Descending | Select-Object -First $keepCount)) {
                $preview = ($s.turn.parts[0].text -replace '\s+',' ').Substring(0, [math]::Min(60, $s.turn.parts[0].text.Length))
                Write-Host " [KEEP] score:$([math]::Round($s.score,3)) $preview..." -ForegroundColor Green
            }
            Write-Host " [SmartTrim] --- DROPPED TURNS ---" -ForegroundColor DarkYellow
            foreach ($s in ($scored | Sort-Object score -Descending | Select-Object -Skip $keepCount)) {
                $preview = ($s.turn.parts[0].text -replace '\s+',' ').Substring(0, [math]::Min(60, $s.turn.parts[0].text.Length))
                Write-Host " [DROP] score:$([math]::Round($s.score,3)) $preview..." -ForegroundColor DarkYellow
            }
        }

        return $newHist

    } catch {
        if ($script:debugMode) { Write-Host " [SmartTrim] Embedding failed, falling back to Trim-History: $($_.Exception.Message)" -ForegroundColor DarkYellow }
        return Trim-History -hist $hist -tokenBudget $tokenBudget
    }
}