# lib/ToolLoader.ps1 v1.0.1
# Responsibility: Finds, validates, loads, and documents all available tools.
# Optimized with Signature-based caching to skip Invoke-Expression on warm loads.

 $script:TOOLS = @{}
 $script:TOOL_CACHE = @{} 

function Get-ToolDirectorySignature {
    param([string]$ScriptRoot)
    
    $toolsDir = Join-Path $ScriptRoot "tools"
    $moreToolsDir = Join-Path $ScriptRoot "more_tools"
    
    $files = @()
    if (Test-Path $toolsDir) { $files += Get-ChildItem -Path $toolsDir -Filter "*.ps1" }
    if (Test-Path $moreToolsDir) { $files += Get-ChildItem -Path $moreToolsDir -Filter "*.ps1" }
    
    # Sort by FullName so order is deterministic even if filenames collide across folders
    return ($files | Sort-Object FullName | ForEach-Object { 
        # e.g. "tools\foo.ps1-638142718520000000" vs "more_tools\foo.ps1-638142718520000000"
        $relPath = $_.FullName.Substring($ScriptRoot.Length).TrimStart('\')
        "$relPath-$($_.LastWriteTime.Ticks)" 
    }) -join "|"
}


function Get-ToolInstructions {
    param(
        [string]$ScriptRoot,
        [string]$Model,
        [hashtable]$ToolLimits
    )

    $script:TOOLS = @{}
    $script:TOOL_CACHE = @{} 

    $toolsDir = Join-Path $ScriptRoot "tools"
    $moreToolsDir = Join-Path $ScriptRoot "more_tools"
    
    $dbDir = Join-Path $ScriptRoot "database"
    if (-not (Test-Path $dbDir)) { New-Item -ItemType Directory -Path $dbDir -Force | Out-Null }
    
    $cachePath = Join-Path $dbDir "tool_meta_cache.json"

    # --- INTELLIGENT CACHE LOGIC ---
    $currentSignature = Get-ToolDirectorySignature -ScriptRoot $ScriptRoot
    $cacheHit = $false

    if (Test-Path $cachePath) {
        try {
            $cachedData = Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            
            # Check if the signature in the cache matches the current file system
            if ($cachedData.signature -eq $currentSignature) {
                # WARM LOAD: Fast path. Signature matches.
                $cacheHit = $true
                
                foreach ($item in $cachedData.tools) {
                    # Rehydrate hashtables from PSCustomObjects for compatibility
                    $params = @{}
                    if ($item.Parameters) { 
                        foreach ($k in $item.Parameters.PSObject.Properties) { $params[$k.Name] = $k.Value } 
                    }
                    
                    $rels = $null
                    if ($item.Relationships) { 
                        $rels = @{}
                        foreach ($k in $item.Relationships.PSObject.Properties) { $rels[$k.Name] = $k.Value } 
                    }

                    $toolObj = @{
                        Name          = $item.Name
                        Description   = $item.Description
                        Icon          = $item.Icon
                        Interactive   = [bool]$item.Interactive
                        RequiresKey   = [bool]$item.RequiresKey
                        RequiresBilling = [bool]$item.RequiresBilling
                        Behavior      = $item.Behavior
                        ToolUseGuidanceMajor = $item.ToolUseGuidanceMajor
                        ToolUseGuidanceMinor = $item.ToolUseGuidanceMinor
                        Parameters    = $params
                        Example       = $item.Example
                        Relationships = $rels
                        Keywords      = $item.Keywords
                        Folder        = $item.Folder # 'tools' or 'more_tools'
                    }
                    
                    $script:TOOL_CACHE[$item.Name] = $toolObj
                    if ($item.Folder -eq "tools") {
                        $script:TOOLS[$item.Name] = $toolObj
                    }
                }
                Write-Host "  [CACHE] Loaded tools from metadata cache." -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [CACHE FAIL] Cache corrupt, falling back to full scan." -ForegroundColor Yellow
            $cacheHit = $false
            $script:TOOLS = @{}
            $script:TOOL_CACHE = @{}
        }
    }

    if (-not $cacheHit) {
        # COLD LOAD: Slow path. Signature mismatch or first run.
        Write-Host "  [SCAN] Tool signature changed or cache missing. Scanning tools..." -ForegroundColor Cyan
        
        if (-not (Test-Path $toolsDir)) { return "" }

        $wrn = [char]0x26A0
        $allToolMeta = @()

        # Process active tools (WITH Green OK / Red FAIL text)
        Get-ChildItem -Path $toolsDir -Filter "*.ps1" | ForEach-Object {
            $meta = Invoke-ToolScript -Path $_.FullName
            if ($meta) {
                if (-not $meta.Icon) { $meta.Icon = [char]0x25CF }
                $meta.Folder = "tools"
                $script:TOOLS[$meta.Name] = $meta
                $script:TOOL_CACHE[$meta.Name] = $meta
                $allToolMeta += $meta
                Write-Host "  [OK] Loaded tool: $($meta.Name)" -ForegroundColor Green
            }
        }

        # Process inactive tools (Silent, no OK text to keep console clean)
        if (Test-Path $moreToolsDir) {
            Get-ChildItem -Path $moreToolsDir -Filter "*.ps1" | ForEach-Object {
                if (-not $script:TOOL_CACHE.ContainsKey($_.BaseName)) {
                    $meta = Invoke-ToolScript -Path $_.FullName
                    if ($meta) {
                        if (-not $meta.Icon) { $meta.Icon = [char]0x25CF }
                        $meta.Folder = "more_tools"
                        $script:TOOL_CACHE[$meta.Name] = $meta
                        $allToolMeta += $meta
                    }
                }
            }
        }

        # Save Unified Cache
        $cacheArray = $allToolMeta | ForEach-Object {
            $paramsObj = if ($_.Parameters) { [PSCustomObject]$_.Parameters } else { [PSCustomObject]@{} }
            $relsObj = if ($_.Relationships) { [PSCustomObject]$_.Relationships } else { $null }
            [PSCustomObject]@{
                Name=$_.Name; Description=$_.Description; Icon=$_.Icon; Folder=$_.Folder;
                Interactive=[bool]$_.Interactive; RequiresKey=[bool]$_.RequiresKey; RequiresBilling=[bool]$_.RequiresBilling;
                Behavior=$_.Behavior; ToolUseGuidanceMajor=$_.ToolUseGuidanceMajor; ToolUseGuidanceMinor=$_.ToolUseGuidanceMinor;
                Parameters=$paramsObj; Example=$_.Example; Relationships=$relsObj; Keywords=$_.Keywords
            }
        }

        $unifiedCache = [PSCustomObject]@{
            signature   = $currentSignature
            last_update = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            total_tools = $allToolMeta.Count
            tools       = $cacheArray
        }

        $cacheJson = $unifiedCache | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($cachePath, $cacheJson, [System.Text.UTF8Encoding]::new($false))

        # ONLY generate the heavy wiki files if the signature changed!
        Export-ToolWiki -ScriptRoot $ScriptRoot
    }

    # --- PROMPT GENERATION LOGIC ---
    $majorModels = @("gemma-3-27b-it", "gemma-3-12b-it")
    $minorModels = @("gemma-3-4b-it", "gemma-3n-e4b-it", "gemma-3n-e2b-it", "gemma-3-1b-it")
    $isMajorModel = $majorModels -contains $Model
    $isMinorModel = $minorModels -contains $Model

    $toolLimit = if ($null -ne $ToolLimits[$Model]) { $ToolLimits[$Model] } else { 0 }
    $toolInstructions = @()
    $toolsToLoad = $script:TOOLS.Values | Where-Object { $_.Name -ne $null } | Sort-Object Name | Select-Object -First $toolLimit

    foreach ($tool in $toolsToLoad) {
        $instruction = ""
        $billingNote = if ($tool.RequiresBilling) { " $wrn WARNING: This tool requires a billing-enabled Google Cloud project. Using this tool may incur financial charges from Google." } else { "" }
        $instruction += "### Tool: $($tool.Name)$billingNote`n"
        $instruction += "**Description:** $($tool.Description)`n"
        
        if ($isMajorModel -and $tool.Behavior) { $instruction += "**Behavior:** $($tool.Behavior)`n" }
        
        if ($tool.Parameters -and $tool.Parameters.Count -gt 0) {
            $instruction += "**Parameters:**`n"
            $tool.Parameters.GetEnumerator() | ForEach-Object { $instruction += "  - $($_.Name): $($_.Value)`n" }
        }

        if ($tool.Example) { $instruction += "**Example:** $($tool.Example)`n" }

        if ($isMajorModel -and $tool.ToolUseGuidanceMajor) {
            $instruction += "**Usage Guidance (Detailed):**`n$($tool.ToolUseGuidanceMajor)`n"
        } elseif ($isMinorModel -and $tool.ToolUseGuidanceMinor) {
            $instruction += "**Usage Guidance (Simplified):**`n$($tool.ToolUseGuidanceMinor)`n"
        }
        
        $toolInstructions += $instruction
    }

    $synergies = @()
    foreach ($tool in $toolsToLoad) {
        if ($tool.Relationships) {
            foreach ($relatedName in $tool.Relationships.Keys) {
                if ($toolsToLoad | Where-Object { $_.Name -eq $relatedName }) {
                    $synergyDesc = $tool.Relationships[$relatedName]
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

function Invoke-ToolScript {
    param([string]$Path)
    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8
        $ToolMeta = $null
        Invoke-Expression -Command $content
        return $ToolMeta
    } catch {
        Write-Host "  [FAIL] Error loading tool ${Path}: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    } finally {
        $ToolMeta = $null 
    }
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
                    $params = if ($meta.Parameters -and $meta.Parameters.Count -gt 0) { 
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

    if ($results.Count -eq 0) { $results += "No tools found in category: $Mode" }
    $results += ""
    $results += "View full tool documentation: " + (Join-Path $ScriptRoot "TOOLS.html")

    return $results
}

<#
.SYNOPSIS
Generates the Wiki files (tools_data.js, TOOLS.html, TOOLS.md) for the Tool Dashboard.
Only called during a COLD LOAD (when tool signatures change).
#>
function Export-ToolWiki {
    param([string]$ScriptRoot)

    $dbDir = Join-Path $ScriptRoot "database"
    $jsPath = Join-Path $dbDir "tools_data.js"
    $htmlPath = Join-Path $ScriptRoot "TOOLS.html"
    $mdPath = Join-Path $ScriptRoot "TOOLS.md"
    
    $jsonArray = @()
    foreach ($tool in $script:TOOL_CACHE.Values) {
        $status = if ($tool.Folder -eq "tools") { "Active" } else { "Disabled" }
        
        $paramsObj = if ($tool.Parameters) { [PSCustomObject]$tool.Parameters } else { [PSCustomObject]@{} }
        $relsObj = if ($tool.Relationships) { [PSCustomObject]$tool.Relationships } else { $null }

        $jsonArray += [PSCustomObject]@{
            Name          = $tool.Name
            Description   = $tool.Description
            Icon          = $tool.Icon
            Status        = $status
            Interactive   = [bool]$tool.Interactive
            RequiresKey   = [bool]$tool.RequiresKey
            Parameters    = $paramsObj
            Example       = $tool.Example
            Relationships = $relsObj
        }
    }

    # EXPLICIT SORTING: Active first (A before D), then Alphabetical by Name
    $jsonArray = $jsonArray | Sort-Object Status, Name

    # 1. Generate tools_data.js
    $json = $jsonArray | ConvertTo-Json -Depth 5
    $jsContent = "window.gemmaTools = $json;"
    [System.IO.File]::WriteAllText($jsPath, $jsContent, [System.Text.UTF8Encoding]::new($false))

    # 2. Generate TOOLS.html
    $htmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GemmaCLI Tool Wiki</title>
    <script src="database/tools_data.js"></script>
    <style>
        :root { --bg: #0a0a0c; --card-bg: #16161e; --text: #c0caf5; --text-muted: #787c99; --accent-magenta: #bb9af7; --accent-cyan: #00f2ff; --accent-green: #73daca; --accent-orange: #ff9e64; --border: #292e42; --danger: #f7768e; --border-glow: rgba(0, 242, 255, 0.2); }
        * { box-sizing: border-box; } 
        body {
            background-color: var(--bg);
            color: var(--text);
            font-family: 'JetBrains Mono', monospace;
            margin: 0;
            line-height: 1.6;
            overflow-x: hidden;
            padding: 6px;
            /* Cyberpunk Grid Background */
            background-image: 
                linear-gradient(var(--border-glow) 1px, transparent 1px),
                linear-gradient(90deg, var(--border-glow) 1px, transparent 1px);
            background-size: 50px 50px;
            background-position: center center;
        }
        #error-screen { display: none; height: 100vh; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 2rem; }
        #dashboard { display: block; } header { background: linear-gradient(90deg, #1a1b26 0%, #24283b 100%); padding: 1.5rem; border-bottom: 1px solid var(--border); text-align: center; }
        header {
            background: rgba(0, 0, 0, 0.8);
            padding: 2rem;
            border-bottom: 2px solid var(--accent-cyan);
            text-align: center;
            box-shadow: 0 0 20px rgba(0, 242, 255, 0.2);
        }
        h1 {
            margin: 0;
            font-family: 'Orbitron', sans-serif;
            font-size: 2.2rem;
            color: var(--accent-cyan);
            text-transform: uppercase;
            letter-spacing: 6px;
            text-shadow: 0 0 10px var(--accent-cyan), 0 0 20px var(--accent-cyan);
            animation: flicker 3s infinite;
        }
        .container { max-width: 1400px; margin: 2rem auto; padding: 0 1.5rem; }
        .controls { display: flex; gap: 1rem; margin-bottom: 2rem; flex-wrap: wrap; background: var(--card-bg); padding: 1rem; border-radius: 8px; border: 1px solid var(--border); position: sticky; top: 1rem; z-index: 100; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
        .search-box { flex: 1; min-width: 300px; }
        input, select { background: #1a1b26; border: 1px solid var(--border); color: var(--text); padding: 0.7rem 1rem; border-radius: 4px; width: 100%; font-size: 1rem; }
        input:focus { outline: none; border-color: var(--accent-cyan); }
        #tool-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(450px, 1fr)); gap: 1.5rem; }
        .tool-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.5rem; display: flex; flex-direction: column; max-height: 400px; animation: fadeIn 0.4s ease-out forwards; }
        .card-content { overflow-y: auto; padding-right: 10px; flex-grow: 1; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        .tool-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 1rem; flex-shrink: 0; }
        .tool-icon-name { display: flex; align-items: center; gap: 1rem; }
        .tool-icon-img { width: 90px; height: 90px; object-fit: contain; background: #1a1b26; border-radius: 8px; border: 1px solid var(--border); padding: 4px; }
        .tool-icon-fallback { font-size: 1.8rem; background: #1a1b26; width: 90px; height: 90px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: 1px solid var(--border); }
        .tool-name { font-weight: bold; font-size: 1.4rem; color: var(--accent-cyan); font-family: monospace; }
        .badge { font-size: 0.7rem; padding: 0.2rem 0.6rem; border-radius: 10px; text-transform: uppercase; font-weight: bold; margin-bottom: 4px; display: block; text-align: center; }
        .badge-active { background: rgba(115, 218, 202, 0.1); color: var(--accent-green); border: 1px solid var(--accent-green); }
        .badge-disabled { background: rgba(247, 118, 142, 0.1); color: var(--danger); border: 1px solid var(--danger); }
        .badge-interactive { background: rgba(255, 158, 100, 0.1); color: var(--accent-orange); border: 1px solid var(--accent-orange); }
        .badge-key { background: rgba(187, 154, 247, 0.1); color: var(--accent-magenta); border: 1px solid var(--accent-magenta); }
        .tool-desc { color: var(--text); margin-bottom: 1.2rem; border-left: 2px solid var(--border); padding-left: 1rem; }
        .section-title { font-size: 0.75rem; color: var(--text-muted); text-transform: uppercase; margin-bottom: 0.5rem; margin-top: 1rem; letter-spacing: 1px; display: flex; align-items: center; gap: 8px; }
        .section-title::after { content: ""; flex: 1; height: 1px; background: var(--border); }
        .params-list { list-style: none; padding: 0; margin: 0 0 1rem 0; font-size: 0.9rem; font-family: monospace; }
        .params-list li { margin-bottom: 0.3rem; color: var(--accent-magenta); } .params-list span { color: var(--text-muted); font-family: sans-serif; }
        .example-box { background: #0f0f14; padding: 1rem; border-radius: 4px; font-size: 0.85rem; font-family: monospace; border: 1px solid var(--border); overflow-x: auto; color: #a9b1d6; white-space: pre-wrap; }
        .synergy-box { margin-top: 0.5rem; padding: 0.8rem; background: rgba(125, 207, 255, 0.05); border-radius: 4px; border: 1px dashed var(--accent-cyan); font-size: 0.85rem; }
        .empty-state { text-align: center; padding: 4rem; color: var(--text-muted); font-size: 1.2rem; }
        ::-webkit-scrollbar { width: 6px; } ::-webkit-scrollbar-track { background: transparent; } ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 10px; } ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }
    </style>
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;600&family=JetBrains+Mono:wght@300;500;800&family=Orbitron:wght@400;900&display=swap" rel="stylesheet">
</head>
<body>
<div id="error-screen" style="display:none; height:100vh; flex-direction:column; align-items:center; justify-content:center; text-align:center;">
    <h1 style="color: var(--danger);">Registry Not Found</h1>
    <p>Please run <b>GemmaCLI</b> at least once to generate the tool database.</p>
    <p style="color: var(--text-muted); font-size: 0.9rem;">(Missing database/tools_data.js)</p>
</div>
<div id="dashboard">
    <header><h1>>GEMMA_CLI/TOOLS</h1></header>
    <div class="container">
        <div class="controls">
            <div class="search-box"><input type="text" id="search" placeholder="Filter by name, description, or parameter..." oninput="filterTools()"></div>
            <div style="display:flex; gap: 10px;">
                <select id="filter-status" onchange="filterTools()" style="width: 150px;"><option value="all">All Status</option><option value="Active">Active</option><option value="Disabled">Disabled</option></select>
                <select id="filter-type" onchange="filterTools()" style="width: 180px;"><option value="all">All Types</option><option value="interactive">Interactive Only</option><option value="requiresKey">Requires API Key</option></select>
                <button onclick="location.reload()" class="btn" title="Reloads the page to show latest data (must run /refresh in GemmaCLI first)" style="padding: 0.5rem 1rem; font-size: 0.9rem;">Refresh View</button>
            </div>
        </div>
        <div id="tool-grid"></div>
    </div>
</div>
<script>
    function init() { if (typeof window.gemmaTools === 'undefined') { document.getElementById('dashboard').style.display = 'none'; document.getElementById('error-screen').style.display = 'flex'; return; } renderTools(window.gemmaTools); }
    function formatToolName(name) { return name.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' '); }
    function renderTools(tools) { const grid = document.getElementById('tool-grid'); grid.innerHTML = ''; if (tools.length === 0) { grid.innerHTML = '<div class="empty-state">No tools match your filters.</div>'; return; } tools.forEach(tool => { const card = document.createElement('div'); card.className = 'tool-card'; let paramsHtml = ''; if (tool.Parameters && Object.keys(tool.Parameters).length > 0) { paramsHtml = '<div class="section-title">Parameters</div><ul class="params-list">'; for (const [key, val] of Object.entries(tool.Parameters)) { paramsHtml += '<li>' + key + ' <span>— ' + val + '</span></li>'; } paramsHtml += '</ul>'; } let synergyHtml = ''; if (tool.Relationships && Object.keys(tool.Relationships).length > 0) { synergyHtml = '<div class="section-title">Synergies</div>'; for (const [target, desc] of Object.entries(tool.Relationships)) { synergyHtml += '<div class="synergy-box"><b>+ ' + target + ':</b> ' + desc + '</div>'; } } const statusBadge = '<span class="badge badge-' + tool.Status.toLowerCase() + '">' + tool.Status + '</span>'; const interactiveBadge = tool.Interactive ? '<span class="badge badge-interactive">Interactive ⚠</span>' : ''; const keyBadge = tool.RequiresKey ? '<span class="badge badge-key">Requires Key 🔑</span>' : ''; const iconPath = 'assets/Tools/' + tool.Name + '_tool.png'; const iconHtml = '<img src="' + iconPath + '" class="tool-icon-img" onerror="this.outerHTML=\'<div class=&quot;tool-icon-fallback&quot;>' + tool.Icon + '</div>\'">'; card.innerHTML = '<div class="tool-header"><div class="tool-icon-name">' + iconHtml + '<div class="tool-name">' + formatToolName(tool.Name) + '</div></div><div style="display:flex; flex-direction:column; align-items:flex-end;">' + statusBadge + interactiveBadge + keyBadge + '</div></div><div class="card-content"><div class="tool-desc">' + tool.Description + '</div>' + paramsHtml + '<div class="section-title">Usage Example</div><div class="example-box">' + (tool.Example ? tool.Example.replace(/</g, '&lt;').replace(/>/g, '&gt;') : 'No example.') + '</div>' + synergyHtml + '</div>'; grid.appendChild(card); }); }
    function filterTools() { const query = document.getElementById('search').value.toLowerCase(); const status = document.getElementById('filter-status').value; const type = document.getElementById('filter-type').value; const filtered = window.gemmaTools.filter(t => { const matchesQuery = t.Name.toLowerCase().includes(query) || t.Description.toLowerCase().includes(query) || (t.Parameters && Object.keys(t.Parameters).some(pk => pk.toLowerCase().includes(query))); const matchesStatus = status === 'all' || t.Status === status; let matchesType = true; if (type === 'interactive') matchesType = t.Interactive; if (type === 'requiresKey') matchesType = t.RequiresKey; return matchesQuery && matchesStatus && matchesType; }); renderTools(filtered); }
    init();
</script>
</body>
</html>
'@
    [System.IO.File]::WriteAllText($htmlPath, $htmlContent, [System.Text.UTF8Encoding]::new($false))

    # 3. Generate TOOLS.md (Iterating over the explicitly sorted array)
    $mdContent = "# GemmaCLI Tool Wiki`n`n"
    $fence = '```' # Avoids backtick parsing errors in PS
    
    foreach ($item in $jsonArray) {
        $tool = $script:TOOL_CACHE[$item.Name]
        $status = $item.Status
        
        $mdContent += "## $($tool.Name)`n"
        $mdContent += "**Status:** $status | **Interactive:** $($tool.Interactive) | **Requires Key:** $($tool.RequiresKey)`n"
        $mdContent += "**Description:** $($tool.Description)`n`n"
        
        if ($tool.Parameters -and $tool.Parameters.Count -gt 0) {
            $mdContent += "### Parameters`n"
            foreach ($key in $tool.Parameters.Keys) {
                $mdContent += "- ``$($key)``: $($tool.Parameters[$key])`n"
            }
            $mdContent += "`n"
        }

        if ($tool.Example) {
            $mdContent += "### Example`n"
            $mdContent += "$fence`n$($tool.Example)`n$fence`n`n"
        }

        if ($tool.Relationships -and $tool.Relationships.Count -gt 0) {
            $mdContent += "### Synergies`n"
            foreach ($target in $tool.Relationships.Keys) {
                $mdContent += "- **+ $target**: $($tool.Relationships[$target])`n"
            }
            $mdContent += "`n"
        }
        $mdContent += "---`n`n"
    }

    [System.IO.File]::WriteAllText($mdPath, $mdContent, [System.Text.UTF8Encoding]::new($false))
}