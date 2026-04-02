# lib/ToolLoader.ps1
# Responsibility: Finds, validates, and loads all available tools.

function Get-ToolInstructions {
    param(
        [string]$ScriptRoot,
        [string]$Model,
        [hashtable]$ToolLimits
    )

    $script:TOOLS = @{}
    $toolsDir = Join-Path $ScriptRoot "tools"
    if (-not (Test-Path $toolsDir)) { return "" }

    Get-ChildItem -Path $toolsDir -Filter "*.ps1" | ForEach-Object {
        try {
            $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8
            # Execute the tool script to populate $ToolMeta
            # This is a safe execution as the tool scripts are part of the project
            # and expected to define $ToolMeta
            Invoke-Expression -Command $content
            
            if ($ToolMeta) {
                $script:TOOLS[$ToolMeta.Name] = $ToolMeta
                Write-Host "  [OK] Loaded tool: $($ToolMeta.Name)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [FAIL] Error loading tool $($_.FullName): $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            $ToolMeta = $null # Clear $ToolMeta for the next tool script
        }
    }
    # Write-Host "Loaded $($script:TOOLS.Count) tool(s)." # Commenting out for cleaner output

    # Define model tiers for guidance
    $majorModels = @("gemma-3-27b-it", "gemma-3-12b-it")
    $minorModels = @("gemma-3-4b-it", "gemma-3n-e4b-it", "gemma-3n-e2b-it", "gemma-3-1b-it")

    # Determine if the current model is a major or minor model
    $isMajorModel = $majorModels -contains $Model
    $isMinorModel = $minorModels -contains $Model

    # Dynamic Prompt Generation
    $toolLimit = if ($null -ne $ToolLimits[$Model]) { $ToolLimits[$Model] } else { 0 }
    $toolInstructions = @()
    # Filter tools based on the model's tool limit and sort by name for consistent output
    $toolsToLoad = $script:TOOLS.Values | Where-Object { $_.Name -ne $null } | Sort-Object Name | Select-Object -First $toolLimit

    foreach ($tool in $toolsToLoad) {
        $instruction = ""
        $instruction += "### Tool: $($tool.Name)`n"
        $instruction += "**Description:** $($tool.Description)`n"
        
        # Add Parameters for all models
        if ($tool.Parameters) {
            $instruction += "**Parameters:**`n"
            $tool.Parameters.GetEnumerator() | ForEach-Object { $instruction += "  - $($_.Name): $($_.Value)`n" }
        }

        # Add Example for all models (if available)
        if ($tool.Example) {
            $instruction += "**Example:** $($tool.Example)`n"
        }

        # Add guidance based on model tier
        if ($isMajorModel -and $tool.ToolUseGuidanceMajor) {
            $instruction += "**Usage Guidance (Detailed):**`n"
            $instruction += "$($tool.ToolUseGuidanceMajor)`n"
        } elseif ($isMinorModel -and $tool.ToolUseGuidanceMinor) {
            $instruction += "**Usage Guidance (Simplified):**`n"
            $instruction += "$($tool.ToolUseGuidanceMinor)`n"
        }
        
        $instruction += "`n" # Add an extra newline for separation between tools
        $toolInstructions += $instruction
    }

    return ($toolInstructions -join "`n")
}

function Get-ToolsSummary {
    param(
        [string]$ScriptRoot,
        [string]$Mode = "enabled" # enabled, disabled, all
    )

    $chk = [char]0x2713
    $crs = [char]0x2717
    $arr = [char]0x2192
    
    $results = @()
    $toolsDir = Join-Path $ScriptRoot "tools"
    $moreToolsDir = Join-Path $ScriptRoot "more_tools"

    $folders = @()
    if ($Mode -eq "enabled" -or $Mode -eq "all") { $folders += @{ Path = $toolsDir; Icon = $chk; Label = "Enabled" } }
    if ($Mode -eq "disabled" -or $Mode -eq "all") { $folders += @{ Path = $moreToolsDir; Icon = $crs; Label = "Disabled" } }

    foreach ($folder in $folders) {
        if (Test-Path $folder.Path) {
            Get-ChildItem -Path $folder.Path -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
                try {
                    $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8
                    $ToolMeta = $null
                    # Lightweight execution to get metadata only
                    Invoke-Expression -Command $content
                    if ($ToolMeta) {
                        $params = if ($ToolMeta.Parameters) { 
                            "(" + (($ToolMeta.Parameters.Keys | ForEach-Object { $_ }) -join ", ") + ")" 
                        } else { "" }
                        
                        $results += "$($folder.Icon)  $($ToolMeta.Name)$params [$($folder.Label)]"
                        $results += "     $arr  $($ToolMeta.Description)"
                        $results += ""
                    }
                } catch { }
            }
        }
    }

    if ($results.Count -eq 0) {
        $results += "No tools found in category: $Mode"
    }

    return $results
}
