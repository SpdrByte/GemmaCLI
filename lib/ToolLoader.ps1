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
            . $_.FullName
            if ($ToolMeta) {
                $script:TOOLS[$ToolMeta.Name] = $ToolMeta
                Write-Host "  [OK] Loaded tool: $($ToolMeta.Name)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [FAIL] Error loading tool $($_.Name): $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            $ToolMeta = $null
        }
    }
    Write-Host "Loaded $($script:TOOLS.Count) tool(s)."

    # Dynamic Prompt Generation
    $toolLimit = $ToolLimits[$Model]
    $toolInstructions = @()
    $toolsToLoad = $script:TOOLS.Values | Select-Object -First $toolLimit

    foreach ($tool in $toolsToLoad) {
        $instruction = ""
        if ($Model -eq "gemma-3-27b-it") {
            $instruction += "### Tool: $($tool.Name)`n"
            $instruction += "**Behavior:** $($tool.Behavior)`n"
            $instruction += "**Description:** $($tool.Description)`n"
            $instruction += "**Parameters:**`n"
            $tool.Parameters.GetEnumerator() | ForEach-Object { $instruction += "  - $($_.Name): $($_.Value)`n" }
            $instruction += "**Example:** $($tool.Example)`n`n"
        } elseif ($Model -eq "gemma-3-12b-it") {
            $instruction += "### Tool: $($tool.Name)`n"
            $instruction += "**Description:** $($tool.Description)`n"
            $instruction += "**Parameters:**`n"
            $tool.Parameters.GetEnumerator() | ForEach-Object { $instruction += "  - $($_.Name): $($_.Value)`n" }
            $instruction += "`n"
        } else {
             $instruction += "- **$($tool.Name):** $($tool.Description)`n"
        }
        $toolInstructions += $instruction
    }

    return ($toolInstructions -join "`n")
}
