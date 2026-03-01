# =========================================================================================
# SCRIPT INITIALIZATION
# =========================================================================================

# 1. Define Script Directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
# Ensure UTF-8 output for emoji and Unicode rendering
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 2. Source All Library Modules
. (Join-Path $scriptDir "lib/ToolLoader.ps1")
. (Join-Path $scriptDir "lib/Api.ps1")
. (Join-Path $scriptDir "lib/UI.ps1")

# 3. Define Core Constants & Functions
# ====================== MODEL REGISTRY ======================
$script:MODEL_REGISTRY = [ordered]@{
    "3-27b"   = @{ id = "gemma-3-27b-it";    label = "Gemma 3 27B";    desc = "Heavy logic & reasoning  (default)" }
    "3-12b"   = @{ id = "gemma-3-12b-it";    label = "Gemma 3 12B";    desc = "Balanced speed / performance" }
    "3-4b"    = @{ id = "gemma-3-4b-it";     label = "Gemma 3 4B";     desc = "Fast multimodal tasks" }
    "3-1b"    = @{ id = "gemma-3-1b-it";     label = "Gemma 3 1B";     desc = "Tiny text-only routing" }
    "3n-e4b"  = @{ id = "gemma-3n-e4b-it";   label = "Gemma 3n E4B";   desc = "High-fidelity multimodal reasoning" }
    "3n-e2b"  = @{ id = "gemma-3n-e2b-it";   label = "Gemma 3n E2B";   desc = "Ultra-low latency" }
}

function Resolve-ModelId {
    param([string]$Choice)
    $c = $Choice.Trim().ToLower()
    if ($script:MODEL_REGISTRY.Contains($c)) { return $script:MODEL_REGISTRY[$c].id }
    foreach ($entry in $script:MODEL_REGISTRY.Values) { if ($entry.id -eq $c) { return $entry.id } }
    Write-Warning "Unknown model '$Choice'. Defaulting to gemma-3-27b-it."
    return "gemma-3-27b-it"
}

function ConvertTo-Hashtable {
    param($Object)
    $hash = @{}
    if ($null -eq $Object) { return $hash }
    foreach ($prop in $Object.PSObject.Properties) {
        $hash[$prop.Name] = $prop.Value
    }
    return $hash
}

$script:MODEL    = "gemma-3-27b-it"
$script:BASE_URI_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

function Get-BaseUri { return "$($script:BASE_URI_BASE)/$($script:MODEL):generateContent" }

# ====================== UNICODE CHARS ======================
$TL = [char]0x256D; $TR = [char]0x256E; $BL = [char]0x2570; $BR = [char]0x256F
$H = [char]0x2500;  $V = [char]0x2502;  $ARR = [char]0x2192; $CHK = [char]0x2713
$CRS = [char]0x2717; $DOT = [char]0x25CF; $BUL = [char]0x2022; $BLK = [char]0x2588
$LBK = [char]0x2591

$script:TOOL_LIMITS = @{
    "gemma-3-27b-it" = 12
    "gemma-3-12b-it" = 8
    "gemma-3-4b-it"  = 2
    "gemma-3n-e4b-it" = 2
    "gemma-3n-e2b-it" = 2
    "gemma-3-1b-it"  = 0
}

# ====================== DEBUG =======================
$script:debugMode = $false


# 4. Load API Key (Requires UI functions for Draw-Box)
# ====================== SECURE API KEY STORAGE ======================
$configDir  = Join-Path $env:APPDATA "GemmaCLI"
$configFile = Join-Path $configDir "apikey.xml"

function Get-SavedApiKey {
    if (Test-Path $configFile) {
        try {
            $secureString = Import-Clixml -Path $configFile
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        } catch { }
    }
    return $null
}

function Save-ApiKey {
    param([string]$apiKey)
    if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }
    $secureString = ConvertTo-SecureString $apiKey -AsPlainText -Force
    $secureString | Export-Clixml -Path $configFile
    Draw-Box @("$CHK  API key saved securely (Windows user-only encryption)") -Color Green
}

# ====================== LOAD API KEY ======================
$API_KEY = $env:GEMMA_API_KEY
if (-not $API_KEY) { $API_KEY = Get-SavedApiKey }
if (-not $API_KEY) {
    Write-Host "`n=== First-time setup ===" -ForegroundColor Cyan
    Write-Host "Get your free Gemma API key here:" -ForegroundColor Yellow
    Write-Host "https://aistudio.google.com/app/apikey`n" -ForegroundColor Gray
    do {
        $secureInput = Read-Host "Enter your API key" -AsSecureString
        $plainKey    = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput))
        $confirm = Read-Host "Confirm API key (paste again)"
        if ($plainKey -ne $confirm) { Write-Host "$CRS  Keys do not match. Try again." -ForegroundColor Red }
        elseif ([string]::IsNullOrWhiteSpace($plainKey)) { Write-Host "$CRS  API key cannot be empty." -ForegroundColor Red }
    } while ($plainKey -ne $confirm -or [string]::IsNullOrWhiteSpace($plainKey))
    Save-ApiKey $plainKey
    $API_KEY = $plainKey
} else {
    Write-Host "$CHK  API key loaded successfully" -ForegroundColor DarkGray
}
$script:API_KEY = $API_KEY
function Get-ApiUri { return "$(Get-BaseUri)?key=$($script:API_KEY)" }


# 5. Load Intelligence File
# ====================== LOAD INTELLIGENCE ======================
$configPath = Join-Path $scriptDir "instructions.json"
$intelligence = try {
    if (Test-Path $configPath) {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($null -eq $json.system_prompt) { throw "Invalid JSON structure" }
        $json
    } else { throw "File not found" }
} catch {
    [PSCustomObject]@{
        system_prompt = "You are Gemma, a helpful assistant."
        guardrails = @{ max_output_tokens = 8192; temperature = 0.7; top_p = 0.95 }
    }
}

# 6. Define Remaining Script Variables
# ====================== GUARDRAILS & STATUS ======================
$script:GUARDRAILS = @{ 
    maxOutputTokens = if ($intelligence.guardrails.max_output_tokens) { [int]$intelligence.guardrails.max_output_tokens } else { 8192 }; 
    temperature = if ($intelligence.guardrails.temperature) { [float]$intelligence.guardrails.temperature } else { 0.7 }; 
    topP = if ($intelligence.guardrails.top_p) { [float]$intelligence.guardrails.top_p } else { 0.95 } 
}
# $CONTEXT_WINDOW = 128000
$script:lastStatus   = @{ prompt = 0; candidate = 0; total = 0; finish = "" }
$script:lastApiCall        = (Get-Date).AddSeconds(-10)   # main loop Gemma calls
$script:lastApiCall_Gemini = (Get-Date).AddSeconds(-10)   # dual-agent Gemini calls
$script:apiCallLog_Gemma   = [System.Collections.Generic.List[datetime]]::new()  # Gemma RPM tracker
$script:apiCallLog_Gemini  = [System.Collections.Generic.List[datetime]]::new()  # Gemini RPM tracker (separate quota)

