# ===============================================
# GemmaCLI Tool - create_tool.ps1 v1.2.0
# Responsibility: Autonomous Tool Creator via Multi-Agent Evolutionary Pipeline
# Uses native AST parsing and dual-agent feedback loops.
# ===============================================

function Invoke-CreateTool {
    param([string]$prompt)

    $results = @()
    $results += "============================================================"
    $results += " 🤖 TOOL FORGE INITIATED: Evolutionary Multi-Agent Pipeline "
    $results += "============================================================"
    $results += " Goal: $prompt"

    # Define API Endpoints - Balanced for precision and free-tier frequency
    $baseUri = "https://generativelanguage.googleapis.com/v1beta/models"
    $architectUri = "$baseUri/$(Resolve-ModelId 'gemini-fast'):generateContent?key=$script:API_KEY"
    $reviewerUri  = "$baseUri/$(Resolve-ModelId 'gemini-lite'):generateContent?key=$script:API_KEY"
    $fixerUri     = "$baseUri/$(Resolve-ModelId 'gemini-lite'):generateContent?key=$script:API_KEY"
    $synthesisUri = "$baseUri/$(Resolve-ModelId 'gemini-stable-fast'):generateContent?key=$script:API_KEY"

    # We need an API call helper that uses our centralized Invoke-SingleTurnApi for robust rate limiting
    function Call-LLM($uri, $systemInstruction, $userPrompt, $label) {
        $fullPrompt = "SYSTEM INSTRUCTION:`n$systemInstruction`n`nUSER PROMPT:`n$userPrompt"
        
        $result = Invoke-SingleTurnApi `
            -uri $uri `
            -prompt $fullPrompt `
            -spinnerLabel $label `
            -backend "gemini"

        if ($result -match "^ERROR:") {
            return "API_ERROR: $result"
        }
        return $result
    }

    # Extract Code Block
    function Extract-Code($text) {
        if ($text -match '(?s)```powershell\s*(.*?)\s*```') { return $matches[1] }
        if ($text -match '(?s)```ps1\s*(.*?)\s*```') { return $matches[1] }
        if ($text -match '(?s)```\s*(.*?)\s*```') { return $matches[1] }
        return $text
    }

    # Extract JSON Block
    function Extract-Json($text) {
        if ($text -match '(?s)```json\s*(.*?)\s*```') { return $matches[1] }
        if ($text -match '(?s)```\s*(.*?)\s*```') { return $matches[1] }
        return $text
    }

    # 1. The Architect (Gemini 2.5 Pro)
    $results += "`n[PHASE 1] The Architect (Gemini 2.5 Pro) drafting initial code..."
    $sysArchitect = @"
You are an expert PowerShell developer creating tools for GemmaCLI v0.8.0.
A GemmaCLI tool MUST follow this exact structure:

1. HEADER: Start with a standard header:
# ===============================================
# GemmaCLI Tool - [filename].ps1 v1.0.0
# Responsibility: [One sentence description]
# ===============================================

2. WORKER FUNCTION: Define a function 'Invoke-[ToolName]Tool' that does the work.

3. METADATA: Define a `$ToolMeta` hash table at the bottom with:
   - Name: (string, lowercase, no spaces)
   - Description: (string, concise)
   - Category: (array of strings)
   - RendersToConsole: (boolean, set to true ONLY if using Draw-Box/Write-Host directly)
   - RequiresBilling: (boolean, true if using Grounding/Paid features)
   - RequiresKey: (boolean, true if requiring a unique external API key)
   - KeyUrl: (string, URL to get the key if RequiresKey is true)
   - Behavior: (string, detailed reasoning for high-capacity models)
   - Parameters: (hashtable defining inputs)
   - Example: (string showing a <tool_call> example)
   - FormatLabel: (MANDATORY: ScriptBlock { param($p) ... } - DO NOT USE A STRING)
   - Execute: (MANDATORY: ScriptBlock { param($params) Invoke-MyTool @params } - DO NOT USE A STRING)
   - ToolUseGuidanceMajor/Minor: (strings for multi-tier guidance)

4. UI PROTOCOLS (CRITICAL):
   - The CLI uses a split protocol. Content between 'CONSOLE::' and '::END_CONSOLE::' is shown to the HUMAN in grey and STRIPPED from the AI's view.
   - Approach A (Rich UI): Set 'RendersToConsole = $true'. Use 'Draw-Box'. 
     Return: "CONSOLE::[User-facing summary]::END_CONSOLE::[Detailed data for the AI]"
   - Approach B (Simple UI): Set 'RendersToConsole = $false'. 
     Return: "CONSOLE::[User-facing summary]::END_CONSOLE::[Detailed data for the AI]"
   - MANDATORY: You MUST return data for the AI after '::END_CONSOLE::'. If you return an empty string after the delimiter, the AI will see "(empty result)".

5. AUDIO/SYSTEM ALERTS:
   - To trigger sounds, include these in the CONSOLE portion of your return string:
   - PLAY_SOUND:filename (e.g. PLAY_SOUND:tada)
   - BEEP:freq,dur (e.g. BEEP:523,80)

6. NO markdown outside code blocks. Output ONLY valid PowerShell code wrapped in ```powershell ```.
"@
    $draftRaw = Call-LLM -uri $architectUri -systemInstruction $sysArchitect -userPrompt "Create a tool that does the following: $prompt" -label "Drafting initial iteration..."
    $currentCode = Extract-Code $draftRaw

    if ($currentCode -match "API_ERROR") {
        return "ERROR: Architect failed to generate code. $currentCode"
    }

    $results += "   -> Draft generated. ($($currentCode.Length) characters)"

    # Evolutionary Loop
    $maxIterations = 3
    $iteration = 1
    $isPerfect = $false

    while ($iteration -le $maxIterations) {
        $results += "`n[PHASE 2 - Iteration $iteration] Verification & Review..."

        # 2a. Linter / AST Check (Native PowerShell)
        $parseErrors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseInput($currentCode, [ref]$tokens, [ref]$parseErrors)
        
        $astErrors = @()
        if ($parseErrors) {
            foreach ($err in $parseErrors) {
                $astErrors += "Line $($err.Extent.StartLineNumber): $($err.Message)"
            }
        }

        # 2b. The Reviewer (Gemini 2.5 Flash)
        $sysReviewer = @"
You are the strict GemmaCLI Screener. Review the following PowerShell code for a GemmaCLI tool.
Check for:
1. Valid `$ToolMeta` block presence.
2. Required fields in `$ToolMeta`: Name, Description, Parameters, Execute.
3. Safety and sanity (no highly destructive unprompted commands).
If it's perfect, output: ````json {"status": "pass", "issues": []} ````
If there are issues, output: ````json {"status": "fail", "issues": ["issue 1", "issue 2"]} ````
Output ONLY JSON.
"@
        $revPrompt = @"
Review this code:

```powershell
$currentCode
```
"@
        $reviewRaw = Call-LLM -uri $reviewerUri -systemInstruction $sysReviewer -userPrompt $revPrompt -label "Reviewer analyzing code structure..."
        $reviewJsonStr = Extract-Json $reviewRaw
        
        $reviewObj = $null
        try {
            $reviewObj = $reviewJsonStr | ConvertFrom-Json
        } catch {
            $reviewObj = @{ status = "fail"; issues = @("Reviewer failed to output valid JSON.") }
        }

        $allIssues = @()
        if ($astErrors.Count -gt 0) {
            $allIssues += "AST Syntax Errors:`n" + ($astErrors -join "`n")
        }
        if ($reviewObj.status -ne "pass" -and $reviewObj.issues) {
            $allIssues += "Structural/Logic Issues:`n" + ($reviewObj.issues -join "`n")
        }

        if ($allIssues.Count -eq 0) {
            $results += "   -> $([char]0x2705) Linter and Reviewer passed. Code is pristine."
            $isPerfect = $true
            break
        }

        $results += "   -> $([char]0x274C) Found issues. Sending to Fixer."
        foreach ($issue in $allIssues) {
            $results += "      - $(if($issue.length -gt 100){$issue.substring(0,100)+"..."}else{$issue})"
        }

        # 3. The Fixer (Gemini 2.5 Flash)
        $sysFixer = @"
You are the Fixer. You receive broken PowerShell code and a list of issues.
Fix the code perfectly. Return ONLY the fully fixed PowerShell code wrapped in ```powershell ```.
"@
        $issuesStr = $allIssues -join "`n"
        $fixPrompt = @"
Current Code:
```powershell
$currentCode
```

Issues to fix:
$issuesStr
"@
        $fixRaw = Call-LLM -uri $fixerUri -systemInstruction $sysFixer -userPrompt $fixPrompt -label "Fixer applying patches..."
        
        $patchedCode = Extract-Code $fixRaw
        if (-not ($patchedCode -match "API_ERROR")) {
            $currentCode = $patchedCode
        }

        $iteration++
    }

    # 4. Final Synthesis Arbitrator (Gemini 2.5 Pro) if not perfect
    if (-not $isPerfect) {
        $results += "`n[PHASE 3] Arbitration (Gemini 2.5 Pro) for final synthesis..."
        $sysArbitrator = @"
You are the Master Arbitrator. The previous agents failed to achieve a perfect script after multiple iterations.
Fix any remaining issues and output the absolute best, final version of this PowerShell GemmaCLI tool.
Output ONLY the raw PowerShell code wrapped in ```powershell ```.
"@
        $finalPrompt = @"
Make this code work:
```powershell
$currentCode
```
"@
        $finalRaw = Call-LLM -uri $synthesisUri -systemInstruction $sysArbitrator -userPrompt $finalPrompt -label "Arbitrator synthesizing final version..."
        $finalCode = Extract-Code $finalRaw
        if (-not ($finalCode -match "API_ERROR")) {
            $currentCode = $finalCode
        }
    }

    # 5. Save the Tool
    $toolNameMatch = $currentCode -match 'Name\s*=\s*"([^"]+)"'
    if ($toolNameMatch) {
        $toolName = $matches[1]
    } else {
        $toolName = "auto_tool_$(Get-Random -Minimum 1000 -Maximum 9999)"
    }
    
    # Save into more_tools so it doesn't immediately activate and crash if something is wrong
    $outDir = Join-Path $scriptDir "more_tools"
    if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
    
    $outPath = Join-Path $outDir "$toolName.ps1"
    # Use .NET to ensure UTF-8 WITH BOM, mandatory for PS 5.1 emoji support
    [System.IO.File]::WriteAllText($outPath, $currentCode, [System.Text.UTF8Encoding]::new($true))

    $results += "`n============================================================"
    $results += " $([char]0x2705) TOOL CREATION COMPLETE "
    $results += " 📁 Saved to: $outPath"
    $results += " Use '/settings' or move to 'tools/' to enable it."
    $results += "============================================================"

    return $results -join "`n"
}

