# tools/tutorial.ps1 v0.6.0
# Responsibility: High-fidelity "Terminal Instructor" for GemmaCLI.
#                 Conversational onboarding with verification gates.

function Invoke-TutorialTool {
    param(
        [string]$action = "start",
        [string]$tool_name = "",
        [string]$current_tools_dir = "" 
    )

    $esc = [char]27
    $reset = "$esc[0m"
    
    # ── Path Setup ───────────────────────────────────────────────────────────
    $appData = Join-Path $env:APPDATA "GemmaCLI"
    if (-not (Test-Path $appData)) { New-Item -Path $appData -ItemType Directory -Force | Out-Null }
    $trackPath = Join-Path $appData "tutorials_completed.json"
    
    if (-not (Test-Path $trackPath)) { 
        @{ 
            system_level = 1
            logistics_done = $false
            tools_learned = @()
            graduation_level = 0
        } | ConvertTo-Json | Set-Content $trackPath 
    }
    
    $state = Get-Content $trackPath | ConvertFrom-Json

    # ── Action: Complete (Tool Mastery) ─────────────────────────────────────
    if ($action -eq "complete") {
        if ($tool_name -and $tool_name -notin $state.tools_learned) {
            $state.tools_learned += $tool_name
        }
        # If model calls 'complete' during Bootcamp, advance level to prevent looping
        if ($state.system_level -le 6) { 
            $state.system_level++ 
            if ($state.system_level -eq 7) {
                $state.logistics_done = $false
                $state.graduation_level = 0
            }
        }
        $state | ConvertTo-Json | Set-Content $trackPath
        # Fall through to return next challenge
    }

    # ── Action: Next Level (Command Mastery) ────────────────────────────────
    if ($action -eq "next_level") {
        if ($state.graduation_level -gt 0) {
            $state.graduation_level++
        } elseif ($state.logistics_done) {
            # In Stage 2 (Tools), completion is handled by action='complete'
        } elseif ($state.system_level -lt 7) {
            $state.system_level++
            if ($state.system_level -eq 7) { 
                $state.logistics_done = $false 
                $state.graduation_level = 0
            }
        }
        $state | ConvertTo-Json | Set-Content $trackPath
        # Fall through to return next module
    }

    # ── Action: Reset ───────────────────────────────────────────────────────
    if ($action -eq "reset") {
        Remove-Item $trackPath -Force
        return "OK: Progress wiped. Instructor initialized for fresh start."
    }

    # ── Logic: Stage 0 (System Bootcamp) ────────────────────────────────────
    if ($state.system_level -le 6) {
        $level = $state.system_level

        # ── Level 1: Welcome + /help ─────────────────────────────────────────
        if ($level -eq 1) {
            $msg = @"
INSTRUCTOR SCRIPT — LEVEL 1 (Welcome + /help)
==============================================
You are now the GemmaCLI Terminal Instructor. Adopt a warm but professional tone.
Do NOT say "I understand" or "Okay." Do NOT reference XML, back-end logic, or documentation.
Do NOT repeat the full workstation briefing — it is already in the system prompt.

YOUR OPENING LINE:
"Welcome to GemmaCLI! I'll be your guide for the next few minutes. Let's start with the most
useful command you'll ever need: /help. Type /help now and press Enter. 
Let me know once you've had a look — I'll walk you through the key sections."

THEN WAIT for the user to respond that they've run it.

VERIFICATION: Once they confirm they have viewed the help menu, acknowledge it and proceed.

ONCE VERIFIED: Call 'tutorial' with action='next_level'.

ROLE GUARD: Only discuss the CLI interface. Do not ask about XML tags or the tool system internals.
"@
            return "CONSOLE::Bootcamp Level 1 — Welcome...::END_CONSOLE::$msg"
        }

        # ── Level 2: /speak ──────────────────────────────────────────────────
        if ($level -eq 2) {
            $msg = @"
INSTRUCTOR SCRIPT — LEVEL 2 (/speak — Voice)
=============================================
TONE: Enthusiastic but brief. This is a fun feature.

SCRIPT STYLE:
"GemmaCLI has a built-in text-to-speech system. Type /speak female (or /speak male) and 
I'll start reading my responses aloud. Give it a try now — type /speak female."

THEN WAIT for them to confirm they've tried it.

VERIFICATION: Once they confirm they hear you, proceed to the next module.

ONCE VERIFIED: Call 'tutorial' with action='next_level'.

ROLE GUARD: Only discuss voice features. Do not reference XML or internal tool mechanics.
"@
            return "CONSOLE::Bootcamp Level 2 — Voice...::END_CONSOLE::$msg"
        }

        # ── Level 3: /listen ──────────────────────────────────────────────────
        if ($level -eq 3) {
            $msg = @"
INSTRUCTOR SCRIPT — LEVEL 3 (/listen — Voice Input)
========================================================
TONE: Informative. This enables hands-free mode.

SCRIPT STYLE:
"GemmaCLI can also listen. Type /listen to enable the microphone. Once active, you can 
speak your prompts directly. The CLI will transcribe them using STT engine.
Try it now: type /listen and then say 'Gemma is my workstation'."

THEN WAIT for the transcribed message to appear.

VERIFICATION: Once you receive the transcribed phrase "Gemma is my workstation", acknowledge that you heard them and proceed.

ONCE VERIFIED: Call 'tutorial' with action='next_level'.
"@
            return "CONSOLE::Bootcamp Level 3 — Listening...::END_CONSOLE::$msg"
        }

        # ── Level 4: /settings ───────────────────────────────────────────────────
        if ($level -eq 4) {
            $msg = @"

INSTRUCTOR SCRIPT — LEVEL 5 (/settings — The Control Hub)
==========================================================
TONE: Confident. This is the master control panel.

SCRIPT STYLE:
"Almost everything in GemmaCLI is configurable from one place: /settings. 
Color themes, which tools are active, context window size, TTS options — all here.
Type /settings now and navigate to 'Colors'. Use the arrow keys and Enter to select."

THEN WAIT for them to confirm.

VERIFICATION: Once they confirm they've explored the settings, proceed to the next module by calling action='next_level'.



"@
            return "CONSOLE::Bootcamp Level 4 — Settings...::END_CONSOLE::$msg"
        }

        # ── Level 5: /trim ───────────────────────────────────────────────────
        if ($level -eq 5) {
            $msg = @"
INSTRUCTOR SCRIPT — LEVEL 4 (/trim — Memory Control)
=====================================================
TONE: Technical but accessible. This is a key differentiator.

SCRIPT:
"Long conversations eat into your context window. GemmaCLI uses 'Smart Trim' — a semantic 
compression system that keeps the most relevant parts of our conversation active and quietly 
prunes the rest. You can also trigger it manually with /trim. You can configure trim options in the /settings. Let's
check settings to make sure Smart Trim is set to 'Enabled' - /Settings > Smart Trim > Enabled. Press esc to close menu if it is Enabled, or press enter to 
enable it. Let me know when you are ready to move forward!"

THEN WAIT for them to confirm.

VERIFICATION: Once they confirm they've run /settings > smart trim, proceed to the next module by calling action='next_level'.

"@
            return "CONSOLE::Bootcamp Level 5 — Memory...::END_CONSOLE::$msg"
        }

        # ── Level 6: Ctrl+Click (OSC 8 Hyperlinks) ───────────────────────────
        if ($level -eq 6) {
            $msg = @"
INSTRUCTOR SCRIPT — LEVEL 6 (Ctrl+Click — Hyperlinks)
======================================================
TONE: Practical. This saves real time.

SCRIPT STYLE:
"One last trick before we move to tools: any file path or URL I print in this terminal 
is a live hyperlink. Hold Ctrl and click it to open it instantly — no copy-pasting needed.
Here's a live example for you to try right now."

THEN OUTPUT this path as a clickable hyperlink (the main loop will hyperlink-ify it automatically):
C:\Users\Public\Documents

Then say: "Ctrl+Click that path. It should open File Explorer directly."

THEN WAIT for them to confirm.

VERIFICATION: Once they confirm File Explorer opened, proceed to the next stage.

ONCE VERIFIED: Call 'tutorial' with action='next_level'.
"@
            return "CONSOLE::Bootcamp Level 6 — Hyperlinks...::END_CONSOLE::$msg"
        }
    }

    # ── Logic: Stage 1 (Logistics Phase) ────────────────────────────────────
    if (-not $state.logistics_done) {
        $activeTools = Get-ChildItem -Path $current_tools_dir -Filter "*.ps1" | Where-Object { $_.BaseName -ne "tutorial" }
        $hasRead = $activeTools | Where-Object { $_.BaseName -eq "readfile" }
        $hasSearch = $activeTools | Where-Object { $_.BaseName -eq "searchdir" }

        if (-not $hasRead -or -not $hasSearch) {
            $msg = @"
INSTRUCTOR SCRIPT — STAGE 1 (Enable Core Tools)
================================================
TONE: Matter-of-fact.

SCRIPT STYLE:
"Before we go hands-on with tools, we need to enable two of them.
Go to /settings -> 'Tools' and switch on both 'readfile' and 'searchdir'.
Once done, type /exit and relaunch GemmaCLI. I'll detect them automatically when you're back."

Do NOT proceed or ask verification questions. Simply wait for the user to re-launch.
I will verify the physical presence of these tool files on the next session start.
"@
            return "CONSOLE::Waiting for tool activation...::END_CONSOLE::$msg"
        } else {
            $state.logistics_done = $true
            $state.graduation_level = 1
            $state | ConvertTo-Json | Set-Content $trackPath
            # Fall through to Stage 2
        }
    }

    # ── Logic: Stage 2 (Field Lab) ──────────────────────────────────────────
    $activeTools = Get-ChildItem -Path $current_tools_dir -Filter "*.ps1" | Where-Object { $_.BaseName -ne "tutorial" }
    $unlearned = $activeTools | Where-Object { $_.BaseName -notin $state.tools_learned }

    if ($unlearned.Count -gt 0) {
        $tFile = $unlearned[0]
        $tutorialContent = "No specific tutorial metadata found."
        $ver = "0.0.0"
        try {
            $content = Get-Content $tFile.FullName -Raw -Encoding UTF8
            if ($content -match "v(\d+\.\d+\.\d+)") { $ver = $matches[1] }
            $meta = New-Module -AsCustomObject -ScriptBlock ([scriptblock]::Create($content))
            if ($meta.ToolMeta.Tutorial) { $tutorialContent = $meta.ToolMeta.Tutorial }
        } catch { }

        $msg = @"
INSTRUCTOR SCRIPT — FIELD LAB: $($tFile.BaseName) (v$ver)
==========================================================
TOOL METADATA: $tutorialContent

TONE: Direct challenge. No hand-holding — the user has earned this.

SCRIPT STYLE:
"Alright — time to use a real tool. Here's your challenge:"

CHALLENGES BY TOOL:
- searchdir: "Find all .json files in your Documents folder. Ask me to search for them."
- readfile:  "Read a text file of your choice. Give me a path and I'll read it."
- writefile: "Ask me to write a short note to a file called test_output.txt."
- For any other tool: Invent a clear, practical challenge that proves real usage.

MISSION:
1. Present the challenge clearly.
2. Wait for the user to trigger the actual tool call (it must execute successfully).
3. ONCE SUCCESSFUL: Call 'tutorial' with action='complete' and tool_name='$($tFile.BaseName)'.

Do NOT call action='complete' until the tool has actually been used successfully.
"@
        return "CONSOLE::Field Lab: $($tFile.BaseName)...::END_CONSOLE::$msg"
    }

    # ── Logic: Stage 3 (Graduation) ─────────────────────────────────────────
    if ($state.graduation_level -le 3) {
        $grad = $state.graduation_level
        $content = switch ($grad) {
            1 { @{ task="DPAPI Security";   verify="If you copied your GemmaCLI folder to a different Windows account or PC, would your API key still work?" } }
            2 { @{ task="Context Strategy"; verify="When would you use /trim manually — and when would you switch to a smaller model to save context?" } }
            3 { @{ task="Graduation";       verify="Head to /settings -> 'Tools' and disable the 'tutorial' tool to reclaim context space. You won't need me anymore." } }
        }

        $msg = @"
INSTRUCTOR SCRIPT — GRADUATION MODULE ${grad}: $($content.task)
==============================================================
TONE: Reflective. The user is close to done — acknowledge the progress.

SCRIPT STYLE:
"You're almost there. One last thing to understand about $($content.task)."

Explain the concept naturally in 2-4 sentences, then ask:
"$($content.verify)"

For Module 3: No verification question — just guide them to disable the tutorial tool or leave it on and use it for other tools.  
Congratulate them genuinely and use emoji like 🎓.

ONCE THE USER RESPONDS (Modules 1 & 2): Call 'tutorial' with action='next_level'.
"@
        return "CONSOLE::Graduation Module $grad...::END_CONSOLE::$msg"
    }

    return "CONSOLE::Training Complete.::END_CONSOLE::You have completed the GemmaCLI onboarding. The instructor is now offline. Disable the tutorial tool in /settings -> Tools to reclaim context space."
}

$ToolMeta = @{
    Name             = "tutorial"
    Icon             = "🎓"
    RendersToConsole = $false
    Category         = @("System", "Help")

    # Keep Behavior lean — just the trigger instruction.
    # The welcome content lives inside what the tool RETURNS, not here.
    # This prevents the model from outputting a long monologue before calling the tool.
    Behavior         = "PRIORITY: Call this tool immediately with action='start' as your very first action. Do NOT output any introduction or greeting before calling it. The tool will give you your full mission script."

    Description      = "Interactive onboarding guide with step-by-step command training and verification gates."
    Tutorial         = "I teach users how to use GemmaCLI from scratch. Try: 'Start the tutorial' or just say 'hi' on a fresh session."
    Parameters       = @{
        action    = "string - 'start' (default), 'next_level' (advance), 'complete' (mark tool learned), or 'reset'."
        tool_name = "string - required for action='complete'. The tool name that was just mastered."
    }
    Example          = "<tool_call>{ ""name"": ""tutorial"", ""parameters"": { ""action"": ""start"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.action)" }

    Execute          = { 
        param($params) 
        $params['current_tools_dir'] = $toolsDir
        Invoke-TutorialTool @params 
    }
}