# ====================== SYSTEM PROMPT ======================
function Get-SystemPrompt {
    if (-not $intelligence.system_prompts) { return $intelligence.system_prompt }
    $specific = $intelligence.system_prompts.PSObject.Properties[$script:MODEL]
    if ($specific) { return $specific.Value }
    return $intelligence.system_prompt
}

# ====================== RATE LIMITING ======================
function Invoke-RpmCheck {
    param([string]$backend = "gemma")
    # Gemini Flash free tier: 15 RPM. Gemma 27B/12B: 2 RPM. Others: 5 RPM.
    $rpm         = if ($backend -eq "gemini") { 15 } elseif ($script:MODEL -in @("gemma-3-27b-it","gemma-3-12b-it")) { 2 } else { 5 }
    $windowStart = (Get-Date).AddSeconds(-60)

    if ($backend -eq "gemini") {
        $script:apiCallLog_Gemini.RemoveAll([Predicate[datetime]]{ param($t) $t -lt $windowStart }) | Out-Null
        $count  = $script:apiCallLog_Gemini.Count
        $oldest = if ($count -gt 0) { $script:apiCallLog_Gemini[0] } else { $null }
    } else {
        $script:apiCallLog_Gemma.RemoveAll([Predicate[datetime]]{ param($t) $t -lt $windowStart }) | Out-Null
        $count  = $script:apiCallLog_Gemma.Count
        $oldest = if ($count -gt 0) { $script:apiCallLog_Gemma[0] } else { $null }
    }

    if ($count -ge $rpm -and $null -ne $oldest) {
        $waitSec = [math]::Ceiling(60 - ((Get-Date) - $oldest).TotalSeconds) + 1
        if ($waitSec -gt 0) {
            if ($script:debugMode) {
                Stop-Spinner
                Draw-Box @("  [$backend] Rate limit: $count/$rpm RPM reached. Waiting $waitSec seconds...") -Color Yellow
                Start-Sleep -Seconds $waitSec
                Start-Spinner -Label "Resuming..."
            } else {
                Write-Host " [Rate limit ($backend): waiting $waitSec seconds...]" -ForegroundColor DarkGray
                Start-Sleep -Seconds $waitSec
            }
        }
    }

    if ($backend -eq "gemini") {
        $script:apiCallLog_Gemini.Add((Get-Date))
    } else {
        $script:apiCallLog_Gemma.Add((Get-Date))
    }
}

# ====================== RETRY WRAPPER ======================
function Invoke-GemmaApiWithRetry {
    param($uri, [ref]$historyRef, $gConfig)
    $delays = @(5, 30, 60)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $resp = Invoke-GemmaApi -uri $uri -history $historyRef.Value -gConfig $gConfig
        # Pass through cancellation and non-quota errors immediately
        if ($resp.cancelled) { return $resp }
        if ($resp.apiError) {
            $isQuota = $resp.apiError -match "429|quota|RESOURCE_EXHAUSTED"
            if (-not $isQuota -or $attempt -eq 2) { return $resp }

            # On first quota failure: check token count and trim if over 11K
            Stop-Spinner
            if ($attempt -eq 0) {
                $tokenEst = 0
                foreach ($turn in $historyRef.Value) {
                    foreach ($part in $turn.parts) {
                        if ($part.text) { $tokenEst += [int]($part.text.Length / 4) }
                    }
                }
                if ($tokenEst -gt 11000) {
                    if ($script:debugMode) { Write-Host " [Retry] Token estimate $tokenEst > 11000 - trimming before retry" -ForegroundColor DarkYellow }
                    $historyRef.Value = Trim-History -hist $historyRef.Value -tokenBudget 11000
                }
            }

            $wait = $delays[$attempt]
            Write-Host ""
            Draw-Box @("$CRS  Quota error (attempt $($attempt+1)/3). Retrying in $wait seconds...") -Color Yellow
            Start-Sleep -Seconds $wait
            Start-Spinner -Label "Gemma is thinking (Esc to cancel)"
            continue
        }
        return $resp
    }
    return $resp
}

# ====================== HISTORY TRIM ======================
function Trim-History {
    param([array]$hist, [int]$tokenBudget = 100000)
    # Estimate tokens: sum all text lengths / 4
    $calcTokens = {
        param([array]$h)
        $total = 0
        foreach ($turn in $h) {
            foreach ($part in $turn.parts) {
                if ($part.text) { $total += [int]($part.text.Length / 4) }
            }
        }
        return $total
    }
    $before  = & $calcTokens $hist
    $dropped = 0
    # Always keep index 0 (system prompt). Trim from index 1 onward.
    while ($hist.Count -gt 2 -and (& $calcTokens $hist) -gt $tokenBudget) {
        $hist = @($hist[0]) + $hist[2..($hist.Count - 1)]
        $dropped++
    }
    if ($script:debugMode -and $dropped -gt 0) {
        $after = & $calcTokens $hist
        Write-Host " [Trim-History] Blind trim fired: dropped $dropped turn(s). Tokens: $before -> $after (budget: $tokenBudget)" -ForegroundColor DarkYellow
    }
    return $hist
}

# ====================== SMART TRIM ======================
function Invoke-EmbedText {
    param([string]$text)
    if ($text.Length -gt 8000) { $text = $text.Substring(0, 8000) }
    $uri   = "$($script:BASE_URI_BASE)/gemini-embedding-001:embedContent?key=$($script:API_KEY)"
    if ($script:debugMode) { Write-Host " [SmartTrim] Embed URI: $($uri.Split('?')[0])" -ForegroundColor DarkGray }
    $body  = @{ content = @{ parts = @(@{ text = $text }) } } | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp  = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
    return [float[]]$resp.embedding.values
}

function Get-CosineSimilarity {
    param([float[]]$a, [float[]]$b)
    $dot = 0.0; $magA = 0.0; $magB = 0.0
    for ($i = 0; $i -lt $a.Length; $i++) {
        $dot  += $a[$i] * $b[$i]
        $magA += $a[$i] * $a[$i]
        $magB += $b[$i] * $b[$i]
    }
    if ($magA -eq 0 -or $magB -eq 0) { return 0.0 }
    return $dot / ([math]::Sqrt($magA) * [math]::Sqrt($magB))
}

