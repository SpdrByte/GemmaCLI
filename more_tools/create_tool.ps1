# ===============================================
# GemmaCLI Tool - create_tool.ps1 v1.0.0
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

    # Define API Endpoints
    $baseUri = "https://generativelanguage.googleapis.com/v1beta/models"
    $architectUri = "$baseUri/gemini-2.5-pro:generateContent?key=$script:API_KEY"
    $reviewerUri  = "$baseUri/gemini-2.5-flash:generateContent?key=$script:API_KEY"
    $fixerUri     = "$baseUri/gemini-2.5-flash:generateContent?key=$script:API_KEY"
    $synthesisUri = "$baseUri/gemini-2.5-pro:generateContent?key=$script:API_KEY"

    # We need an API call helper that returns just the text, bypassing Start-Job if we're already in a Job
    function Call-LLM($uri, $systemInstruction, $userPrompt, $label) {
        Write-Host "   -> $label" -ForegroundColor DarkGray
        
        $body = @{
            systemInstruction = @{ parts = @( @{ text = $systemInstruction } ) }
            contents = @( @{ role = "user"; parts = @( @{ text = $userPrompt } ) } )
            generationConfig = @{ temperature = 0.4 }
        }
        $json = $body | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        try {
            $resp = Invoke-RestMethod -Uri $uri -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
            $text = $resp.candidates[0].content.parts[0].text
            return $text
        } catch {
            return "API_ERROR: $($_.Exception.Message)"
        }
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
You are an expert PowerShell developer creating tools for GemmaCLI.
A GemmaCLI tool MUST:
1. Define a main function (e.g. Invoke-MyTool).
2. Define a `$ToolMeta` hash table at the bottom with: Name, Description, Behavior, Parameters (hash table), Example, FormatLabel (scriptblock), Execute (scriptblock), ToolUseGuidanceMajor, ToolUseGuidanceMinor.
3. NEVER write anything outside the function and `$ToolMeta`.
4. Output ONLY valid PowerShell code wrapped in ```powershell ```.
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
        $reviewRaw = Call-LLM -uri $reviewerUri -systemInstruction $sysReviewer -userPrompt "Review this code:\n\n```powershell\n$currentCode\n```" -label "Reviewer analyzing code structure..."
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
            $results += "   -> ✅ Linter & Reviewer passed. Code is pristine."
            $isPerfect = $true
            break
        }

        $results += "   -> ❌ Found issues. Sending to Fixer."
        foreach ($issue in $allIssues) {
            $results += "      - $(if($issue.length -gt 100){$issue.substring(0,100)+"..."}else{$issue})"
        }

        # 3. The Fixer (Gemini 2.5 Flash)
        $sysFixer = @"
You are the Fixer. You receive broken PowerShell code and a list of issues.
Fix the code perfectly. Return ONLY the fully fixed PowerShell code wrapped in ```powershell ```.
"@
        $fixPrompt = "Current Code:\n```powershell\n$currentCode\n```\n\nIssues to fix:\n$($allIssues -join "`n")"
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
        $finalRaw = Call-LLM -uri $synthesisUri -systemInstruction $sysArbitrator -userPrompt "Make this code work:\n```powershell\n$currentCode\n```" -label "Arbitrator synthesizing final version..."
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
    Set-Content -Path $outPath -Value $currentCode -Encoding UTF8 -Force

    $results += "`n============================================================"
    $results += " ✅ TOOL CREATION COMPLETE "
    $results += " 📁 Saved to: $outPath"
    $results += " Use '/settings' or move to 'tools/' to enable it."
    $results += "============================================================"

    return $results -join "`n"
}

$ToolMeta = @{
    Name        = "create_tool"
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
        "🛠️ ToolForge -> $(if($p.prompt.length -gt 30){$p.prompt.substring(0,30)+'...'}else{$p.prompt})" 
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