$ToolMeta = @{
    Name        = "create_tool"
    Icon        = "🛠️"
    RendersToConsole = $false
    Category    = @("Coding/Development")
    Behavior    = "Autonomous Tool Creator. Use this when the user asks you to 'create a tool that does X'. This tool orchestrates a multi-agent pipeline to generate, parse, review, and fix a complete .ps1 tool script before saving it to the more_tools folder."
    Description = "Generates and verifies a new GemmaCLI tool using an evolutionary multi-agent loop with AST parsing."
    Parameters  = @{
        prompt = "string - The instruction describing what the new tool should do."
    }
    Example     = "<tool_call>{ `"name`": `"create_tool`", `"parameters`": { `"prompt`": `"A tool that fetches the weather using wttr.in`" } }</tool_call>"
    FormatLabel = { 
        param($p) 
        "ToolForge -> $(if($p.prompt.length -gt 30){$p.prompt.substring(0,30)+'...'}else{$p.prompt})" 
    }
    Execute     = {
        param($params)
        Invoke-CreateTool -prompt $params.prompt
    }
    ToolUseGuidanceMajor = @"
        - When to use 'create_tool': Use this tool strictly when the user specifically requests the creation of a new capability, plugin, or tool for the CLI.
        - Important parameters:
            - `prompt`: Provide a highly detailed description of the tool's intended functionality, inputs, and outputs so the Architect agent can build it.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Automatically build, verify, and save a new GemmaCLI tool.
        - The tool handles its own compilation checks and saves to 'more_tools/'.
"@
}