function Invoke-SmartTrim {
    param([array]$hist, [int]$tokenBudget = 11000, [string]$currentQuery = "")

    $enabled  = if ($null -ne $script:Settings.smart_trim) { [bool]$script:Settings.smart_trim } else { $false }
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

        $locked     = @($hist[0])
        $tail       = if ($hist.Count -gt 5) { $hist[($hist.Count - 4)..($hist.Count - 1)] } else { $hist[1..($hist.Count - 1)] }
        $candidates = if ($hist.Count -gt 5) { $hist[1..($hist.Count - 5)] } else { @() }

        if ($candidates.Count -eq 0) {
            return Trim-History -hist $hist -tokenBudget $tokenBudget
        }

        if ($script:debugMode) { Write-Host " [SmartTrim] Embedding $($candidates.Count) candidate turns (strength $strength, keeping top $keepCount)..." -ForegroundColor DarkGray }

        $queryVec = Invoke-EmbedText -text $currentQuery

        $scored = @()
        foreach ($turn in $candidates) {
            $text = ($turn.parts | Where-Object { $_.text } | ForEach-Object { $_.text }) -join " "
            $vec  = Invoke-EmbedText -text $text
            $sim  = Get-CosineSimilarity -a $queryVec -b $vec
            $scored += [PSCustomObject]@{ turn = $turn; score = $sim }
        }

        $kept    = @(($scored | Sort-Object score -Descending | Select-Object -First $keepCount).turn)

        $dropped = $candidates.Count - $kept.Count
        $trimNotice = @{
            role  = "user"
            parts = @(@{ text = "SYSTEM NOTICE: Your session history was just trimmed. You retained $($kept.Count) most relevant turns from earlier in the conversation plus the last 4 turns. $dropped turns removed." })
        }
        $newHist = $locked + $kept + @($trimNotice) + $tail

        if ($script:debugMode) {
            Write-Host " [SmartTrim] Complete. Kept $($kept.Count), dropped $dropped candidate turns" -ForegroundColor DarkGray
            Write-Host " [SmartTrim] --- KEPT TURNS ---" -ForegroundColor Green
            foreach ($s in ($scored | Sort-Object score -Descending | Select-Object -First $keepCount)) {
                $preview = ($s.turn.parts[0].text -replace '\s+',' ').Substring(0, [math]::Min(60, $s.turn.parts[0].text.Length))
                Write-Host "  [KEEP] score:$([math]::Round($s.score,3))  $preview..." -ForegroundColor Green
            }
            Write-Host " [SmartTrim] --- DROPPED TURNS ---" -ForegroundColor DarkYellow
            foreach ($s in ($scored | Sort-Object score -Descending | Select-Object -Skip $keepCount)) {
                $preview = ($s.turn.parts[0].text -replace '\s+',' ').Substring(0, [math]::Min(60, $s.turn.parts[0].text.Length))
                Write-Host "  [DROP] score:$([math]::Round($s.score,3))  $preview..." -ForegroundColor DarkYellow
            }
        }

        return $newHist

    } catch {
        if ($script:debugMode) { Write-Host " [SmartTrim] Embedding failed, falling back to Trim-History: $($_.Exception.Message)" -ForegroundColor DarkYellow }
        return Trim-History -hist $hist -tokenBudget $tokenBudget
    }
}

# ====================== API CALL LOGGER ======================
function Write-ApiLog {
    param([string]$toolName = "chat")
    $logFile = Join-Path $configDir "gemma_cli.log"
    $s = $script:lastStatus
    $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}" -f `
        (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), `
        $script:MODEL, `
        $toolName, `
        $s.prompt, `
        $s.candidate, `
        $s.total, `
        $s.finish
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# ====================== DUAL-AGENT (bigBrother / littleSister) ======================

function Get-GeminiUri {
    # Gemini 2.5 Flash — free tier, same v1beta endpoint and API key as Gemma
    return "$($script:BASE_URI_BASE)/gemini-2.5-flash:generateContent?key=$($script:API_KEY)"
}

function Invoke-SingleTurnApi {
    param([string]$uri, [string]$prompt, [string]$spinnerLabel = "Thinking...", [string]$backend = "gemma")
    Invoke-RpmCheck -backend $backend

    # 2-second gap enforced per backend independently — switching backends never triggers a wait
    if ($backend -eq "gemini") {
        $elapsed = ((Get-Date) - $script:lastApiCall_Gemini).TotalMilliseconds
        if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        $script:lastApiCall_Gemini = Get-Date
    } else {
        $elapsed = ((Get-Date) - $script:lastApiCall).TotalMilliseconds
        if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        $script:lastApiCall = Get-Date
    }

    $body = @{
        contents         = @(@{ role = "user"; parts = @(@{ text = $prompt }) })
        generationConfig = @{ maxOutputTokens = 4096; temperature = 0.7; topP = 0.95 }
    } | ConvertTo-Json -Depth 10 -Compress

    # Send as UTF-8 bytes to match Invoke-GemmaApi encoding behaviour
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    Start-Spinner -Label $spinnerLabel
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
        Stop-Spinner
        return $resp.candidates[0].content.parts[0].text.Trim()
    } catch {
        Stop-Spinner
        # Extract actual API error message from response stream
        $detail = ""
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $raw    = $reader.ReadToEnd()
            $json   = $raw | ConvertFrom-Json
            $detail = if ($json.error.message) { $json.error.message } else { $raw }
        } catch {}
        $msg = if ($detail) { $detail } else { $_.Exception.Message }
        return "ERROR: $msg"
    }
}

