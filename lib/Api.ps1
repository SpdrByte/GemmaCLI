# lib/Api.ps1 v0.1.2
# Responsibility: Manages interactions with the Google Gemini API, including Job management and error handling.
# Handles the Start-Job logic for API calls.

function Get-StoredKey {
    param([string]$keyName = "gemmacli")
    $configDir  = Join-Path $env:APPDATA "GemmaCLI"
    $configFile = Join-Path $configDir "${keyName}.xml"
    if (Test-Path $configFile) {
        try {
            $secureString = Import-Clixml -Path $configFile
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        } catch { }
    }
    return $null
}

function Save-StoredKey {
    param([string]$apiKey, [string]$keyName = "gemmacli")
    $configDir  = Join-Path $env:APPDATA "GemmaCLI"
    $configFile = Join-Path $configDir "${keyName}.xml"
    if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }
    $secureString = ConvertTo-SecureString $apiKey -AsPlainText -Force
    $secureString | Export-Clixml -Path $configFile
}

function Remove-StoredKey {
    param([string]$keyName = "gemmacli")
    $configDir  = Join-Path $env:APPDATA "GemmaCLI"

    $configFile = Join-Path $configDir "${keyName}.xml"
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force
        return $true
    }
    return $false
}

function Resolve-ModelId {
    param([string]$Choice)
    $c = $Choice.Trim().ToLower()
    if ($script:MODEL_REGISTRY) {
        # Check if it's a hashtable or a PSCustomObject
        if ($script:MODEL_REGISTRY.PSObject.Properties[$c]) { return $script:MODEL_REGISTRY.PSObject.Properties[$c].Value.id }
        foreach ($entry in $script:MODEL_REGISTRY.Values) { if ($entry.id -eq $c) { return $entry.id } }
    }
    Write-Warning "Unknown model '$Choice' or registry missing. Defaulting to gemma-3-27b-it."
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

function Get-BaseUri { return "$($script:BASE_URI_BASE)/$($script:MODEL):generateContent" }
function Get-ApiUri { return "$(Get-BaseUri)?key=$($script:API_KEY)" }
function Get-GeminiUri { 
    $modelId = Resolve-ModelId "gemini-stable-fast"
    return "$($script:BASE_URI_BASE)/${modelId}:generateContent?key=$($script:API_KEY)" 
}

function Get-GeminiLiteUri {
    $modelId = Resolve-ModelId "gemini-lite"
    return "$($script:BASE_URI_BASE)/${modelId}:generateContent?key=$($script:API_KEY)"
}

function Get-SystemPrompt {
    if (-not $script:intelligence.system_prompts) { return $script:intelligence.system_prompt }
    $specific = $script:intelligence.system_prompts.PSObject.Properties[$script:MODEL]
    if ($specific) { return $specific.Value }
    return $script:intelligence.system_prompt
}

function Invoke-ModelGeneration {
    param($uri, $contents, $gConfig, [bool]$skipCancelCheck = $false, $tools = $null, $toolConfig = $null)

    # Capture current setting from main thread to pass into the background job
    $currentExpect = [System.Net.ServicePointManager]::Expect100Continue

    $script:apiJob = Start-Job -ScriptBlock {
        param($uri, $contents, $gConfig, $tools, $toolConfig, $expectSetting)
        
        # Apply the setting from settings.json/main thread
        [System.Net.ServicePointManager]::Expect100Continue = $expectSetting

        $payload = @{
            contents         = $contents
            generationConfig = $gConfig
        }
        if ($null -ne $tools) { $payload["tools"] = $tools }
        if ($null -ne $toolConfig) { $payload["toolConfig"] = $toolConfig }

        $json = $payload | ConvertTo-Json -Depth 20 -Compress
        # Send as UTF8 bytes to avoid PowerShell string encoding issues
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        try {
            Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes
        } catch {
            $detail = ""
            try {
                $response = $_.Exception.Response
                if ($response) {
                    $stream = $null
                    $reader = $null
                    try {
                        $stream = $response.GetResponseStream()
                        $reader = [System.IO.StreamReader]::new($stream)
                        $raw    = $reader.ReadToEnd()
                        $json   = $raw | ConvertFrom-Json
                        $detail = if ($json.error.message) { $json.error.message } else { $raw }
                    } finally {
                        if ($reader) { $reader.Close(); $reader.Dispose() }
                        if ($stream) { $stream.Close(); $stream.Dispose() }
                    }
                }
            } catch {}
            $msg = if ($detail) { $detail } else { $_.Exception.Message }
            [PSCustomObject]@{ apiError = $msg }
        }
    } -ArgumentList $uri, $contents, $gConfig, $tools, $toolConfig, $currentExpect

    $cancelled = $false
    while ($script:apiJob.State -eq "Running") {
        if (-not $skipCancelCheck) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq "Escape") {
                    $cancelled = $true
                    Stop-Job $script:apiJob
                    break
                }
            }
        }
        Start-Sleep -Milliseconds 100
    }

    if ($cancelled) {
        Remove-Job $script:apiJob
        return [PSCustomObject]@{ cancelled = $true }
    }

    $resp = Receive-Job $script:apiJob
    Remove-Job $script:apiJob
    return $resp
}

