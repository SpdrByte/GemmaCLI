# lib/ToolLoader.ps1 v0.1.4
# Responsibility: Finds, validates, and loads all available tools.

$script:TOOLS = @{}
$script:TOOL_CACHE = @{} # Persistent cache for all metadata (enabled and disabled)

function Get-ToolInstructions {
    param(
        [string]$ScriptRoot,
        [string]$Model,
        [hashtable]$ToolLimits
    )

    $script:TOOLS = @{}
    $toolsDir = Join-Path $ScriptRoot "tools"
    $moreToolsDir = Join-Path $ScriptRoot "more_tools"
    if (-not (Test-Path $toolsDir)) { return "" }

    # Get count of inactive tools for Latent Awareness
    $script:INACTIVE_COUNT = 0
    if (Test-Path $moreToolsDir) {
        $script:INACTIVE_COUNT = (Get-ChildItem -Path $moreToolsDir -Filter "*.ps1").Count
    }

    $wrn = [char]0x26A0
    
    Get-ChildItem -Path $toolsDir -Filter "*.ps1" | ForEach-Object {
        try {
            # Execute with explicit UTF8 to avoid Mojibake in PowerShell 5.1
            $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8
            $ToolMeta = $null
            Invoke-Expression -Command $content
            
            if ($ToolMeta) {
                # Inject default icon if missing
                if (-not $ToolMeta.Icon) { $ToolMeta.Icon = [char]0x25CF } # $DOT
                $script:TOOLS[$ToolMeta.Name] = $ToolMeta
                $script:TOOL_CACHE[$ToolMeta.Name] = $ToolMeta # Cache it
                Write-Host "  [OK] Loaded tool: $($ToolMeta.Name)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [FAIL] Error loading tool $($_.FullName): $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            $ToolMeta = $null 
        }
    }

    # Pre-cache inactive tools for faster UI navigation
    if (Test-Path $moreToolsDir) {
        Get-ChildItem -Path $moreToolsDir -Filter "*.ps1" | ForEach-Object {
            if (-not $script:TOOL_CACHE.ContainsKey($_.BaseName)) {
                try {
                    $c = Get-Content $_.FullName -Raw -Encoding UTF8
                    $ToolMeta = $null
                    Invoke-Expression $c
                    if ($ToolMeta) { 
                        if (-not $ToolMeta.Icon) { $ToolMeta.Icon = [char]0x25CF } # $DOT
                        $script:TOOL_CACHE[$ToolMeta.Name] = $ToolMeta 
                    }
                } catch {}
            }
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
        $billingNote = if ($tool.RequiresBilling) { " $wrn WARNING: This tool requires a billing-enabled Google Cloud project. Using this tool may incur financial charges from Google." } else { "" }
        $instruction += "### Tool: $($tool.Name)$billingNote`n"
        $instruction += "**Description:** $($tool.Description)`n"
        
        # Add Behavior for high-reasoning models
        if ($isMajorModel -and $tool.Behavior) {
            $instruction += "**Behavior:** $($tool.Behavior)`n"
        }
        
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

    # --- Tool Synergies / Relationships ---
    $synergies = @()
    foreach ($tool in $toolsToLoad) {
        if ($tool.Relationships) {
            foreach ($relatedName in $tool.Relationships.Keys) {
                # Only mention synergy if BOTH tools are in the active $toolsToLoad set
                if ($toolsToLoad | Where-Object { $_.Name -eq $relatedName }) {
                    $synergyDesc = $tool.Relationships[$relatedName]
                    # Avoid duplicate synergy entries (A+B and B+A)
                    $pairKey = (@($tool.Name, $relatedName) | Sort-Object) -join "+"
                    if ($null -eq ($synergies | Where-Object { $_ -match "#### Synergy: $pairKey" })) {
                         $synergies += "#### Synergy: $pairKey`n$synergyDesc`n"
                    }
                }
            }
        }
    }

    if ($synergies.Count -gt 0) {
        $synergyHeader = "## Tool Synergies`nThe following tools have expanded capabilities when used together:`n`n"
        return ($toolInstructions -join "`n") + $synergyHeader + ($synergies -join "`n")
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
                $name = $_.BaseName
                $meta = $script:TOOL_CACHE[$name]
                
                # Fallback if not cached for some reason
                if (-not $meta) {
                    try {
                        $c = Get-Content -Path $_.FullName -Raw -Encoding UTF8
                        $ToolMeta = $null; Invoke-Expression $c; $meta = $ToolMeta
                        if ($meta) { $script:TOOL_CACHE[$name] = $meta }
                    } catch {}
                }

                if ($meta) {
                    $params = if ($meta.Parameters) { 
                        "(" + (($meta.Parameters.Keys | ForEach-Object { $_ }) -join ", ") + ")" 
                    } else { "" }
                    
                    $indicators = @()
                    if ($meta.Interactive) { $indicators += "⚠ " }
                    if ($meta.RequiresKey) { $indicators += "🔑" }
                    $indStr = if ($indicators.Count -gt 0) { " " + ($indicators -join " ") } else { "" }
                    $results += "$($meta.Icon)  $($meta.Name)$params [$($folder.Label)]$indStr"
                    $results += "     $arr  $($meta.Description)"
                    $results += ""
                }
            }
        }
    }

    if ($results.Count -eq 0) {
        $results += "No tools found in category: $Mode"
    }

    return $results
}