function Invoke-DualAgent {
    param(
        [string]$query,
        [string]$mode   # "bigBrother" or "littleSister"
    )

    # Compact context snapshot — last 3 user turns for Gemma's correction pass
    $contextSummary = "CURRENT SESSION CONTEXT:`n"
    $contextSummary += "Active model: $script:MODEL`n"
    $contextSummary += "Recent conversation turns: $([math]::Max(0, $history.Count - 1))`n"
    $recentTurns = $history | Select-Object -Last 6 | Where-Object { $_.role -eq "user" } | Select-Object -Last 3
    foreach ($turn in $recentTurns) {
        $preview = $turn.parts[0].text
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + "..." }
        $contextSummary += "  - $preview`n"
    }

    $geminiUri = Get-GeminiUri
    $gemmaUri  = Get-ApiUri

    if ($mode -eq "bigBrother") {
        Write-Host ""
        Draw-Box @("$BUL  bigBrother mode  $BUL  Gemini $ARR Gemma $ARR Gemini") -Color Cyan

        # Round 1: Gemini answers with limited context

        $lastTurn = ($history | Select-Object -Last 3 | Where-Object { $_.role -ne "user" -or $_.parts[0].text -notmatch '^/bigBrother' } | ForEach-Object { $_.parts[0].text }) -join "`n"

        $geminiAnswer = Invoke-SingleTurnApi `
            -uri $geminiUri `
            -prompt "You are Gemini, Gemma's brother, an AI assistant participating in a dual-agent pipeline with Gemma. You are being consulted for your broad knowledge on this query.`nRECENT CONTEXT:`n$lastTurn`nQUERY: $query" `
            -spinnerLabel "Gemini Flash answering (Round 1)..." `
            -backend "gemini"

        if ($geminiAnswer -like "ERROR:*") {
            Draw-Box @("$CRS  Gemini failed: $geminiAnswer") -Color Red
            return
        }

        # Round 2: Gemma reviews Gemini's answer with full session context
        # No rate limit wait needed — switching from Gemini to Gemma quota bucket
        $gemmaReviewPrompt = @"
$contextSummary

A query was sent to an external AI (Gemini Flash) that has NO knowledge of our session context.
The query was: "$query"

Gemini's answer:
---
$geminiAnswer
---

Your task:
1. Identify any parts of Gemini's answer that don't apply to THIS session's context (wrong language, wrong framework, wrong OS, etc.)
2. Add any session-specific corrections or additions
3. Keep what's correct — only flag what's contextually wrong or missing
Be concise. Format as: CORRECTIONS: [your notes] or CONFIRMED: [if Gemini was fully correct]
"@
        $gemmaCorrection = Invoke-SingleTurnApi `
            -uri $gemmaUri `
            -prompt $gemmaReviewPrompt `
            -spinnerLabel "Gemma contextualizing (Round 2)..." `
            -backend "gemma"

        # Round 3: Gemini synthesizes with Gemma's corrections
        # No rate limit wait needed — switching back to Gemini quota bucket
        $finalPrompt = @"
You previously answered this query: "$query"

Your answer:
---
$geminiAnswer
---

A context-aware AI reviewed your answer and provided these notes:
---
$gemmaCorrection
---

Provide a final improved answer incorporating these corrections. Keep what was correct, fix what wasn't. Be direct.
"@
        $finalAnswer = Invoke-SingleTurnApi `
            -uri $geminiUri `
            -prompt $finalPrompt `
            -spinnerLabel "Gemini synthesizing final answer (Round 3)..." `
            -backend "gemini"

        Write-Host ""
        Draw-Box @("Gemini Flash  (raw answer)") -Color DarkCyan
        Write-Host " $geminiAnswer" -ForegroundColor DarkCyan
        Write-Host ""
        Draw-Box @("Gemma  (context corrections)") -Color Magenta
        Write-Host " $gemmaCorrection" -ForegroundColor Magenta
        Write-Host ""
        Draw-Box @("Gemini Flash  (final synthesis)") -Color Cyan
        Write-Host " $finalAnswer" -ForegroundColor Cyan
        Write-Host ""

        $script:history = $history + @(
            @{ role = "user";  parts = @(@{ text = $query }) },
            @{ role = "model"; parts = @(@{ text = "[bigBrother synthesis] $finalAnswer" }) }
        )
        $history = $script:history

    } elseif ($mode -eq "littleSister") {
        Write-Host ""
        Draw-Box @("$BUL  littleSister mode  $BUL  Gemma $ARR Gemini $ARR Gemma") -Color Magenta

        # Round 1: Gemma answers with full session context
        $gemmaFirstPrompt = @"
$contextSummary

The user asks: $query

Answer based on everything you know about this session. Be thorough.
"@
        $gemmaAnswer = Invoke-SingleTurnApi `
            -uri $gemmaUri `
            -prompt $gemmaFirstPrompt `
            -spinnerLabel "Gemma answering with context (Round 1)..." `
            -backend "gemma"

        # Round 2: Gemini expands — no rate limit wait switching to Gemini bucket
        $geminiExpandPrompt = @"
A context-aware AI assistant answered the query "$query":
---
$gemmaAnswer
---

Using your broader knowledge base:
1. Confirm what is correct
2. Add important missing information
3. Suggest better approaches if applicable
Be direct and additive — do not repeat what is already correct.
"@
        $geminiExpansion = Invoke-SingleTurnApi `
            -uri $geminiUri `
            -prompt $geminiExpandPrompt `
            -spinnerLabel "Gemini expanding with broad knowledge (Round 2)..." `
            -backend "gemini"

        # Round 3: Gemma synthesizes — no rate limit wait switching back to Gemma bucket
        $gemmaSynthesisPrompt = @"
$contextSummary

Original query: "$query"

Your initial answer:
---
$gemmaAnswer
---

Gemini Flash additions:
---
$geminiExpansion
---

Produce a final unified answer combining your session-specific knowledge with Gemini's additions. Prioritize session context where they conflict.
"@
        $finalAnswer = Invoke-SingleTurnApi `
            -uri $gemmaUri `
            -prompt $gemmaSynthesisPrompt `
            -spinnerLabel "Gemma synthesizing final answer (Round 3)..." `
            -backend "gemma"

        Write-Host ""
        Draw-Box @("Gemma  (context-aware answer)") -Color Magenta
        Write-Host " $gemmaAnswer" -ForegroundColor Magenta
        Write-Host ""
        Draw-Box @("Gemini Flash  (broad knowledge expansion)") -Color DarkCyan
        Write-Host " $geminiExpansion" -ForegroundColor DarkCyan
        Write-Host ""
        Draw-Box @("Gemma  (final synthesis)") -Color Green
        Write-Host " $finalAnswer" -ForegroundColor Green
        Write-Host ""

        $script:history = $history + @(
            @{ role = "user";  parts = @(@{ text = $query }) },
            @{ role = "model"; parts = @(@{ text = "[littleSister synthesis] $finalAnswer" }) }
        )
        $history = $script:history
    }
}

$toolBlock = Get-ToolInstructions -ScriptRoot $scriptDir -Model $script:MODEL -ToolLimits $script:TOOL_LIMITS
$systemPrompt = Get-SystemPrompt
$systemPrompt = $systemPrompt -replace "%%AVAILABLE_TOOLS%%", $toolBlock
$systemPrompt = "SYSTEM: Current date and time: $(Get-Date -Format 'dddd, MMMM dd yyyy HH:mm')`n`n" + $systemPrompt
$script:systemPrompt = $systemPrompt
$history = @( @{ role = "user"; parts = @(@{ text = $systemPrompt }) } )


# ====================== LOAD MEMORY ======================
$appDataGemma = Join-Path $env:APPDATA "GemmaCLI"
$memoryFile   = Join-Path $appDataGemma "memory.json"

# ====================== LOAD CUSTOM COMMANDS ======================
$customCommandsPath = Join-Path $scriptDir "config/custom_commands.json"
$script:customCommands = @{}
if (Test-Path $customCommandsPath) {
    $jsonObject = Get-Content -Path $customCommandsPath | ConvertFrom-Json
    $hashtable = @{}
    if ($jsonObject) {
        foreach ($property in $jsonObject.PSObject.Properties) {
            $hashtable[$property.Name] = $property.Value
        }
    }
    $script:customCommands = $hashtable
}

# ====================== COLOR SCHEMES ======================
$script:DefaultColors = @{
    input_highlight = "DarkMagenta"
    input_text      = "Gray"
    gemma_response  = "Green"
    ui_boxes        = "Cyan"
    system_status   = "Cyan"
    user_label      = "Gray"
    custom_command  = "Magenta"
}

$script:AlternativeColors = @{
    input_highlight = "DarkBlue"
    input_text      = "White"
    gemma_response  = "Yellow"
    ui_boxes        = "Cyan"
    system_status   = "Cyan"
    user_label      = "White"
    custom_command  = "Cyan"
}

# ====================== LOAD SETTINGS ======================
$settingsPath = Join-Path $scriptDir "config/settings.json"
$script:Settings = if (Test-Path $settingsPath) { Get-Content $settingsPath | ConvertFrom-Json } else { @{} }
$scheme = if ($script:Settings.color_scheme) { $script:Settings.color_scheme } else { "default" }