function Invoke-GemmaApi {
    param($uri, $history, $gConfig)
    return Invoke-ModelGeneration -uri $uri -contents $history -gConfig $gConfig
}

function Invoke-RpmCheck {
    param([string]$backend = "gemma")
    # Gemini Flash free tier: 15 RPM. Gemma 4/Gemma 3 27B/12B: 2 RPM. Others: 5 RPM.
    $rpm         = if ($backend -eq "gemini") { 15 } elseif ($script:MODEL -in @("gemma-4-31b-it","gemma-4-26b-a4b-it","gemma-3-27b-it","gemma-3-12b-it")) { 2 } else { 5 }
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

            # On first quota failure: check token count and trim if over threshold
            Stop-Spinner
            if ($attempt -eq 0) {
                $tokenEst = 0
                foreach ($turn in $historyRef.Value) {
                    foreach ($part in $turn.parts) {
                        if ($part.text) { $tokenEst += [int]($part.text.Length / 4) }
                    }
                }
                $threshold = if ($script:TRIM_THRESHOLD) { $script:TRIM_THRESHOLD } else { 11000 }
                if ($tokenEst -gt $threshold) {
                    if ($script:debugMode) { Write-Host " [Retry] Token estimate $tokenEst > $threshold - trimming before retry" -ForegroundColor DarkYellow }
                    $historyRef.Value = Trim-History -hist $historyRef.Value -tokenBudget $threshold
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

function Write-ApiLog {
    param([string]$toolName = "chat")
    $logFile = Join-Path $script:configDir "gemma_cli.log"
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

function Invoke-SingleTurnApi {
    param([string]$uri, [string]$prompt, [string]$spinnerLabel = "Thinking...", [string]$backend = "gemma", $tools = $null, $toolConfig = $null, $configOverride = $null)
    Invoke-RpmCheck -backend $backend

    # 2-second gap enforced per backend independently
    if ($backend -eq "gemini") {
        $elapsed = ((Get-Date) - $script:lastApiCall_Gemini).TotalMilliseconds
        if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        $script:lastApiCall_Gemini = Get-Date
    } else {
        $elapsed = ((Get-Date) - $script:lastApiCall).TotalMilliseconds
        if ($elapsed -lt 2000) { Start-Sleep -Milliseconds (2000 - $elapsed) }
        $script:lastApiCall = Get-Date
    }

    $contents = @(@{ role = "user"; parts = @(@{ text = $prompt }) })
    $gConfig = if ($null -ne $configOverride) { $configOverride } else { @{ maxOutputTokens = 4096; temperature = 0.7; topP = 0.95 } }

    # Detect if we are running inside a Start-Job (no interactive console)
    $isJob = ($null -ne $MyInvocation.MyCommand.ModuleName) -or ($host.Name -match "Server") -or ($null -eq [Console]::WindowWidth)
    
    Start-Spinner -Label $spinnerLabel
    $resp = Invoke-ModelGeneration -uri $uri -contents $contents -gConfig $gConfig -skipCancelCheck $isJob -tools $tools -toolConfig $toolConfig
    Stop-Spinner

    # --- Cascading Fallbacks ---
    if ($resp.apiError -and $backend -eq "gemini" -and ($resp.apiError -match "429|quota|RESOURCE_EXHAUSTED")) {
        # Tier 2: Gemini Lite
        $liteUri = Get-GeminiLiteUri
        if ($uri -ne $liteUri) {
            Write-Host " [Flash quota exceeded - falling back to Gemini Lite...]" -ForegroundColor Cyan
            Start-Spinner -Label "Lite: $spinnerLabel"
            $resp = Invoke-ModelGeneration -uri $liteUri -contents $contents -gConfig $gConfig -skipCancelCheck $isJob -tools $tools -toolConfig $toolConfig
            Stop-Spinner
        }

        # Tier 3: Gemma 12b (Final Backup)
        if ($resp.apiError -and ($resp.apiError -match "429|quota|RESOURCE_EXHAUSTED")) {
            $gemmaId = Resolve-ModelId "gemma-heavy"
            $gemmaUri = "$($script:BASE_URI_BASE)/${gemmaId}:generateContent?key=$($script:API_KEY)"
            Write-Host " [Gemini Lite quota exceeded - falling back to Gemma 12b...]" -ForegroundColor Yellow
            Start-Spinner -Label "Gemma: $spinnerLabel"
            $resp = Invoke-ModelGeneration -uri $gemmaUri -contents $contents -gConfig $gConfig -skipCancelCheck $isJob -tools $tools -toolConfig $toolConfig
            Stop-Spinner
        }
    }

    if ($resp.cancelled) { return "ERROR: Operation cancelled by user" }
    if ($resp.apiError)  { return "ERROR: $($resp.apiError)" }
    if (-not $resp.candidates) {
        $reason = if ($resp.promptFeedback.blockReason) { $resp.promptFeedback.blockReason } else { "No candidates returned (blocked?)" }
        return "ERROR: $reason"
    }
    
    # If using custom config, return the raw response object so tool can handle multi-modal data
    if ($null -ne $configOverride) { return $resp }

    return $resp.candidates[0].content.parts[0].text.Trim()
}

function Invoke-DualAgent {
    param(
        [string]$query,
        [string]$mode   # "bigBrother" or "littleSister"
    )

    # Compact context snapshot — last 3 user turns for Gemma's correction pass
    $contextSummary = "CURRENT SESSION CONTEXT:`n"
    $contextSummary += "Active model: $script:MODEL`n"
    $contextSummary += "Recent conversation turns: $([math]::Max(0, $script:history.Count - 1))`n"
    $recentTurns = $script:history | Select-Object -Last 6 | Where-Object { $_.role -eq "user" } | Select-Object -Last 3
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

        $lastTurn = ($script:history | Select-Object -Last 3 | Where-Object { $_.role -ne "user" -or $_.parts[0].text -notmatch '^/bigBrother' } | ForEach-Object { $_.parts[0].text }) -join "`n"

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

        $script:history = $script:history + @(
            @{ role = "user";  parts = @(@{ text = $query }) },
            @{ role = "model"; parts = @(@{ text = "[bigBrother synthesis] $finalAnswer" }) }
        )
        $script:history = $script:history

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

        $script:history = $script:history + @(
            @{ role = "user";  parts = @(@{ text = $query }) },
            @{ role = "model"; parts = @(@{ text = "[littleSister synthesis] $finalAnswer" }) }
        )
        $script:history = $script:history
    }
}
