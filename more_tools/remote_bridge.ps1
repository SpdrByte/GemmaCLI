# more_tools/remote_bridge.ps1 v1.1.0
# Responsibility: Provides a secure bridge to Telegram for remote control from Android.
# =============================================================================

function Invoke-RemoteBridgeTool {
    param(
        [string]$action = "send", # "send" | "listen" | "setup"
        [string]$message = "",
        [int]$timeout_sec = 60    # For 'listen'
    )

    # Use the global scriptDir defined in GemmaCLI.ps1
    $scriptRootDir = $global:scriptDir
    if (-not $scriptRootDir) { $scriptRootDir = "." }

    # Load Token and ChatID from secure storage
    # Check for both specific name and the generic tool name from CLI setup
    $token = Get-StoredKey -keyName "telegram_bot_token"
    if (-not $token) { $token = Get-StoredKey -keyName "remote_bridge" }
    
    $allowedChatId = Get-StoredKey -keyName "telegram_chat_id"

    # ── ACTION: setup ───────────────────────────────────────────────────────
    if ($action -eq "setup") {
        Write-Host "`n=== Telegram Bridge Setup ===" -ForegroundColor Cyan
        Write-Host "1. Open https://t.me/BotFather to create a bot and get a TOKEN."
        Write-Host "2. Open https://t.me/userinfobot to get your personal Chat ID.`n"
        
        if ($token) { Write-Host "[!] Existing Token found. Press Enter to keep it, or paste a new one." -ForegroundColor Green }
        $newToken = Read-Host "Enter Telegram Bot Token"
        if ([string]::IsNullOrWhiteSpace($newToken) -and $token) { $newToken = $token }

        if ($allowedChatId) { Write-Host "[!] Existing Chat ID found ($allowedChatId). Press Enter to keep it." -ForegroundColor Green }
        Write-Host "Hint: Message @userinfobot on Telegram to get your unique ID number." -ForegroundColor Gray
        $newChat  = Read-Host "Enter your Chat ID"
        if ([string]::IsNullOrWhiteSpace($newChat) -and $allowedChatId) { $newChat = $allowedChatId }
        
        if ($newToken -and $newChat) {
            Save-StoredKey -apiKey $newToken -keyName "telegram_bot_token"
            Save-StoredKey -apiKey $newChat  -keyName "telegram_chat_id"
            # Sync to generic name too for CLI consistency
            Save-StoredKey -apiKey $newToken -keyName "remote_bridge"
            return "OK: Telegram Bridge configured. You can now use 'tunnel' to start your mobile session."
        }
        return "ERROR: Setup incomplete."
    }

    if (-not $token -or -not $allowedChatId) {
        return "ERROR: Telegram Bridge not configured. Run 'setup' action first."
    }

    $baseUri = "https://api.telegram.org/bot$token"

    # ── SHARED HELPER: Send-RemoteMsg ────────────────────────────────────────
    # Handles Telegram rate limits (1 msg/sec) and character limits (4096)
    $SendRemoteMsg = {
        param($txt, $token, $chatId, [bool]$useMarkdown = $true)
        if ([string]::IsNullOrWhiteSpace($txt)) { return }
        $base = "https://api.telegram.org/bot$token"
        
        # Chunking: Telegram limit is 4096. We'll use 4000 for safety.
        $chunkSize = 4000
        for ($i = 0; $i -lt $txt.Length; $i += $chunkSize) {
            $chunk = $txt.Substring($i, [Math]::Min($chunkSize, $txt.Length - $i))
            $payload = @{ chat_id = $chatId; text = $chunk }
            if ($useMarkdown) { $payload["parse_mode"] = "Markdown" }
            
            $sent = $false; $attempts = 0
            while (-not $sent -and $attempts -lt 2) {
                try {
                    $body = $payload | ConvertTo-Json
                    Invoke-RestMethod -Uri "$base/sendMessage" -Method Post -Body $body -ContentType "application/json" | Out-Null
                    $sent = $true
                } catch {
                    $attempts++
                    if ($attempts -eq 1 -and $useMarkdown) {
                        # First failure? Try falling back to plain text (markdown often breaks on chunks)
                        $payload.Remove("parse_mode")
                    } elseif ($attempts -ge 2) {
                        Write-Host " [!] Telegram Send Failed: $($_.Exception.Message)" -ForegroundColor Red
                    } else {
                        Start-Sleep -Seconds 1
                    }
                }
            }
            # Rate limiting: 1 msg/sec per chat. Only sleep if there are more chunks.
            if (($i + $chunkSize) -lt $txt.Length) { Start-Sleep -Milliseconds 1100 }
        }
    }

    # ── ACTION: send ────────────────────────────────────────────────────────
    if ($action -eq "send") {
        if ([string]::IsNullOrWhiteSpace($message)) { return "ERROR: No message provided." }
        & $SendRemoteMsg $message $token $allowedChatId
        return "CONSOLE::Sent to phone: $message::END_CONSOLE::OK: Message sent to your Android device."
    }

    # ── ACTION: tunnel ──────────────────────────────────────────────────────
    elseif ($action -eq "tunnel") {
        Write-Host "`n[TUNNEL] Remote Session Active. Gemma is now synced to your phone." -ForegroundColor Cyan
        Write-Host "[TUNNEL] Sleep Prevention: ENABLED" -ForegroundColor Green
        Write-Host "[TUNNEL] Text 'EXIT' to close the tunnel. Send photos for vision analysis.`n" -ForegroundColor DarkGray
        
        # Keep system awake only if plugged in (Smart Power Logic)
        try {
            $isPluggedIn = $true # Default for desktops
            try { $isPluggedIn = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue).PowerOnline } catch {}
            
            if ($isPluggedIn -eq $false) {
                Write-Host "[TUNNEL] Power Status: BATTERY (Sleep prevention skipped)" -ForegroundColor Gray
            } else {
                $steCode = @"
                [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
                public static extern uint SetThreadExecutionState(uint esFlags);
"@
                $ste = Add-Type -MemberDefinition $steCode -Name "Win32Sleep" -Namespace "Win32" -PassThru
                # ES_CONTINUOUS (0x80000000) | ES_SYSTEM_REQUIRED (0x00000001) = 2147483649
                $flags = [uint32]2147483649
                $ste::SetThreadExecutionState($flags) | Out-Null
                Write-Host "[TUNNEL] Power Status: AC (Sleep Prevention ENABLED)" -ForegroundColor Green
            }
        } catch { 
            Write-Host " [!] Warning: Could not enable sleep prevention: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        $consoleSummary = New-Object System.Collections.Generic.List[string]
        $consoleSummary.Add("--- REMOTE SESSION START ---")

        # ... (Inside the while loop, just after the EXIT check)
        # Ensure cleanup happens on return
        try {
            # (Original tunnel logic continues here...)
        } finally {
            if ($ste) { $ste::SetThreadExecutionState($ES_CONTINUOUS) | Out-Null }
            Write-Host "[TUNNEL] Sleep Prevention: DISABLED" -ForegroundColor Yellow
        }

        # Initialize remote offset
        $script:REMOTE_OFFSET = 0
        try {
            $initial = Invoke-RestMethod -Uri "$baseUri/getUpdates?limit=1&offset=-1"
            if ($initial.result.Count -gt 0) { $script:REMOTE_OFFSET = $initial.result[0].update_id + 1 }
        } catch { }

        & $SendRemoteMsg "*Gemma Tunnel Opened* 🟢`nI am now synced to your mobile device. Standing by..." $token $allowedChatId

        $connErrorCount = 0
        while ($true) {
            Write-Host "[TUNNEL] Syncing..." -ForegroundColor Gray
            $userInput = $null
            $imagePart = $null
            
            # 1. Listen for User Input / Photos
            while ($null -eq $userInput -and $null -eq $imagePart) {
                try {
                    $updates = Invoke-RestMethod -Uri "$baseUri/getUpdates?offset=$($script:REMOTE_OFFSET)&timeout=20"
                    $connErrorCount = 0 # Reset on success
                    
                    foreach ($upd in $updates.result) {
                        $script:REMOTE_OFFSET = $upd.update_id + 1
                        if ($upd.message.chat.id.ToString() -eq $allowedChatId.ToString()) {
                            if ($upd.message.photo) {
                                # Get highest resolution photo
                                $photo = $upd.message.photo[-1]
                                $fileInfo = Invoke-RestMethod -Uri "$baseUri/getFile?file_id=$($photo.file_id)"
                                $filePath = $fileInfo.result.file_path
                                $imgUri = "https://api.telegram.org/file/bot$token/$filePath"
                                
                                Write-Host " [Remote] > Received image..." -ForegroundColor Yellow
                                $wc = New-Object System.Net.WebClient
                                $imgBytes = $wc.DownloadData($imgUri)
                                $b64 = [Convert]::ToBase64String($imgBytes)
                                $mime = if ($filePath -match "\.png$") { "image/png" } else { "image/jpeg" }
                                
                                $imagePart = @{ inline_data = @{ mime_type = $mime; data = $b64 } }
                                $userInput = if ($upd.message.caption) { $upd.message.caption } else { "[Image Uploaded]" }
                            } else {
                                $userInput = $upd.message.text
                            }
                        }
                    }
                } catch { 
                    $connErrorCount++
                    if ($connErrorCount -eq 5) { Write-Host "`n [!] WARNING: Lost connection to Telegram. Retrying..." -ForegroundColor Red }
                    if ($connErrorCount -gt 20) { return "ERROR: Persistent connection loss. Tunnel collapsed." }
                    Start-Sleep -Seconds ([Math]::Min(30, 2 * $connErrorCount)) # Backoff
                }
                Start-Sleep -Milliseconds 200
            }

            if ($userInput -eq "EXIT" -or $userInput -eq "/exit") {
                & $SendRemoteMsg "*Tunnel Closed* 🔴`nAll changes synced to local history." $token $allowedChatId
                $consoleSummary.Add("--- REMOTE SESSION END ---")
                return "CONSOLE::$($consoleSummary -join "`n")::END_CONSOLE::Remote session ended via EXIT command."
            }

            Write-Host " [Remote] > $userInput" -ForegroundColor Green
            $consoleSummary.Add("YOU (Remote): $userInput")
            
            # Real-time History Injection with [REMOTE] context tag
            $userTurn = @{ role = "user"; parts = @() }
            if ($imagePart) { 
                $userTurn.parts += @{ text = "[REMOTE IMAGE]: $userInput" }
                $userTurn.parts += $imagePart 
            } else {
                $userTurn.parts += @{ text = "[REMOTE]: $userInput" }
            }
            $script:history += $userTurn

            # 2. Recursive Turn Loop (Gemma keeps going if she calls tools)
            $finishedTurn = $false
            while (-not $finishedTurn) {
                $modelUri = Get-ApiUri
                $gConfig = $script:GUARDRAILS
                
                Start-Spinner -Label "Gemma is thinking (Remote)"
                $resp = Invoke-GemmaApiWithRetry -uri $modelUri -historyRef ([ref]$script:history) -gConfig $gConfig
                Stop-Spinner

                if (-not $resp.candidates) { $finishedTurn = $true; break }
                $modelText = $resp.candidates[0].content.parts[0].text.Trim()

                # 3. Handle Tool Calls inside Tunnel
                if ($modelText -match '(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>') {
                    try {
                        $call = $matches[1] | ConvertFrom-Json
                        $toolName = $call.name
                        $params = ConvertTo-Hashtable -Object $call.parameters
                        
                        # Recursive protection: Block gemma from opening a tunnel inside a tunnel
                        if ($toolName -eq "remote_bridge") {
                            $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                            $script:history += @{ role = "user";  parts = @(@{ text = "TOOL RESULT: Error - remote_bridge is already active. You cannot call it recursively. Please use other tools or reply to the user." }) }
                            continue
                        }

                        # Terminal Logging for local user
                        Write-Host " [Remote Tool Request] > $toolName" -ForegroundColor Magenta
                        
                        # REMOTE PERMISSION REQUEST
                        & $SendRemoteMsg "⚠ *Permission Required*`nGemma wants to use tool: *$toolName*`nParams: ``$($params | ConvertTo-Json -Compress)```n`nReply *YES* to allow, *NO* to deny." $token $allowedChatId
                        $consoleSummary.Add("GEMMA: Requested tool $toolName")

                        $permission = $null
                        while ($null -eq $permission) {
                            $upds = Invoke-RestMethod -Uri "$baseUri/getUpdates?offset=$($script:REMOTE_OFFSET)&timeout=20"
                            foreach ($u in $upds.result) {
                                $script:REMOTE_OFFSET = $u.update_id + 1
                                if ($u.message.chat.id.ToString() -eq $allowedChatId.ToString()) {
                                    $permission = $u.message.text.ToUpper()
                                }
                            }
                        }

                        if ($permission -eq "YES") {
                            & $SendRemoteMsg "✅ Executing $toolName..." $token $allowedChatId
                            $consoleSummary.Add("YOU: Allowed $toolName")
                            
                            $toolPath = Join-Path $scriptRootDir "tools/$toolName.ps1"
                            if (-not (Test-Path $toolPath)) { $toolPath = Join-Path $scriptRootDir "more_tools/$toolName.ps1" }
                            
                            $toolResult = "ERROR: Tool not found."
                            if (Test-Path $toolPath) {
                                $c = Get-Content $toolPath -Raw -Encoding UTF8
                                $ToolMeta = $null; Invoke-Expression $c
                                $toolResult = & $ToolMeta.Execute $params
                            }
                            & $SendRemoteMsg "⚙ *Result*: $toolResult" $token $allowedChatId
                            $consoleSummary.Add("RESULT: $toolResult")
                            
                            $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                            $script:history += @{ role = "user";  parts = @(@{ text = "[SYSTEM] TOOL RESULT:`n$toolResult" }) }
                            # Loop continues because $finishedTurn is still false
                        } else {
                            & $SendRemoteMsg "❌ Tool denied." $token $allowedChatId
                            $consoleSummary.Add("YOU: Denied $toolName")
                            $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                            $script:history += @{ role = "user";  parts = @(@{ text = "TOOL RESULT: The user denied this tool call." }) }
                            # Loop continues to get model reaction to denial
                        }
                    } catch {
                        & $SendRemoteMsg "❌ Tool Parse Error: $($_.Exception.Message)" $token $allowedChatId
                        $finishedTurn = $true
                    }
                } else {
                    # 4. Standard Response (No more tools)
                    $script:history += @{ role = "model"; parts = @(@{ text = $modelText }) }
                    $consoleSummary.Add("GEMMA: $modelText")
                    Write-Host " Gemma [Remote]: $modelText" -ForegroundColor Cyan
                    & $SendRemoteMsg $modelText $token $allowedChatId
                    $finishedTurn = $true
                }
            } # End of turn loop
        }
    }

    # ── ACTION: listen ──────────────────────────────────────────────────────
    elseif ($action -eq "listen") {
        Write-Host "`n[REMOTE] Waiting for response from Android (Timeout: ${timeout_sec}s)..." -ForegroundColor Yellow
        $startTime = Get-Date
        $errorCount = 0
        
        # Use session-persistent offset if available to avoid re-processing
        if ($null -eq $script:REMOTE_OFFSET) { $script:REMOTE_OFFSET = 0 }
        
        # Initial sync if offset is 0
        if ($script:REMOTE_OFFSET -eq 0) {
            try {
                $initial = Invoke-RestMethod -Uri "$baseUri/getUpdates?limit=1&offset=-1"
                if ($initial.result.Count -gt 0) { $script:REMOTE_OFFSET = $initial.result[0].update_id + 1 }
            } catch { }
        }

        while (((Get-Date) - $startTime).TotalSeconds -lt $timeout_sec) {
            try {
                # Long-poll for 10 seconds per API request
                $updates = Invoke-RestMethod -Uri "$baseUri/getUpdates?offset=$($script:REMOTE_OFFSET)&timeout=10"
                $errorCount = 0 # Reset on successful connection
                
                foreach ($upd in $updates.result) {
                    # Always advance offset immediately to acknowledge receipt
                    $script:REMOTE_OFFSET = $upd.update_id + 1
                    
                    if ($upd.message.chat.id.ToString() -eq $allowedChatId.ToString()) {
                        return "REMOTE USER RESPONSE: $($upd.message.text)"
                    }
                }
            } catch {
                $errorCount++
                if ($errorCount -gt 3) {
                    return "ERROR: Telegram connection is persistently failing: $($_.Exception.Message)"
                }
                Start-Sleep -Seconds 2 # Backoff on error
            }
            # Short sleep to prevent CPU spiking in tight loops
            Start-Sleep -Milliseconds 200
        }
        return "TIMEOUT: No response received from remote user within $timeout_sec seconds."
    }

    return "ERROR: Unknown action '$action'."
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "remote_bridge"
    Icon        = "📱"
    RendersToConsole = $true
    Interactive      = $true
    RequiresKey      = $true
    KeyUrl           = "https://t.me/BotFather"
    Category    = @("Communication", "Remote Control")
    Behavior    = "Allows you to send updates to the user's Android phone via Telegram and wait for remote instructions. Use this when performing long-running tasks or when you need user approval but the user is away from the terminal."
    Description = "Bridges GemmaCLI to a Telegram bot for remote Android control."
    Parameters  = @{
        action      = "string - required. 'send' (to phone), 'listen' (wait for one reply), 'setup', or 'tunnel' (persistent remote session)."
        message     = "string - optional. Message to send to the phone."
        timeout_sec = "int - optional. How long to wait for a reply in 'listen' mode (default 60)."
    }
    Example     = "<tool_call>{ ""name"": ""remote_bridge"", ""parameters"": { ""action"": ""send"", ""message"": ""Task complete. Proceed to next step?"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.action)" }
    Execute     = { param($params) Invoke-RemoteBridgeTool @params }
    ToolUseGuidanceMajor = @"
        - 'setup': Must be run once by the user to link their Telegram Bot.
        - 'send': Use this to provide status updates to the user's mobile device.
        - 'listen': Use this to pause execution and wait for a command from the user's mobile device.
        - Security: The bridge only accepts messages from the whitelisted ChatID configured during setup.
"@
}