if ($scheme -eq "alternative") {
    $script:Colors = $script:AlternativeColors
} else {
    $script:Colors = $script:DefaultColors
}

# ====================== SPLASH ======================
$startupDelay = if ($script:Settings.startup_delay) { [int]$script:Settings.startup_delay } else { 0 }
if ($startupDelay -gt 0) { Start-Sleep -Seconds $startupDelay }
Clear-Host
Write-Host ""
Write-Host "  .oooooo.   oooooooooooo ooo        ooooo ooo        ooooo      .o.       " -ForegroundColor Magenta
Write-Host " d8P'  'Y8b  '888'     '8 '88.       .888' '88.       .888'     .888.      " -ForegroundColor Magenta
Write-Host "888           888          888b     d'888   888b     d'888      .8'888.     " -ForegroundColor Magenta
Write-Host "888           888oooo8     8 Y88. .P  888   8 Y88. .P  888     .8' '888.   " -ForegroundColor Magenta
Write-Host "888     ooooo 888    '     8  '888'   888   8  '888'   888    .88ooo8888.  " -ForegroundColor Magenta
Write-Host "'88.    .88'  888       o  8    Y     888   8    Y     888   .8'     '888. " -ForegroundColor Magenta
Write-Host " 'Y8bood8P'  o888ooooood8 o8o        o888o o8o        o888o o88o     o8888o" -ForegroundColor Magenta
Write-Host ""

$helpLines = @(
    "/help              $ARR Show all commands",
    "/clear             $ARR Reset conversation",
    "/recall            $ARR Load memories from previous sessions",
    "/multiline         $ARR Multiline mode - end with /end",
    "/model [id]        $ARR Switch model / pass id directly",
    "/tools             $ARR Show available tools",
    "/settings          $ARR Manage system settings",
    "/customCommand     $ARR List/Create your custom commands",
    "/bigBrother [q]    $ARR Dual model pipeline, Gemini > Gemma > Gemini",
    "/littleSister [q]  $ARR Dual model pipeline, Gemma > Gemini > Gemma",
    "/debug             $ARR Toggle debug output",
    "/resetkey          $ARR Delete saved key & re-prompt",
    "exit               $ARR Quit"
)

Draw-Box $helpLines -Title "Gemma CLI v0.4.6 $BUL (C) 2026 SpdrByte Labs $BUL AGPL-3.0 License" -Width 80 -Color $script:Colors.ui_boxes

Write-Host ""

