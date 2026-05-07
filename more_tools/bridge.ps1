# ===============================================
# GemmaCLI Tool - bridge.ps1 v1.1.1
# Responsibility: Facilitates async communication via a filesystem-based mailbox.
# ===============================================

function Invoke-BridgeTool {
    param (
        [ValidateSet("check-inbox", "send-message", "bridge-status", "agent-prompt")]
        [string]$Action,

        [string]$Message,
        [string]$To = "broadcast",
        [string]$From = "gemma",
        [string]$ReplyTo = "",
        [ValidateRange(1, 100)]
        [int]$Limit = 10,
        [ValidateSet("chat", "tool_request", "status", "broadcast", "urgent")]
        [string]$Type = "chat"
    )

    # 1. Pathing Setup — GemmaCLI.ps1 sets $scriptDir in global scope on launch
    $GemmaRoot = $global:scriptDir
    if (-not $GemmaRoot) { $GemmaRoot = "." }

    $BridgePath = Join-Path $GemmaRoot "bridge"
    $InboxPath  = Join-Path $BridgePath "inbox"
    $OutboxPath = Join-Path $BridgePath "outbox"
    $ErrorPath  = Join-Path $BridgePath "error"

    # 2. Ensure Directories Exist
    foreach ($dir in @($InboxPath, $OutboxPath, $ErrorPath)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    $ConsoleOutput = ""
    $AIData        = ""

    switch ($Action) {
        "check-inbox" {
            $Files = Get-ChildItem -Path $InboxPath -Filter *.json -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime |
                     Select-Object -First $Limit

            if ($Files.Count -eq 0) {
                $ConsoleOutput = "BEEP:440,100`nNo new messages found in the inbox."
                $AIData        = "No new messages from external sources."
            }
            else {
                $Results      = @()
                $Processed    = 0
                $Failed       = 0

                foreach ($File in $Files) {
                    try {
                        $Content = Get-Content $File.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

                        # Build a readable summary
                        $FromStr  = if ($Content.from) { $Content.from } else { "unknown" }
                        $ToStr    = if ($Content.to)   { $Content.to }   else { "broadcast" }
                        $TypeStr  = if ($Content.type) { $Content.type } else { "chat" }
                        $MsgBody  = if ($Content.message) { $Content.message } else { "[no body]" }
                        $Ts       = if ($Content.timestamp) { $Content.timestamp } else { $File.LastWriteTime }

                        $Results += "[$($File.Name)] From: $FromStr → $ToStr | Type: $TypeStr | Time: $Ts`n  $MsgBody"

                        # Successfully parsed — safe to delete
                        Remove-Item $File.FullName -Force -ErrorAction Stop
                        $Processed++
                    }
                    catch {
                        # Parse or read failure — move to error/ instead of deleting
                        $errFile = Join-Path $ErrorPath $File.Name
                        try {
                            Move-Item $File.FullName $errFile -Force -ErrorAction Stop
                        }
                        catch {
                            # Last resort: rename in-place so we don't reprocess forever
                            $renamed = Join-Path $InboxPath "$($File.BaseName)_CORRUPTED_$((Get-Date).Ticks)$($File.Extension)"
                            Rename-Item $File.FullName $renamed -Force -ErrorAction SilentlyContinue
                        }
                        $Results += "[Error] Failed to parse $($File.Name) → moved to error/"
                        $Failed++
                    }
                }

                $ConsoleOutput = "Processed $Processed message(s); $Failed failed. BEEP:880,150"
                $AIData        = $Results -join "`n---`n"
            }
        }

        "send-message" {
            if ([string]::IsNullOrWhiteSpace($Message)) {
                return "CONSOLE::ERROR: Message cannot be empty.::END_CONSOLE::Error: Message parameter missing."
            }

            $Timestamp = Get-Date -Format "o"
            $ShortId   = [Guid]::NewGuid().ToString("N").Substring(0, 8)
            $FileName  = "$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')_${ShortId}.json"
            $FilePath  = Join-Path $OutboxPath $FileName
            $TempPath  = "$FilePath.tmp"

            $Payload = @{
                id        = $ShortId
                timestamp = $Timestamp
                from      = $From
                to        = $To
                type      = $Type
                message   = $Message
            }

            if (-not [string]::IsNullOrWhiteSpace($ReplyTo)) {
                $Payload['reply_to'] = $ReplyTo
            }

            try {
                # Atomic write: temp file → rename
                $Payload | ConvertTo-Json -Depth 3 | Out-File -FilePath $TempPath -Encoding utf8 -ErrorAction Stop
                Move-Item $TempPath $FilePath -Force -ErrorAction Stop

                $ConsoleOutput = "Message placed in outbox ($FileName). PLAY_SOUND:tada"
                $AIData        = "Message sent to '$To' at $Timestamp. ID: $ShortId | File: $FileName"
            }
            catch {
                # Clean up temp if it exists
                if (Test-Path $TempPath) { Remove-Item $TempPath -Force -ErrorAction SilentlyContinue }
                return "CONSOLE::ERROR: Failed to write message — $($_.Exception.Message)::END_CONSOLE::Error: Could not write to outbox."
            }
        }

        "bridge-status" {
            $inboxCount  = (Get-ChildItem $InboxPath  -Filter *.json -ErrorAction SilentlyContinue).Count
            $outboxCount = (Get-ChildItem $OutboxPath -Filter *.json -ErrorAction SilentlyContinue).Count
            $errorCount  = (Get-ChildItem $ErrorPath  -Filter *.json -ErrorAction SilentlyContinue).Count
            $now         = Get-Date -Format "HH:mm:ss"

            $ConsoleOutput = "Bridge status — Inbox: $inboxCount | Outbox: $outboxCount | Errors: $errorCount"
            $AIData        = "Bridge status at $now`: Inbox=$inboxCount, Outbox=$outboxCount, Error=$errorCount."
        }

        "agent-prompt" {
            $Prompt = @"
You are connected to GemmaCLI via a filesystem-based bridge. The bridge directory is located at:
  $BridgePath

DIRECTORY STRUCTURE:
  $InboxPath   <- Write here to SEND messages TO GemmaCLI
  $OutboxPath  <- Read here to RECEIVE messages FROM GemmaCLI
  $ErrorPath   <- Corrupted messages are quarantined here

MESSAGE FORMAT (JSON):
  {
    "id": "unique_msg_id",
    "timestamp": "2026-04-21T20:00:00Z",
    "from": "kimi",
    "to": "gemma",
    "type": "chat",
    "message": "Your message text here",
    "reply_to": "optional_parent_id"
  }

HOW TO SEND A MESSAGE TO GemmaCLI:
  1. Create a JSON file matching the format above.
  2. Write it to: $InboxPath
  3. Use this filename pattern: yyyyMMdd_HHmmss_fff_shortguid.json
  4. GemmaCLI will pick it up on its next inbox check and delete it.

HOW TO RECEIVE A MESSAGE FROM GemmaCLI:
  1. Poll: $OutboxPath for new *.json files.
  2. Read each file, note the "from" and "to" fields.
  3. Delete or archive the file after reading (GemmaCLI does not auto-delete outbox files).

POWERSHELL EXAMPLES:
  # Send a message
  `$msg = @{ id=(New-Guid).ToString().Substring(0,8); timestamp=(Get-Date -Format "o"); from="kimi"; to="gemma"; type="chat"; message="Hello" } | ConvertTo-Json`
  `$msg | Out-File "$InboxPath\$(Get-Date -Format 'yyyyMMdd_HHmmss_fff')_kimi.json" -Encoding utf8`

  # Check for replies
  Get-ChildItem "$OutboxPath\*.json" | Sort-Object LastWriteTime | ForEach-Object { Get-Content `$_.FullName | ConvertFrom-Json }

RULES:
- Messages in inbox/ are consumed (deleted) by GemmaCLI after reading.
- Messages in outbox/ are NOT auto-deleted — you must clean them up.
- Use "reply_to" to thread conversations.
- Valid types: chat, tool_request, status, broadcast, urgent.
"@

            $ConsoleOutput = "Agent prompt generated. Copy the text below into your agent's system prompt."
            $AIData        = $Prompt
        }
    }

    return "CONSOLE::$ConsoleOutput::END_CONSOLE::$AIData"
}

$ToolMeta = @{
    Name             = "bridge"
    Icon             = "🌉"
    Version          = "1.1.1"
    Interactive      = $false
    Description      = "Asynchronous filesystem-based mailbox for inter-AI communication."
    Keywords         = ""
    Category         = @("Communication", "System")
    RendersToConsole = $true
    RequiresBilling  = $false
    RequiresKey      = $false
    KeyUrl           = ""
    Behavior         = @"
This tool manages a local inbox/outbox system for coordination with Kimi, AIBrowser, and other external processes.

- check-inbox: Reads up to 'Limit' JSON messages from bridge/inbox, then deletes them atomically.
  Failed parses are moved to bridge/error/ instead of being lost.
- send-message: Writes a structured JSON message to bridge/outbox with from/to/type headers.
  Uses atomic temp-file + rename to avoid Windows file-locking issues.
- bridge-status: Returns counts of pending messages without consuming any.
- agent-prompt: Generates a copy-paste system prompt that teaches an external agent how to use this bridge.

All messages carry 'id', 'timestamp', 'from', 'to', 'type', and 'message' fields.
Use 'reply_to' when responding to a specific prior message.
"@
    Parameters       = @{
        Action   = "The operation: 'check-inbox' (read/clear), 'send-message' (write), 'bridge-status' (count only), or 'agent-prompt' (generate onboarding instructions for an external agent)."
        Message  = "The text content to send (required for 'send-message')."
        To       = "Recipient tag: 'kimi', 'browser', 'broadcast', etc. Default: 'broadcast'."
        From     = "Sender tag. Default: 'gemma'."
        ReplyTo  = "Message ID being replied to, for threading."
        Limit    = "Max messages to process in one call (1-100). Default: 10."
        Type     = "Message category: chat, tool_request, status, broadcast, urgent. Default: chat."
    }
    Example          = "<tool_call> {`"name`": `"bridge`", `"arguments`": {`"Action`": `"send-message`", `"To`": `"kimi`", `"Message`": `"Task completed. Ready for next instruction.`"}} </tool_call>"
    FormatLabel      = {
        param($params)
        $Action = $params.Action
        $Target = if ($params.To) { " → $($params.To)" } else { "" }
        return "Bridge: $Action$Target"
    }
    Execute          = {
        param($params)
        Invoke-BridgeTool @params
    }
    ToolUseGuidanceMajor = "Use 'bridge-status' first to see if traffic exists, then 'check-inbox' to consume messages. Use 'send-message' with explicit 'To' and 'ReplyTo' for threaded conversations. When connecting a new external agent, call 'agent-prompt' first and give the result to the agent as its system prompt."
    ToolUseGuidanceMinor = "Messages are deleted immediately upon successful read. Failed parses are quarantined in bridge/error/. Always use atomic temp-write + rename when producing files."
}