# ====================== MAIN LOOP ======================
while ($true) {
    # Dark Purple Entire Row Highlight for Input
    $esc = [char]27
    # Map friendly color names to ANSI if needed, but for now we'll stick to basic colors or keep the purple logic
    # The requirement was "don't reuse same colors", so let's use the scheme's highlight
    $bgRGB = if ($scheme -eq "alternative") { "0;0;100" } else { "40;0;40" } 
    $highlightColor = "$esc[48;2;$($bgRGB)m" 
    $reset = "$esc[0m"

    # Write the row start and header
    Write-Host "$highlightColor$($esc)[K You " -NoNewline -ForegroundColor $script:Colors.user_label
    
    # 1. Print bar AFTER user prompt line always.
    $startX = [Console]::CursorLeft
    $startY = [Console]::CursorTop
    
    # Ensure there is a line below for the bar if we are at the bottom
    if ($startY -ge ([Console]::BufferHeight - 1)) {
        [Console]::WriteLine()
        $startY--
        [Console]::SetCursorPosition($startX, $startY)
    }

    $barRow = $startY + 1
    [Console]::SetCursorPosition(0, $barRow)
    $text = Get-StatusBarText
    $w = [Console]::WindowWidth
    $paddedText = if ($text.Length -gt ($w - 1)) { $text.Substring(0, $w - 1) } else { $text.PadRight($w - 1) }
    Write-Host $paddedText -ForegroundColor $script:Colors.system_status -BackgroundColor DarkBlue -NoNewline
    
    # Return cursor to prompt position for user to type
    [Console]::SetCursorPosition($startX, $startY)

    # Start polling tracker — moves bar down if user input wraps to new line
    Start-BarTracker -InitialBarRow $barRow -HighlightANSI $highlightColor

    # Use the ANSI code as a prefix for Read-Host to keep the background purple while typing
    $userInput = Read-Host "$highlightColor"

    $endY = [Console]::CursorTop
    Write-Host -NoNewline $reset # Reset immediately after enter

    # Stop tracker, get final bar row, erase it
    Stop-BarTracker
    $finalBarRow = $script:barRow
    if ($finalBarRow -lt [Console]::BufferHeight) {
        [Console]::SetCursorPosition(0, $finalBarRow)
        Write-Host (" " * ($w - 1)) -NoNewline
        [Console]::SetCursorPosition(0, $endY)
    }

    if ($userInput -eq "exit") { break }


     if ($userInput -eq "/multiline") {
        $pastelines =@()
        Write-Host "Multiline mode - [end with /end on its own line]" -ForegroundColor DarkGray
        while ($true) {
            $pasteline = Read-Host
            if ($pasteline -eq "/end") { break }
            $pastelines += $pasteline
        }
        $userInput = $pastelines -join "`n"
    }


    if ($userInput -eq "/clear") {
        $history = @($history[0])
        Draw-Box @("$CHK  Conversation cleared.") -Color Yellow
        continue
    }

    if ($userInput -eq "/debug") {
        $script:debugMode = -not $script:debugMode
        $state = if ($script:debugMode) { "ON" } else { "OFF" }
        Draw-Box @("$CHK  Debug mode $state") -Color Yellow
        continue
    }

    if ($userInput -eq "/help") {
        Draw-Box $helpLines -Title "Gemma CLI  $BUL  Help" -Width 80 -Color $script:Colors.ui_boxes
        continue
    }


    if ($userInput -eq "/recall") {
        if (-not (Test-Path $memoryFile)) {
            Draw-Box @("$CRS  No memory file found. Ask Gemma to remember something first.") -Color Yellow
            continue
        }

        try {
            $raw      = Get-Content $memoryFile -Raw -Encoding UTF8
            $memories = $raw | ConvertFrom-Json

            if (-not $memories -or $memories.Count -eq 0) {
                Draw-Box @("$CRS  Memory file is empty.") -Color Yellow
                continue
            }

            $lines    = @()
            $lines   += "RECALLED MEMORIES ($($memories.Count) entries):"
            $lines   += ""
            $grouped  = $memories | Group-Object -Property category | Sort-Object Name
            foreach ($group in $grouped) {
                $lines += "[$($group.Name.ToUpper())]"
                foreach ($m in $group.Group) {
                    $lines += "  $($m.date)  $($m.fact)"
                }
                $lines += ""
            }

            $history += @{
                role  = "user"
                parts = @(@{ text = "MEMORY CONTEXT - facts you have learned about me in previous sessions:`n`n$($lines -join "`n")`n`nAcknowledge this context briefly and use it going forward." })
            }

            $boxLines = @("$CHK  Loaded $($memories.Count) memories into context", "")
            foreach ($group in $grouped) {
                $boxLines += "  $($group.Name.ToUpper()) ($($group.Group.Count))"
                foreach ($m in $group.Group) {
                    $preview   = if ($m.fact.Length -gt 55) { $m.fact.Substring(0, 55) + "..." } else { $m.fact }
                    $boxLines += "    $($m.date.Substring(0,10))  $preview"
                }
            }
            Draw-Box $boxLines -Title "/recall  $BUL  Memory Loaded" -Width 80 -Color Magenta

        } catch {
            Draw-Box @("$CRS  Failed to load memory: $($_.Exception.Message)") -Color Red
        }
        continue
    }


    if ($userInput -eq "/tools") {
        $toolLines = @()
        foreach ($tool in $script:TOOLS.Values) {
            $paramList = ($tool.Parameters.Keys | ForEach-Object { "$_=$($tool.Parameters[$_])" }) -join ", "
            $toolLines += "$CHK  $($tool.Name)($paramList)"
            $toolLines += "     $ARR  $($tool.Description)"
            $toolLines += ""
        }
        Draw-Box $toolLines -Title "Available Tools" -Width 80 -Color Green
        continue
    }

    if ($userInput -eq "/resetkey") {
        if (Test-Path $configFile) { Remove-Item $configFile -Force }
        Draw-Box @("$CHK  Saved API key deleted. Restart the script to set a new one.") -Color Cyan       
        break
    }

    if ($userInput -eq "/settings") {
        $settingsChoice = Show-ArrowMenu -Options @("Colors", "Tools", "Smart Trim", "Start Delay", "Exit") -Title "Settings"
        switch ($settingsChoice) {
            0 { 
                $schemeOptions = @("Default Scheme", "Alternative Scheme")
                $schemeIdx = if ($scheme -eq "alternative") { 1 } else { 0 }
                $choice = Show-ArrowMenu -Options $schemeOptions -Title "Color Settings" -Default $schemeIdx
                if ($choice -ge 0) {
                    $newScheme = if ($choice -eq 1) { "alternative" } else { "default" }
                    $script:Settings.color_scheme = $newScheme
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    Draw-Box @("Color scheme updated to '$newScheme'. Restart the script to apply changes.") -Color Yellow
                }
            }
            1 { 
                $enabledTools = Get-ChildItem -Path "tools" -Filter "*.ps1" | ForEach-Object { @{ Name = $_.BaseName; Status = "Enabled" } }
                $disabledTools = Get-ChildItem -Path "more_tools" -Filter "*.ps1" | ForEach-Object { @{ Name = $_.BaseName; Status = "Disabled" } }
                $allTools = $enabledTools + $disabledTools
                $toolOptions = $allTools | ForEach-Object { "$($_.Name) ($($_.Status))" }
                $toolChoice = Show-ArrowMenu -Options $toolOptions -Title "Tool Management"
                if ($toolChoice -ge 0) {
                    $selectedTool = $allTools[$toolChoice]
                    $enabledCount = ($allTools | Where-Object { $_.Status -eq "Enabled" }).Count
                    $limit = $script:TOOL_LIMITS[$script:MODEL]

                    if ($selectedTool.Status -eq "Disabled" -and $enabledCount -ge $limit) {
                        Draw-Box @("Model '$($script:MODEL)' only supports $limit active tools. Please disable a tool before enabling another.") -Color Red
                    } else {
                        if ($selectedTool.Status -eq "Enabled") {
                            Move-Item -Path "tools\$($selectedTool.Name).ps1" -Destination "more_tools/"
                            $script:Settings.disabled_tools += $selectedTool.Name
                            $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                            Draw-Box @("Tool '$($selectedTool.Name)' has been disabled.") -Color Yellow
                        } else {
                            Move-Item -Path "more_tools\$($selectedTool.Name).ps1" -Destination "tools/"
                            $script:Settings.disabled_tools = $script:Settings.disabled_tools | Where-Object { $_ -ne $selectedTool.Name }
                            $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                            Draw-Box @("Tool '$($selectedTool.Name)' has been enabled.") -Color Yellow
                        }
                    }
                }
            }
            2 {
                $currentEnabled  = if ($null -ne $script:Settings.smart_trim) { [bool]$script:Settings.smart_trim } else { $false }
                $currentStrength = if ($script:Settings.smart_trim_strength) { [int]$script:Settings.smart_trim_strength } else { 5 }
                $trimState       = if ($currentEnabled) { "Enabled" } else { "Disabled" }

                $trimChoice = Show-ArrowMenu -Options @("Toggle Smart Trim ($trimState)", "Set Strength ($currentStrength)") -Title "Smart Trim Settings"

                if ($trimChoice -eq 0) {
                    $script:Settings.smart_trim = -not $currentEnabled
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    $newState = if ($script:Settings.smart_trim) { "Enabled" } else { "Disabled" }
                    Draw-Box @("$CHK  Smart Trim $newState") -Color Magenta
                }
                elseif ($trimChoice -eq 1) {
                    $strengthOptions = @(
                        "1  - Conservative  (keep most, minimal token savings)",
                        "2  - Conservative+",
                        "3  - Balanced-",
                        "4  - Balanced",
                        "5  - Balanced+  (recommended)",
                        "6  - Aggressive-",
                        "7  - Aggressive",
                        "8  - Aggressive+",
                        "9  - Maximum-",
                        "10 - Maximum  (keep least, most token savings)"
                    )
                    $strengthIdx    = [math]::Max(0, $currentStrength - 1)
                    $strengthChoice = Show-ArrowMenu -Options $strengthOptions -Title "Smart Trim Strength" -Default $strengthIdx
                    if ($strengthChoice -ge 0) {
                        $script:Settings.smart_trim_strength = $strengthChoice + 1
                        $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                        Draw-Box @("$CHK  Smart Trim strength set to $($script:Settings.smart_trim_strength)") -Color Magenta
                    }
                }
            }
            3 {
                $currentDelay = if ($script:Settings.startup_delay) { [int]$script:Settings.startup_delay } else { 0 }
                $delayOptions = @("0s  - No delay", "1s", "2s", "3s", "5s")
                $delayValues  = @(0, 1, 2, 3, 5)
                $currentIdx   = [math]::Max(0, $delayValues.IndexOf($currentDelay))
                $delayChoice  = Show-ArrowMenu -Options $delayOptions -Title "Startup Delay  $BUL  current: $($currentDelay)s" -Default $currentIdx
                if ($delayChoice -ge 0) {
                    $script:Settings.startup_delay = $delayValues[$delayChoice]
                    $script:Settings | ConvertTo-Json | Set-Content -Path $settingsPath
                    Draw-Box @("$CHK  Startup delay set to $($delayValues[$delayChoice])s") -Color Magenta
                }
            }
        }
        continue
    }

    if ($userInput -eq "/customCommand") {
        $lines = @(
            "HOW TO CREATE A CUSTOM COMMAND:",
            "Use the syntax: /customCommand /yourAlias Your detailed prompt here",
            "Example: /customCommand /poem write a short poem about coding",
            "",
            "Once created, you can just type /yourAlias to execute that prompt.",
            ""
        )

        if ($script:customCommands.Count -gt 0) {
            $lines += "YOUR CUSTOM COMMANDS:"
            foreach ($key in $script:customCommands.Keys) {
                $lines += "$($key.PadRight(18)) $ARR  $($script:customCommands[$key])"
            }
        } else {
            $lines += "You haven't created any custom commands yet."
        }

        Draw-Box $lines -Title "Custom Commands Management" -Width 80 -Color $script:Colors.custom_command
        continue
    }

    if ($userInput -match '^/customCommand\s+(\/\w+)\s+(.*)') {
        $alias = $matches[1]
        $prompt = $matches[2]
        
        $script:customCommands[$alias] = $prompt
        $script:customCommands | ConvertTo-Json | Set-Content -Path $customCommandsPath
        
        Draw-Box @("Custom command '$alias' has been saved and is ready to use.") -Color Green
        continue
    }

    # ---- /model command ----
    if ($userInput -match '^/model\s*(.*)$') {
        $modelArg = $matches[1].Trim()

        if ([string]::IsNullOrWhiteSpace($modelArg)) {
            # Show interactive arrow-key picker
            $menuLabels = $script:MODEL_REGISTRY.Keys | ForEach-Object {
                $e = $script:MODEL_REGISTRY[$_]
                "$($e.label.PadRight(18)) $ARR  $($e.id.PadRight(22))  $($e.desc)"
            }
            $currentIdx = 0
            $keys = @($script:MODEL_REGISTRY.Keys)
            for ($i = 0; $i -lt $keys.Count; $i++) {
                if ($script:MODEL_REGISTRY[$keys[$i]].id -eq $script:MODEL) { $currentIdx = $i; break }
            }
            $choice = Show-ArrowMenu `
                -Options $menuLabels `
                -Title "Select Model  $BUL  current: $script:MODEL" `
                -Width 100 `
                -Default $currentIdx
            if ($choice -ge 0) {
                $script:MODEL = $script:MODEL_REGISTRY[$keys[$choice]].id
                # SAFE TO REMOVE? $currentUri   = Get-ApiUri
                $history = @(@{ role = "user"; parts = @(@{ text = (Get-SystemPrompt) }) })
                Draw-Box @("$CHK  Model switched to: $script:MODEL") -Color Magenta
            } else {
                Write-Host "  Model selection cancelled." -ForegroundColor DarkGray
            }
        } else {
            # Direct switch: /model 3n-e4b  OR  /model gemma-3n-e4b-it
            $resolved = Resolve-ModelId $modelArg
            $script:MODEL = $resolved
            $currentUri   = Get-ApiUri
            $history = @(@{ role = "user"; parts = @(@{ text = (Get-SystemPrompt) }) })
            Draw-Box @("$CHK  Model switched to: $script:MODEL") -Color Magenta
        }
        continue
    }

    # ---- /bigBrother command ----
    if ($userInput -match '^/bigBrother\s+(.+)$') {
        $query = $matches[1].Trim()
        Invoke-DualAgent -query $query -mode "bigBrother"
        continue
    }

    if ($userInput -eq "/bigBrother") {
        Draw-Box @("$CRS  Usage: /bigBrother <your question>") -Color Yellow
        continue
    }

    # ---- /littleSister command ----
    if ($userInput -match '^/littleSister\s+(.+)$') {
        $query = $matches[1].Trim()
        Invoke-DualAgent -query $query -mode "littleSister"
        continue
    }

    if ($userInput -eq "/littleSister") {
        Draw-Box @("$CRS  Usage: /littleSister <your question>") -Color Yellow
        continue
    }

    if ($script:customCommands.ContainsKey($userInput)) {
        $userInput = $script:customCommands.$userInput
        Draw-Box @("Executing custom command: $userInput") -Color $script:Colors.custom_command
    }

    if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

    $history += @{ role = "user"; parts = @(@{ text = $userInput }) }

    $currentUri = Get-ApiUri 
    $toolTurns    = 0
    $maxToolTurns = if ($script:MODEL -in @("gemma-3-27b-it","gemma-3-12b-it")) { 4 } else { 2 }

    while ($toolTurns -lt $maxToolTurns) {
        $toolTurns++

        # RPM check — enforces free-tier request-per-minute ceiling before every call
        Invoke-RpmCheck -backend "gemma"

        # Minimum 2-second gap between calls (secondary guard, covers sub-RPM burst)
        if ($script:lastApiCall) {
            $elapsed = ((Get-Date) - $script:lastApiCall).TotalMilliseconds
            if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        }
        $script:lastApiCall = Get-Date

        # Trim history if approaching context window limit
        $history = Invoke-SmartTrim -hist $history -tokenBudget 11000 -currentQuery $userInput

        # Start spinner ONLY for the API call to avoid interfering with tool logic
        Start-Spinner -Label "Gemma is thinking (Esc to cancel)"

        $resp = Invoke-GemmaApiWithRetry -uri $currentUri -historyRef ([ref]$history) -gConfig $script:GUARDRAILS

        Stop-Spinner 

        if ($resp.cancelled) {
            Write-Host " [Operation cancelled by user]" -ForegroundColor Yellow
            break
        }

        if (-not $resp) {
            Write-Host ""
            Draw-Box @("$CRS  No response from API. Check your connection or API key.") -Color Red
            break
        }
        if ($resp.apiError) {
            $errMsg = $resp.apiError
            Write-Host ""
            Draw-Box @("$CRS  API Error:", "     $errMsg") -Color Red
            break
        }
        if (-not $resp.candidates) {
            $reason = if ($resp.promptFeedback.blockReason) { $resp.promptFeedback.blockReason } else { "Unknown reason" }
            Write-Host ""
            Draw-Box @("$CRS  Response blocked: $reason") -Color Red
            break
        }

        # Update metadata for next status bar draw
        $usage = $resp.usageMetadata
        $fin   = $resp.candidates[0].finishReason
        $script:lastStatus = @{ prompt = $usage.promptTokenCount; candidate = $usage.candidatesTokenCount; total = $usage.totalTokenCount; finish = $fin }
        Write-ApiLog -toolName "chat"  # updated to tool name below if a tool call is parsed

        $modelText = $resp.candidates[0].content.parts[0].text.Trim()

        $jsonStr = $null

        # Format 1: Official XML style <tool_call>{...}</tool_call> — skip if wrapped in code_block tags
        if ($modelText -match '(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>' -and $modelText -notmatch '<code_block>') {
            $jsonStr = $matches[1]
        }
        # Format 2: Markdown style ```tool_code\n{...}\n``` — skip if wrapped in outer codefence or code_block tags
        elseif ($modelText -match '(?s)```tool_code\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_code' -and $modelText -notmatch '<code_block>') {
            $jsonStr = $matches[1]
        }
        # Format 3: Codefence style ```tool_call\n{...}\n``` — skip if wrapped in outer codefence or code_block tags
        elseif ($modelText -match '(?s)```tool_call\s*(\{.*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```tool_call' -and $modelText -notmatch '<code_block>') {
            $jsonStr = $matches[1]
        }
        # Format 4: Plain ```json\n{...}\n``` with a name field — skip if wrapped in outer codefence or code_block tags
        elseif ($modelText -match '(?s)```json\s*(\{.*?""name"".*?\})\s*```' -and $modelText -notmatch '(?s)```[^`]*```json' -and $modelText -notmatch '<code_block>') {
            $jsonStr = $matches[1]
        }
        # Format 5: Bare function call style tool_name({"param": "value"}) — skip if wrapped in code_block tags
        elseif ($modelText -match '(?s)(\w+)\(\s*(\{.*?\})\s*\)' -and $modelText -notmatch '<code_block>') {
            $jsonStr = "{`"name`": `"$($matches[1])`", `"parameters`": $($matches[2])}"
        }

         if ($jsonStr) {
         # Bulletproof sanitization: handles escaped quotes AND escaped backslashes
         $jsonStr = [System.Text.RegularExpressions.Regex]::Replace($jsonStr, '(?s)("(?:[^"\\]|\\.)*")', {
             param($m) $m.Value -replace "\r\n|\r|\n", '\n'
         })
    
         if ($script:debugMode) {
            Write-Host "`n[DEBUG] Sanitized Tool Call JSON: $jsonStr" -ForegroundColor Yellow
         }
   
         try {
            $call = $jsonStr | ConvertFrom-Json
                $params = ConvertTo-Hashtable -Object $call.parameters
                $tool = $script:TOOLS[$call.name]
                if (-not $tool) {
                    throw "Unknown tool '$($call.name)' requested."
                }
                $label = & $tool.FormatLabel $params


                Write-Host ""
                Write-Host " Tool request: " -NoNewline -ForegroundColor DarkGray
                Write-Host $label -ForegroundColor White
                Write-Host ""

                $choice = Show-ArrowMenu `
                    -Options @("Allow once", "Deny") `
                    -Title "Action Required  $BUL  $label" `
                    -Width 100 `
                    -Default 0

                if ($choice -ne 0) {
                    Write-Host ""
                    Draw-Box @("$CRS  Tool call denied.") -Color Red
                    $history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $history += @{ role = "user";  parts = @(@{ text = "TOOL RESULT: The user denied this tool call. Please respond without using that tool." }) }
                    continue
                }

                Write-Host ""
                Draw-Box @("$CHK  $label") -Color Magenta

                # Execute tool directly in the main session as in 019
                # but with a simple Esc check loop if possible
                Start-Spinner -Label "Executing $($call.name) (Esc to cancel)"

                $script:toolJob = Start-Job -ScriptBlock {
                    param($toolName, $params, $toolsDir, $workDir)
                    Set-Location -Path $workDir
                    
                    $toolFile = Join-Path $toolsDir "$toolName.ps1"
                    if (-not (Test-Path $toolFile)) {
                        return "ERROR: Tool file '$toolFile' not found."
                    }
                    
                    try {
                        # Dot-source the tool file to load its metadata and functions
                        . $toolFile
                        if (-not $ToolMeta.Execute) {
                            return "ERROR: Tool '$toolName' is missing its 'Execute' scriptblock."
                        }
                        # Invoke the tool's execution block with the parameters
                        return & $ToolMeta.Execute $params
                    } catch {
                        return "ERROR: Exception while executing tool '$toolName': $($_.Exception.Message) | StackTrace: $($_.ScriptStackTrace)"
                    } finally {
                        $ToolMeta = $null
                    }
                } -ArgumentList $call.name, $params, (Join-Path $scriptDir "tools"), (Get-Location)


                $cancelled = $false
                while ($script:toolJob.State -eq "Running") {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq "Escape") {
                            $cancelled = $true
                            Stop-Job $script:toolJob
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                }

                if ($cancelled) {
                    Stop-Spinner
                    Remove-Job $script:toolJob
                    Write-Host " [Tool execution cancelled by user]" -ForegroundColor Yellow
                    break
                }

                $result = Receive-Job $script:toolJob
                Remove-Job $script:toolJob
                Stop-Spinner
                if ($script:debugMode) { Write-Host "`n[DEBUG] Tool Execution Result: $result" -ForegroundColor Yellow }

                # Ensure result is a single clean string (job may return string[])
                if ($result -is [array]) { $result = $result -join "`n" }
                if (-not $result) { $result = "(empty result)" }

                # Strip control characters (null bytes, BOM, etc.) that break JSON
                $result = $result -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
                # Remove UTF-8 BOM if present
                $result = $result.TrimStart([char]0xFEFF)

                $maxChars = 20000
                $truncated = $false
                if ($result.Length -gt $maxChars) {
                  $result = $result.Substring(0, $maxChars)
                  $truncated = $true
                }
                $truncNote = if ($truncated) { "`n[Note: file was truncated to $maxChars characters due to size limits]" } else { "" }

                # Handle image tool results — inject as multimodal content
                if ($result -match "^IMAGE_DATA::([^:]+)::([^:]+)::(.+)$") {
                    $mime   = $matches[1]
                    $b64    = $matches[2]
                    $prompt = $matches[3]
                    $history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $history += @{
                        role  = "user"
                        parts = @(
                            @{ text = "TOOL RESULT: Image loaded. $prompt" },
                            @{ inline_data = @{ mime_type = $mime; data = $b64 } }
                        )
                    }
                } else {
                    $history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $history += @{ role = "user"; parts = @(@{ text = "TOOL RESULT:`n$result$truncNote`n`nNow respond to the user based on context. Do not call this tool again immediately." }) }
                }

                Write-ApiLog -toolName $call.name
                continue

            } catch {
                Write-Host "Tool call parse error: $($_.Exception.Message)" -ForegroundColor Red
                break
            }

       } else {
            if ($script:debugMode) {
                Write-Host "`n[DEBUG] Raw Model Text: $modelText" -ForegroundColor Yellow
            }
            $history += @{ role = "model"; parts = @(@{ text = $modelText }) }
            Write-Host ""
            Write-Host " Gemma: " -NoNewline -ForegroundColor $script:Colors.gemma_response
            Write-Host ""
           $segments = [System.Text.RegularExpressions.Regex]::Split($modelText, '(?s)(<code_block>.*?</code_block>)')
            foreach ($seg in $segments) {
                if ($seg -match '(?s)<code_block>(.*?)</code_block>') {
                    $code = $matches[1].Trim()
                    Write-Host ""
                    foreach ($codeLine in $code -split "`n") {
                        Write-Host "  $codeLine" -ForegroundColor White -BackgroundColor DarkGray
                    }
                    Write-Host ""
                } else {
                     if ($seg.Trim()) { Write-Host $seg }
                }
            }
            Write-Host ""
            break
        }
    }
}

Write-Host ""
Draw-Box @("Goodbye!  Thanks for using Gemma CLI.") -Color $script:Colors.ui_boxes