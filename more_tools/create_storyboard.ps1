# ===============================================
# GemmaCLI Tool - create_storyboard.ps1 v1.3.0
# Responsibility: Manages cinematic project structure, parses scripts,
#                 generates storyboard manifests (JSON), and builds a visual 
#                 HTML dashboard for asset tracking.
# ===============================================

<#
.SYNOPSIS
    STORYBOARD MANIFEST DATA CONTRACT (storyboard.json)

    [PROJECT LEVEL]
    - resolution: string ("1280x720", "1920x1080", "3840x2160")
    - default_quality_weight: int (1-10)
    - total_shot_count: int
    - project_name: string
    - total_length_seconds: int

    [SCENE LEVEL]
    - id: int
    - slug: string
    - text: string
    - quality_weight: int
    - montage: bool
    - shots: array (Shot objects)

    [SHOT LEVEL]
    - id: string (e.g. "1.1")
    - scene_id: int
    - description: string
    - quality_weight: int
    - duration_seconds: float
    - camera_move: string ("zoom_in", "zoom_out", "pan_left", "pan_right", "dolly_in", "hold_wide", "hold_cu")
    - shot_type: string ("text_only", "static_image", "blur_tinted", "animated_fx", "panzoom", "parallax", "vo_narration", "music", "parallax_vo_music", "veo")
    - cut_out: string ("hard_cut", "crossfade", "smash_cut", "fade_to_black")
    - audio: {
        vo: { role: "narrator|character|silent", character_id: string, script: string },
        music: { cue: string, behavior: "fade_in|continue|fade_out|cut" },
        sfx: [ { label: string, description: string } ],
        veo_audio_mode: "silent|baked_dialogue|baked_ambient"
      }
    - status: string ("proposed", "approved", "generating", "done", "locked")
    - locked: bool
    - warnings: array
    - assets: { bg: {path, status, prompt}, fg: {path, status, prompt} }
#>

# --- Global Mappings ---
$script:QualityToResolution = @{
    1  = "1920x1080"
    2  = "1920x1080"; 3 = "1920x1080"; 4 = "1920x1080"; 5 = "1920x1080"
    6  = "1920x1080"
    7  = "1280x720"  # Veo Lite 720p
    8  = "1280x720"  # Veo Standard 720p
    9  = "1920x1080" # Veo Standard 1080p
    10 = "3840x2160" # Veo Standard 4K
}

$script:QualityToShotType = @{
    1  = "static_image" # Base: Includes PanZoom, VO, Music
    2  = "static_image"
    3  = "static_image"
    4  = "panzoom"
    5  = "parallax"     # Standard 2-Layer
    6  = "parallax_high" # Multi-Layer / FX
    7  = "veo_lite"     # Budget Generative Video (720p)
    8  = "veo_720p"     # Standard Generative Video (720p)
    9  = "veo_1080p"    # High-end Generative Video (1080p)
    10 = "veo_4k"       # Ultra-high Generative Video (4K)
}

# --- Helper: JSON Extractor ---
function Extract-Json {
    param([string]$text)
    
    # 1. Try to find content within Markdown fences first
    $json = $text
    if ($text -match '(?s)```json\s*(.*?)\s*(?:```|$)') { $json = $Matches[1] }
    elseif ($text -match '(?s)```\s*(.*?)\s*(?:```|$)') { $json = $Matches[1] }
    
    # 2. Find the bounds of the array
    $firstBracket = $json.IndexOf("[")
    if ($firstBracket -lt 0) { return $json.Trim() }
    
    $json = $json.Substring($firstBracket).Trim()
    
    # 3. Try parsing as-is (with PowerShell 5.1 comma cleanup)
    $clean = $json -replace ',\s*]', ']' -replace ',\s*}', '}'
    try { 
        $null = $clean | ConvertFrom-Json -ErrorAction Stop
        return $clean 
    } catch { }
    
    # 4. Truncation Repair: Backtrack to last valid object (Strategy: Dropping broken tail)
    # This is safer than closing unsealed braces because it ensures mandatory fields exist.
    $lastBrace = $json.LastIndexOf("}")
    if ($lastBrace -gt 0) {
        $repaired = $json.Substring(0, $lastBrace + 1)
        if (-not $repaired.EndsWith("]")) { $repaired += "]" }
        $repaired = $repaired -replace ',\s*]', ']'
        try {
            $null = $repaired | ConvertFrom-Json -ErrorAction Stop
            return $repaired
        } catch { }
    }

    # 5. Last Resort: Force-close unsealed braces/quotes
    $temp = $json
    $quotes = [regex]::Matches($temp, '(?<!\\)"').Count
    if ($quotes % 2 -ne 0) { $temp += '"' }
    $openBraces = [regex]::Matches($temp, '\{').Count
    $closeBraces = [regex]::Matches($temp, '\}').Count
    for ($i=0; $i -lt ($openBraces - $closeBraces); $i++) { $temp += '}' }
    if (-not $temp.EndsWith("]")) { $temp += "]" }
    $temp = $temp -replace ',\s*]', ']' -replace ',\s*}', '}'
    return $temp
}

# --- Helper: Dashboard Generator ---
function Update-StoryboardDashboard {
    param($manifest, [string]$storyboard_dir)

    $htmlPath = Join-Path $storyboard_dir "storyboard.html"
    
    # We use a single-quoted here-string (@' ... '@) to prevent PowerShell from expanding ${} and `
    $htmlContent = @'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Storyboard Production Suite</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #1a1a1a; color: #eee; margin: 0; padding: 20px; padding-top: 100px; }
        header { position: fixed; top: 0; left: 0; right: 0; background: #111; padding: 10px 20px; border-bottom: 2px solid #00ffff; z-index: 1000; display: flex; justify-content: space-between; align-items: center; height: 50px; }
        .header-meta { font-size: 13px; color: #888; }
        .header-meta b { color: #00ffff; }
        .timeline-container { position: fixed; top: 70px; left: 0; right: 0; height: 25px; background: #222; z-index: 999; display: flex; border-bottom: 1px solid #333; overflow: hidden; }
        .timeline-block { height: 100%; display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: bold; cursor: pointer; border-right: 1px solid #444; transition: background 0.2s; background: #333; color: #aaa; }
        .timeline-block:hover { background: #444; color: #fff; }
        .scene-section { margin-top: 40px; border-top: 1px solid #333; padding-top: 20px; }
        .scene-header { display: flex; align-items: center; gap: 15px; margin-bottom: 20px; }
        .scene-header h2 { margin: 0; color: #00ffff; font-size: 1.4em; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr)); gap: 20px; }
        .card { background: #252525; border: 1px solid #444; border-radius: 8px; overflow: hidden; position: relative; transition: transform 0.2s; border-left: 4px solid transparent; }
        .card.locked { border-color: #8a2be2; box-shadow: 0 0 10px rgba(138, 43, 226, 0.2); }
        .card.warning { border-left-color: #ff4500; }
        .image-container { width: 100%; aspect-ratio: 16/9; background: #000; position: relative; cursor: pointer; display: flex; align-items: center; justify-content: center; overflow: hidden; }
        .image-container img { width: 100%; height: 100%; object-fit: cover; }
        .placeholder-text { padding: 20px; font-style: italic; color: #666; font-size: 11px; text-align: center; }
        .badge { position: absolute; top: 10px; right: 10px; padding: 3px 8px; border-radius: 4px; font-size: 10px; font-weight: bold; color: #fff; background: #444; z-index: 10; }
        .badge.parallax { background: #8a2be2; } .badge.parallax_high { background: #9400d3; border: 1px solid #fff; } 
        .badge.panzoom { background: #20b2aa; } .badge.veo_4k { background: #ff4500; }
        .cam-badge { position: absolute; bottom: 10px; right: 10px; background: rgba(0,0,0,0.6); padding: 3px 8px; border-radius: 4px; font-size: 9px; color: #aaa; }
        .status-dot { position: absolute; top: 12px; left: 10px; width: 10px; height: 10px; border-radius: 50%; background: #555; }
        .status-dot.approved { background: #1e90ff; } .status-dot.done { background: #00ff00; }
        .status-dot.error { background: #ff4500; } .status-dot.warning { background: #ffa500; }
        .loader-bar { height: 3px; background: linear-gradient(90deg, #222, #00ffff, #222); background-size: 200% 100%; animation: loading 1.5s infinite; display: none; width: 100%; position: absolute; bottom: 0; left: 0; }
        @keyframes loading { 0% { background-position: 100% 0; } 100% { background-position: -100% 0; } }
        .info { padding: 15px; }
        .shot-meta { display: flex; justify-content: space-between; font-size: 11px; color: #888; margin-bottom: 10px; }
        .q-weight { padding: 2px 6px; border-radius: 3px; font-weight: bold; font-size: 10px; cursor: pointer; }
        .vo-box { background: #111; padding: 10px; border-radius: 4px; font-size: 12px; color: #bbb; border-left: 3px solid #444; margin-top: 10px; }
        .fg-marker { margin-top: 10px; font-size: 10px; color: #00ff00; font-weight: bold; }
        #toast { position: fixed; bottom: 20px; right: 20px; padding: 15px 25px; border-radius: 5px; background: #00ffff; color: #000; font-weight: bold; z-index: 2000; display: none; }
        #cmd-popup { position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: #222; border: 2px solid #00ffff; padding: 30px; border-radius: 10px; z-index: 3000; display: none; width: 80%; max-width: 600px; }
        #cmd-text { background: #000; color: #0f0; padding: 15px; font-family: monospace; border-radius: 5px; margin: 15px 0; word-break: break-all; }
        .btn { background: #00ffff; color: #000; border: none; padding: 10px 20px; border-radius: 5px; cursor: pointer; font-weight: bold; }
    </style>
</head>
<body>
    <div id="cmd-popup">
        <h3 style="margin-top:0; color:#00ffff;">Update Production Budget</h3>
        <p style="font-size:13px; color:#aaa;">Copy this command and paste it into your <b>GemmaCLI</b> terminal.</p>
        <div id="cmd-text"></div>
        <button class="btn" onclick="copyCmd()">Copy Command</button>
        <button class="btn" style="background:#555; color:#fff;" onclick="closePopup()">Cancel</button>
    </div>
    <div id="app"></div>
    <div id="toast"></div>

    <script>
        let lastManifestJson = "";

        window.loadStoryboardData = function(data) {
            const currentJson = JSON.stringify(data);
            if (currentJson !== lastManifestJson) {
                lastManifestJson = currentJson;
                render(data);
            }
        };

        function poll() {
            const script = document.createElement('script');
            script.src = 'storyboard_data.js?t=' + Date.now();
            script.onload = () => script.remove();
            script.onerror = () => console.error("Poll error (file missing?)");
            document.head.appendChild(script);
        }

        function render(project) {
            const app = document.getElementById('app');
            const html = [];
            html.push(`<header>
                <div>
                    <h1 style="margin:0; font-size: 1.2em;">🎬 ${project.project_name}</h1>
                    <div style="font-size:10px; color: #00ffff; margin-top:2px;">Style: <b>${project.style}</b></div>
                </div>
                <div class="header-meta">
                    <button class="btn" style="padding: 4px 10px; font-size: 11px; margin-right: 15px; background: #1e90ff;" onclick="approveAll()">✔️ Approve All</button>
                    Res: <b>${project.resolution}</b> | Len: <b>${project.total_length_seconds}s</b> | Scenes: <b>${project.scenes.length}</b>
                </div>
            </header>
            <div class="timeline-container">`);
            
            project.scenes.forEach(s => {
                const pct = (s.duration / project.total_length_seconds) * 100;
                html.push(`<div class="timeline-block" style="width: ${pct}%;" onclick="scrollToScene(${s.id})">S${s.id}</div>`);
            });
            html.push(`</div>`);

            if (project.characters && project.characters.length > 0) {
                html.push(`<section class="scene-section" style="margin-top: 20px;">
                    <div class="scene-header"><h2>👥 CAST & CHARACTER MODELS</h2></div>
                    <div class="grid" style="grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));">`);
                
                project.characters.forEach(c => {
                    let imgHtml = `<div class="placeholder-text"><b>T-POSE PROMPT:</b> ${c.prompt}</div>`;
                    if (c.assets && c.assets.ref_image && c.assets.ref_image.status === 'done') {
                        imgHtml = `<img src="${c.assets.ref_image.path}?t=${Date.now()}">`;
                    }
                    
                    const safePrompt = c.prompt ? c.prompt.replace(/'/g, "\\'") : '';
                    html.push(`<div class="card">
                        <div class="image-container" style="aspect-ratio: 1/1;" onclick="copyPrompt('${safePrompt}')">
                            ${imgHtml}
                        </div>
                        <div class="info">
                            <div style="font-size: 14px; font-weight: bold; color: #00ffff; margin-bottom: 5px;">${c.name}</div>
                            <div style="font-size: 11px; color: #aaa; line-height: 1.4;">${c.description}</div>
                        </div>
                    </div>`);
                });
                html.push(`</div></section>`);
            }

            project.scenes.forEach(scene => {
                const qClass = scene.quality_weight >= 10 ? "q-10" : (scene.quality_weight >= 5 ? "q-5" : "q-1");
                html.push(`<section class="scene-section" id="scene-${scene.id}">
                    <div class="scene-header">
                        <h2>SCENE ${scene.id}: ${scene.slug}</h2>
                        <span class="q-weight ${qClass}" onclick="changeQuality(${scene.id}, ${scene.quality_weight})">Quality: ${scene.quality_weight}</span>
                        <span style="color:#888; font-size:13px;">${scene.duration}s | Start: ${scene.start_time}s</span>
                    </div>
                    <div class="grid">`);
                
                if (scene.shots && scene.shots.length > 0) {
                    scene.shots.forEach(shot => {
                        const safeDesc = shot.description ? shot.description.replace(/'/g, "\\'") : '';
                        const bgPrompt = shot.description || '';
                        const sType = (shot.shot_type || 'static').toUpperCase();
                        const sClass = shot.shot_type || 'static_image';
                        const cMove = (shot.camera_move || 'none').toUpperCase();
                        
                        let voHtml = '';
                        let musicHtml = '';
                        let sfxHtml = '';
                        let veoAudioMode = '';
                        
                        if (shot.audio) {
                            if (shot.audio.veo_audio_mode) {
                                veoAudioMode = `<div style="color:#ffaa00; font-size:10px; margin-bottom:5px;">VEO AUDIO: ${shot.audio.veo_audio_mode}</div>`;
                            }
                            if (shot.audio.vo && shot.audio.vo.role && shot.audio.vo.role !== 'silent') {
                                const role = shot.audio.vo.character_id ? shot.audio.vo.character_id : shot.audio.vo.role;
                                voHtml = `<div style="margin-bottom:4px;"><b>VO (${role}):</b> ${shot.audio.vo.script || ''}</div>`;
                            }
                            if (shot.audio.music && shot.audio.music.cue && shot.audio.music.behavior !== 'none') {
                                musicHtml = `<div style="margin-bottom:4px; color:#20b2aa;"><b>MUSIC [${shot.audio.music.behavior}]:</b> ${shot.audio.music.cue}</div>`;
                            }
                            if (shot.audio.sfx && Array.isArray(shot.audio.sfx) && shot.audio.sfx.length > 0) {
                                const sfxList = shot.audio.sfx.map(s => `[${s.label}] ${s.description}`).join(' | ');
                                sfxHtml = `<div style="color:#aaa; font-size:10px;"><b>SFX:</b> ${sfxList}</div>`;
                            }
                        }
                        
                        let bgImg = `<div class="placeholder-text"><b>BG PROMPT:</b> ${bgPrompt}</div>`;
                        if (shot.assets && shot.assets.bg && shot.assets.bg.status === 'done') {
                            bgImg = `<img src="${shot.assets.bg.path}?t=${Date.now()}">`;
                        }

                        const hasWarning = shot.warnings && shot.warnings.length > 0;

                        html.push(`<div class="card ${shot.status || ''} ${shot.locked ? 'locked' : ''} ${hasWarning ? 'warning' : ''}">
                            <div class="image-container" onclick="copyPrompt('${safeDesc}')">
                                <div class="status-dot ${shot.status || ''}"></div>
                                <div class="badge ${sClass}">${sType}</div>
                                <div class="cam-badge">${cMove}</div>
                                ${bgImg}
                            </div>
                            <div class="info">
                                <div class="shot-meta">
                                    <span>SHOT ${shot.id}</span>
                                    <span>${shot.duration_seconds || 0}s</span>
                                    <span class="q-weight">Q${shot.quality_weight || 1}</span>
                                </div>
                                <div class="vo-box">
                                    ${veoAudioMode}
                                    ${voHtml}
                                    ${musicHtml}
                                    ${sfxHtml}
                                </div>
                                <div style="display:flex; gap:5px; margin-top: 8px;">
                                    <button class="btn" style="padding: 2px 5px; font-size: 9px; background: #1e90ff; color: #fff;" onclick="approveShot(${scene.id}, '${shot.id}', this)">✔️ Approve</button>
                                    <button class="btn" style="padding: 2px 5px; font-size: 9px; background: #444; color: #fff;" onclick="regenerateShot(${scene.id}, '${shot.id}')">🔄 Regen</button>
                                </div>
                            </div>
                            <div class="loader-bar" id="loader-${shot.id}"></div>
                        </div>`);
                    });
                } else {
                    html.push(`<div class="card"><div class="placeholder-text">Pending decompose...</div></div>`);
                }
                html.push(`</div></section>`);
            });
            app.innerHTML = html.join('');
        }

        function changeQuality(id, q) {
            const val = prompt("New weight (1-10):", q);
            if (val) {
                const cmd = `create_storyboard -mode set-quality -scene_id ${id} -weight ${val}`;
                document.getElementById('cmd-text').innerText = cmd;
                document.getElementById('cmd-popup').style.display = 'block';
            }
        }
        function regenerateShot(sceneId, shotId) {
            const note = prompt("Any specific notes for the AI? (Leave blank for general regeneration)");
            if (note !== null) {
                let cmd = `create_storyboard -mode regenerate-shot -scene_id ${sceneId} -shot_id "${shotId}"`;
                if (note.trim() !== '') {
                    cmd += ` -note "${note.replace(/"/g, '\\"')}"`;
                }
                document.getElementById('cmd-text').innerText = cmd;
                document.getElementById('cmd-popup').style.display = 'block';
            }
        }
        function approveShot(sceneId, shotId, btnElement) {
            btnElement.disabled = true;
            document.getElementById('loader-' + shotId).style.display = 'block';
            const cmd = `create_storyboard -mode approve-shot -scene_id ${sceneId} -shot_id "${shotId}"`;
            document.getElementById('cmd-text').innerText = cmd;
            document.getElementById('cmd-popup').style.display = 'block';
            setTimeout(() => { btnElement.disabled = false; document.getElementById('loader-' + shotId).style.display = 'none'; }, 2000);
        }
        function approveAll() {
            const cmd = `create_storyboard -mode approve-all`;
            document.getElementById('cmd-text').innerText = cmd;
            document.getElementById('cmd-popup').style.display = 'block';
        }
        function copyCmd() {
            navigator.clipboard.writeText(document.getElementById('cmd-text').innerText);
            showToast("Command copied!"); closePopup();
        }
        function closePopup() { document.getElementById('cmd-popup').style.display = 'none'; }
        function showToast(m) { const t = document.getElementById('toast'); t.innerText = m; t.style.display = 'block'; setTimeout(()=>t.style.display='none', 2000); }
        function scrollToScene(id) { document.getElementById('scene-'+id).scrollIntoView({behavior:'smooth'}); }
        function copyPrompt(p) { navigator.clipboard.writeText(p); showToast("Prompt copied!"); }

        setInterval(poll, 2000);
        poll();
    </script>
</body>
</html>
'@
    $htmlContent | Set-Content -Path $htmlPath -Encoding UTF8
}

# --- Helper: Shot Constructor ---
function New-ShotObject {
    param(
        [string]$id, [int]$scene_id, [string]$description,
        [int]$quality_weight = 1, [float]$duration = 3.0,
        [string]$camera_move = "hold_wide", [string]$shot_type = "static_image",
        [string]$cut_out = "hard_cut",
        [string]$vo_role = "silent", [string]$vo_character_id = "", [string]$vo_script = "",
        [string]$music_cue = "", [string]$music_behavior = "continue",
        [array]$sfx_array = @(),
        [string]$veo_audio_mode = "silent",
        [string]$status = "proposed",
        [float]$start_time = 0,
        [string]$line_ref = "",
        [string]$fg_description = ""
    )
    
    $bgPrompt = $description
    $fgPrompt = ""
    if ($shot_type -match "parallax") {
        # Foreground prompt needs green screen instruction
        $fgPrompt = if ($fg_description) { $fg_description } else { $description }
        $fgPrompt += " With a #00ff00 green background for easy removal."
    }

    return @{
        id               = $id
        scene_id         = $scene_id
        description      = $description
        quality_weight   = $quality_weight
        duration_seconds = $duration
        start_time       = $start_time
        line_ref         = $line_ref
        camera_move      = $camera_move
        shot_type        = $shot_type
        cut_out          = $cut_out
        audio            = @{
            vo = @{ role = $vo_role; character_id = $vo_character_id; script = $vo_script }
            music = @{ cue = $music_cue; behavior = $music_behavior }
            sfx = $sfx_array
            veo_audio_mode = $veo_audio_mode
        }
        status           = $status
        locked           = $false
        warnings         = @()
        assets           = @{
            bg = @{ path="assets/shot_${id}_bg.png"; status="pending"; prompt=$bgPrompt }
            fg = if ($shot_type -match "parallax") { @{ path="assets/shot_${id}_fg.png"; status="pending"; prompt=$fgPrompt } } else { $null }
        }
    }
}

function Invoke-CreateStoryboardTool {
    param(
        [string]$project_dir,
        [string]$script_path,
        [string]$logline,
        [int]$min_length_seconds = 60,
        [int]$max_length_seconds = 600,
        [int]$default_quality_weight = 1,
        [string]$style,
        [string]$scene_weights,
        [ValidateSet("short","long")]
        [string]$length_tier,
        [int]$scene_id,
        [string]$shot_id,
        [string]$note,
        [int]$weight,
        [ValidateSet("init","decompose","set-quality","regenerate-shot","approve-shot","approve-all")]
        [string]$mode = "init"
    )

    # --- 1. Project Setup & Inference ---
    # Handle missing project_dir before trimming to avoid errors
    if (-not [string]::IsNullOrWhiteSpace($project_dir)) {
        $project_dir = $project_dir.Trim().Trim("'").Trim('"')
    }
    
    # Logic for directory inference if project_dir is missing or standard placeholder
    if ([string]::IsNullOrWhiteSpace($project_dir) -or $project_dir -eq "." -or $project_dir -eq "./MyMovie") {
        if (-not [string]::IsNullOrWhiteSpace($script_path) -and (Test-Path $script_path)) {
            $project_dir = Split-Path (Resolve-Path $script_path).Path -Parent
        }
    }

    # Final check: if we still don't have a dir, we can't proceed safely
    if ([string]::IsNullOrWhiteSpace($project_dir)) {
        return "[SYSTEM] ERROR: No 'project_dir' provided and could not infer one from 'script_path'. Please provide a project_dir."
    }

    # --- 1.5 Project Style Handling ---
    $styleOptions = @(
        "Realistic cinematic",
        "Gritty 80s Sci-Fi Noir",
        "Found footage / VHS aesthetic",
        "Epic IMAX blockbuster",
        "Cyberpunk Anime",
        "Cartoon Network style",
        "3D CGI (Pixar/Disney style)",
        "Hand-drawn charcoal sketch",
        "Studio Ghibli watercolor",
        "Retro 16-bit Pixel Art",
        "Stop-motion claymation",
        "VFX concept art"
    )

    $hasLength = (-not [string]::IsNullOrWhiteSpace($length_tier)) -or ($min_length_seconds -ne 60 -or $max_length_seconds -ne 600)

    if ($mode -eq "init" -and ([string]::IsNullOrWhiteSpace($style) -or -not $hasLength)) {
        $optionsStr = ($styleOptions | ForEach-Object { "  - $_" }) -join "`n"
        $promptMsg = "🎬 PRODUCTION KICKOFF: I need to set your project's creative direction.`n`nPlease provide:`n1. VISUAL STYLE: (Choose from below or describe your own)`n$optionsStr`n`n2. PRODUCTION WEIGHT: (1-10, applies to all scenes by default)`n`n3. TARGET RUNTIME: (Short: 5-15m or Long: 15-90m)`n`nGEMMA: Ask the user for these three values, then re-run 'init' with: -style '[Choice]' -default_quality_weight [Num] -length_tier '[short/long]'"
        return "[SYSTEM] ACTION_REQUIRED: $promptMsg"
    }

    if ([string]::IsNullOrWhiteSpace($style)) { $style = "Realistic cinematic" }
    
    # Set min/max based on tier (if provided)
    if ($length_tier -eq "short") { $min_length_seconds = 300; $max_length_seconds = 900 }
    elseif ($length_tier -eq "long") { $min_length_seconds = 900; $max_length_seconds = 5400 }

    $storyboard_dir = Join-Path $project_dir "storyboard"
    $assets_dir = Join-Path $storyboard_dir "assets"

    try {
        if (-not (Test-Path $project_dir)) {
            New-Item -Path $project_dir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $storyboard_dir)) {
            New-Item -Path $storyboard_dir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $assets_dir)) {
            New-Item -Path $assets_dir -ItemType Directory -Force | Out-Null
        }
    } catch {
        return "ERROR: Failed to initialize project directory structure at '$project_dir'. $($_.Exception.Message)"
    }

    # --- 2. Script Management ---
    $final_script_name = "script.txt"
    $local_script_path = Join-Path $storyboard_dir $final_script_name

    if ($mode -eq "init") {
        if ([string]::IsNullOrWhiteSpace($script_path) -and [string]::IsNullOrWhiteSpace($logline)) {
            return "ERROR: You must provide either a 'script_path' or a 'logline' to create a storyboard."
        }

        if (-not [string]::IsNullOrWhiteSpace($script_path)) {
            if (-not (Test-Path $script_path)) {
                return "ERROR: Provided script_path '$script_path' does not exist."
            }
            # Copy script to project folder if not already there
            if ((Resolve-Path $script_path).Path -ne (Resolve-Path $local_script_path -ErrorAction SilentlyContinue).Path) {
                Copy-Item -Path $script_path -Destination $local_script_path -Force
            }
        }
    }

    # --- 3. Mode Dispatch ---
    $mode = $mode.ToLower()
    $jsonPath = Join-Path $storyboard_dir "storyboard.json"
    $existingManifest = $null
    if (Test-Path $jsonPath) {
        try { $existingManifest = Get-Content $jsonPath -Raw | ConvertFrom-Json } catch { }
    }

    if ($mode -eq "init") {
        $res = $script:QualityToResolution[$default_quality_weight]
        if (-not $res) { $res = "1920x1080" }

        $manifest = @{
            project_name           = Split-Path $project_dir -Leaf
            total_length_seconds   = $min_length_seconds
            default_quality_weight = $default_quality_weight
            resolution             = $res
            style                  = $style
            total_shot_count       = 0
            scenes                 = @()
            characters             = @()
            locations              = @{}
            status                 = if ($existingManifest) { $existingManifest.status } else { "initialized" }
        }

        $scriptContent = ""
        if (-not [string]::IsNullOrWhiteSpace($script_path)) {
            $scriptContent = Get-Content $local_script_path -Raw -Encoding UTF8
        } else {
            return "ACTION_REQUIRED: Standalone Logline Mode detected. Logline: '$logline'.`n`nPlease use the 'write_script' tool with the topic: '$logline' to generate a screenplay first, then call 'create_storyboard' again with the resulting 'script_path'."
        }

        # --- 4. Extract Manifest (Characters/Locations) ---
        if ($scriptContent -match "(?is)\[CHARACTER & LOCATION MANIFEST\](.*?)(?:\r?\n\r?\n|SCRIPT HEADER:|SCENE 1:|# SCENE 1:|\*\*SCENE 1:\*\*)") {
            $manifestBlock = $Matches[1]
            $manifestLines = $manifestBlock -split "\r?\n" | Where-Object { $_ -match ":" }
            $charIndex = 1
            foreach ($line in $manifestLines) {
                if ($line -match "(?i)CHARACTER:\s*(.*?)\s*-\s*(.*)") {
                    $charName = $Matches[1].Trim()
                    $charDesc = $Matches[2].Trim()
                    $charPrompt = "Character design model sheet, T-pose full body turnaround, $charName. $charDesc. Style: $($manifest.style). Clean neutral background, highly detailed, symmetrical."
                    $manifest.characters += @{
                        id = "char_$charIndex"
                        name = $charName
                        description = $charDesc
                        prompt = $charPrompt
                        assets = @{
                            ref_image = @{ path="assets/char_${charIndex}.png"; status="pending" }
                        }
                    }
                    $charIndex++
                } elseif ($line -match "(?i)LOCATION:\s*(.*?)\s*-\s*(.*)") {
                    $manifest.locations[$Matches[1].Trim()] = $Matches[2].Trim()
                }
            }
        }

        # --- 5. Slice Scenes ---
        $scenePattern = "(?ims)(?:###|\*\*|)\s*SCENE\s+(\d+):\s+(.*?)\s+\[(MOTION|STATIC|MONTAGE)\](?:\*\*|)\s*(.*?)(?=(?:###|\*\*|)\s*SCENE\s+\d+:|\z)"
        $matches = [regex]::Matches($scriptContent, $scenePattern)

        if ($matches.Count -eq 0) {
            return "ERROR: Found 0 scenes in the script. The script MUST follow the format: 'SCENE [N]: SLUG [STATIC/MOTION/MONTAGE]'. Please verify your script file content."
        }

        $totalWordCount = 0
        $tempScenes = [System.Collections.Generic.List[object]]::new()
        $maxQuality = $default_quality_weight

        foreach ($m in $matches) {
            $id = $m.Groups[1].Value
            $slug = $m.Groups[2].Value.Trim()
            $tag = $m.Groups[3].Value.ToUpper()
            $content = $m.Groups[4].Value.Trim()
            
            $isMontage = ($tag -eq "MONTAGE")
            $qWeight = $default_quality_weight
            if ($isMontage -and $qWeight -lt 5) { $qWeight = 5 }
            if ($qWeight -gt $maxQuality) { $maxQuality = $qWeight }

            $words = ($content -split "\s+" | Where-Object { $_ }).Count
            $totalWordCount += $words
            $lineStart = ($scriptContent.Substring(0, $m.Index) -split "\r?\n").Count
            $lineEnd = $lineStart + ($m.Value -split "\r?\n").Count - 1

            # Map shot type from quality mapping
            $shotType = $script:QualityToShotType[[int]$qWeight]

            $existingScene = if ($existingManifest) { $existingManifest.scenes | Where-Object { $_.id -eq [int]$id } } else { $null }
            
            $sceneObj = @{
                id              = [int]$id
                slug            = $slug
                tag             = $tag
                text            = $content
                quality_weight  = $qWeight
                montage         = $isMontage
                shots           = @()
                word_count      = $words
                script_line_ref = "$lineStart-$lineEnd"
                shot_type       = $shotType
                status          = if ($existingScene) { $existingScene.status } else { "pending" }
            }
            $tempScenes.Add($sceneObj)
        }

        # Final Resolution check
        $manifest.resolution = $script:QualityToResolution[[int]$maxQuality]

        # --- 5.5 Cinematic Pacing & Runtime Normalization ---
        # 1. Calculate Raw Durations
        $rawTotal = 0
        foreach ($s in $tempScenes) {
            $baseDur = [Math]::Max(15, [Math]::Round($s.word_count / 1))
            $s.duration = $baseDur + 15 # 15s establishing/transition bonus
            $rawTotal += $s.duration + 3
        }

        # 2. Calculate Scaling Factor to stay within min/max bounds
        $scaleFactor = 1.0
        if ($rawTotal -gt $max_length_seconds) {
            $scaleFactor = $max_length_seconds / $rawTotal
        } elseif ($rawTotal -lt $min_length_seconds -and $rawTotal -gt 0) {
            $scaleFactor = $min_length_seconds / $rawTotal
        }

        # 3. Apply Scaling & Smart Weights
        $currentTime = 0
        $manifest.scenes = @()
        
        # Parse scene weights
        $weightList = if ($scene_weights) { $scene_weights -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } } else { @() }
        $fillWeight = $default_quality_weight
        if ($weightList.Count -gt 0) {
            # If a list is provided, use the lowest value as the "fill" weight for remainder
            $fillWeight = ($weightList | Measure-Object -Minimum).Minimum
        }

        for ($i=0; $i -lt $tempScenes.Count; $i++) {
            $s = $tempScenes[$i]
            
            # Apply Scaling
            $s.duration = [Math]::Round($s.duration * $scaleFactor, 1)
            $s.start_time = [Math]::Round($currentTime, 1)
            
            # Smart Weight Logic
            if ($i -lt $weightList.Count) {
                $s.quality_weight = $weightList[$i]
            } else {
                $s.quality_weight = $fillWeight
            }

            $currentTime += $s.duration + 3 # 3s scene transition buffer
            $manifest.scenes += $s
        }
        $manifest.total_length_seconds = [Math]::Round($currentTime, 1)

        # --- 6. Save Manifest ---
        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Set-Content -Path $jsonPath -Encoding UTF8
        "window.loadStoryboardData($manifestJson);" | Set-Content -Path (Join-Path $storyboard_dir "storyboard_data.js") -Encoding UTF8

        # --- 7. Generate HTML Dashboard ---
        Update-StoryboardDashboard -manifest $manifest -storyboard_dir $storyboard_dir

        $successMsg = "Successfully initialized storyboard project in '$project_dir'."
        $dashPath = Join-Path $storyboard_dir "storyboard.html"
        $guidance = "`n`nNEXT STEPS: Init complete. Call create_storyboard again with mode='decompose' to generate shot lists."
        return "CONSOLE::[INIT] $($successMsg)::END_CONSOLE::$($successMsg)`nManifest: $($jsonPath)`nDashboard: $($dashPath)$($guidance)"
    }

    elseif ($mode -eq "set-quality") {
        if (-not $existingManifest) { return "ERROR: Storyboard manifest not found." }
        if (-not $scene_id) { return "ERROR: -scene_id is required for set-quality mode." }
        if ($null -eq $weight) { return "ERROR: -weight (1-10) is required for set-quality mode." }

        $manifest = $existingManifest
        $targetScene = $manifest.scenes | Where-Object { $_.id -eq $scene_id }
        if (-not $targetScene) { return "ERROR: Scene $scene_id not found in manifest." }

        $targetScene.quality_weight = $weight
        # Update resolution based on max quality in project
        $maxQ = ($manifest.scenes | Measure-Object -Property quality_weight -Maximum).Maximum
        $manifest.resolution = $script:QualityToResolution[[int]$maxQ]

        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Set-Content -Path $jsonPath -Encoding UTF8
        "window.loadStoryboardData($manifestJson);" | Set-Content -Path (Join-Path $storyboard_dir "storyboard_data.js") -Encoding UTF8
        Update-StoryboardDashboard -manifest $manifest -storyboard_dir $storyboard_dir

        $msg = "Successfully updated Scene $scene_id quality weight to $weight."
        return "CONSOLE::[SET-QUALITY] $msg::END_CONSOLE::$msg"
    }

    elseif ($mode -eq "regenerate-shot") {
        if (-not $existingManifest) { return "ERROR: Storyboard manifest not found." }
        if (-not $scene_id) { return "ERROR: -scene_id is required." }
        if (-not $shot_id) { return "ERROR: -shot_id is required." }
        if (-not $script:API_KEY) { return "ERROR: Google API key not found." }

        $manifest = $existingManifest
        $targetScene = $manifest.scenes | Where-Object { $_.id -eq $scene_id }
        if (-not $targetScene) { return "ERROR: Scene $scene_id not found." }

        $targetShotIndex = -1
        for ($i=0; $i -lt $targetScene.shots.Count; $i++) {
            if ($targetScene.shots[$i].id -eq $shot_id) { $targetShotIndex = $i; break }
        }
        if ($targetShotIndex -lt 0) { return "ERROR: Shot $shot_id not found in scene." }
        
        $targetShot = $targetScene.shots[$targetShotIndex]

        $charText = ($manifest.characters | ForEach-Object { "CHARACTER: $($_.name) - $($_.description)" }) -join "`n"
        $locText = ""
        if ($manifest.locations -is [System.Collections.IDictionary]) {
            $locText = ($manifest.locations.Keys | Where-Object { $_ } | ForEach-Object { "LOCATION: $_ - $($manifest.locations[$_])" }) -join "`n"
        } elseif ($manifest.locations -is [PSCustomObject]) {
            $locText = ($manifest.locations.PSObject.Properties | ForEach-Object { "LOCATION: $($_.Name) - $($_.Value)" }) -join "`n"
        }

        $noteText = if (-not [string]::IsNullOrWhiteSpace($note)) { "`nDIRECTOR'S NOTE FOR REGENERATION:`n$note`n" } else { "" }

        $prompt = @"
You are a cinematic producer and director. You need to REGENERATE a single specific shot from a scene.

SCENE: $($targetScene.id): $($targetScene.slug)
SCRIPT TEXT:
$($targetScene.text)

MANIFEST DATA:
$charText
$locText

THE SHOT TO REGENERATE:
ID: $($targetShot.id)
Original Description: $($targetShot.description)$noteText

CONSTRAINTS FOR THIS SHOT:
- MUST be EXACTLY $($targetShot.duration_seconds) seconds (DO NOT CHANGE DURATION).
- Quality Weight: $($targetShot.quality_weight)
- Project Resolution: $($manifest.resolution)
- VEO DURATION RULE: Generated video shots MUST be exactly 4, 6, or 8 seconds. 
- VEO EXTENDED RULE: For long 720p or 1080p action shots, you may use 'veo_extended' for up to 15s.
- 4K HARD STOP: If the project resolution is 4K, all 'veo' shots MUST be exactly 8 seconds.
- You must act as a PRODUCER: Decide where to spend on 'veo' or 'parallax' and where to save using 'panzoom' or 'static_image'.
- VEO AUDIO RULE: If a veo shot contains a character speaking, set veo_audio_mode to "baked_dialogue" and leave vo.script EMPTY — Veo handles the voice. If a veo shot is an action/scenery shot with no dialogue, set veo_audio_mode to "silent" and provide vo/music/sfx separately.
- SFX RULE: Every shot MUST have at least one sfx entry. "No sound" is not valid — silence is itself an sfx entry ("SILENCE: Dead quiet interior, no ambient.").
- VO ROLE RULE: Set vo.role to "narrator", "character", or "silent".
- MUSIC RULE: Do not leave music.cue blank. If the shot continues the previous scene's music, write "continue" in cue and set behavior to "continue".

JSON FORMAT:
[
  {
    "description": "Visual prompt...",
    "fg_description": "Foreground prompt if parallax, else empty.",
    "script_line_ref": "Short text snippet...",
    "camera_move": "zoom_in|hold_wide|etc",
    "duration_seconds": $($targetShot.duration_seconds),
    "shot_type": "static_image|parallax|veo_lite|veo_720p|veo_1080p|veo_4k|veo_extended",
    "cut_out": "hard_cut|crossfade",
    "audio": {
      "vo": { "role": "narrator|character|silent", "character_id": "", "script": "..." },
      "music": { "cue": "describe mood/instrumentation", "behavior": "fade_in|continue|fade_out|cut" },
      "sfx": [
        { "label": "LABEL_ALLCAPS", "description": "What the sound sounds like and where it sits." }
      ],
      "veo_audio_mode": "silent|baked_dialogue|baked_ambient"
    },
    "suggested_quality_weight": $($targetShot.quality_weight)
  }
]
"@

        try {
            $geminiUri = Get-GeminiUri
            $config = @{ maxOutputTokens = 8192; temperature = 0.7; topP = 0.95 }
            $rawText = Invoke-SingleTurnApi -uri $geminiUri -prompt $prompt -spinnerLabel "Director: Regenerating Shot $($shot_id)..." -backend "gemini" -configOverride $config
            
            if ($rawText -like "ERROR:*") { return $rawText }
            if ($rawText.candidates) { $rawText = $rawText.candidates[0].content.parts[0].text.Trim() }
            
            $cleanJson = Extract-Json -text $rawText
            $returnedShots = $cleanJson | ConvertFrom-Json -ErrorAction Stop
            
            if ($returnedShots -isnot [array]) { $returnedShots = @($returnedShots) }
            $rs = $returnedShots[0]

            $voRole = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.role } else { "silent" }
            $voCharId = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.character_id } else { "" }
            $voScript = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.script } else { "" }
            $musicCue = if ($rs.audio -and $rs.audio.music) { $rs.audio.music.cue } else { "" }
            $musicBehavior = if ($rs.audio -and $rs.audio.music) { $rs.audio.music.behavior } else { "none" }
            $veoAudioMode = if ($rs.audio -and $rs.audio.veo_audio_mode) { $rs.audio.veo_audio_mode } else { "silent" }
            $sfxArray = if ($rs.audio -and $rs.audio.sfx) { @($rs.audio.sfx) | Where-Object { $_ -ne $null } } else { @() }

            $sObj = New-ShotObject -id $shot_id -scene_id $scene_id `
                -description $rs.description `
                -quality_weight $targetShot.quality_weight `
                -duration $targetShot.duration_seconds `
                -camera_move $rs.camera_move `
                -shot_type $rs.shot_type `
                -cut_out $rs.cut_out `
                -vo_role $voRole `
                -vo_character_id $voCharId `
                -vo_script $voScript `
                -music_cue $musicCue `
                -music_behavior $musicBehavior `
                -sfx_array $sfxArray `
                -veo_audio_mode $veoAudioMode `
                -status "proposed" `
                -start_time $targetShot.start_time `
                -line_ref $rs.script_line_ref `
                -fg_description $rs.fg_description

            $targetScene.shots[$targetShotIndex] = $sObj

            $manifestJson = $manifest | ConvertTo-Json -Depth 10
            $manifestJson | Set-Content -Path $jsonPath -Encoding UTF8
            "window.loadStoryboardData($manifestJson);" | Set-Content -Path (Join-Path $storyboard_dir "storyboard_data.js") -Encoding UTF8
            Update-StoryboardDashboard -manifest $manifest -storyboard_dir $storyboard_dir

            $msg = "Successfully regenerated Shot $shot_id."
            return "CONSOLE::[REGENERATE] $msg::END_CONSOLE::$msg"
        } catch {
            return "ERROR: Failed to regenerate shot. $($_.Exception.Message)"
        }
    }

    elseif ($mode -in @("approve-shot", "approve-all")) {
        if (-not $existingManifest) { return "ERROR: Storyboard manifest not found." }

        $manifest = $existingManifest
        $shotsToApprove = @()

        if ($mode -eq "approve-shot") {
            if (-not $scene_id) { return "ERROR: -scene_id is required." }
            if (-not $shot_id) { return "ERROR: -shot_id is required." }
            
            $targetScene = $manifest.scenes | Where-Object { $_.id -eq $scene_id }
            if (-not $targetScene) { return "ERROR: Scene $scene_id not found." }
            
            $targetShot = $targetScene.shots | Where-Object { $_.id -eq $shot_id }
            if (-not $targetShot) { return "ERROR: Shot $shot_id not found." }
            $shotsToApprove += $targetShot
        } else {
            foreach ($scene in $manifest.scenes) {
                if ($scene.shots) {
                    $shotsToApprove += $scene.shots
                }
            }
        }

        $passed = 0
        $failed = 0
        $warned = 0

        foreach ($shot in $shotsToApprove) {
            $criticals = [System.Collections.Generic.List[string]]::new()
            $warns = [System.Collections.Generic.List[string]]::new()

            # Critical Errors
            if ([string]::IsNullOrWhiteSpace($shot.description)) { $criticals.Add("Missing visual description/prompt.") }
            if ($null -eq $shot.duration_seconds -or $shot.duration_seconds -le 0) { $criticals.Add("Duration is 0 or missing.") }
            
            $fgPrompt = $null
            if ($shot.assets -and $shot.assets.fg -and $shot.assets.fg.prompt) { $fgPrompt = $shot.assets.fg.prompt }
            if ($shot.shot_type -eq "parallax" -and [string]::IsNullOrWhiteSpace($fgPrompt)) { $criticals.Add("Parallax shot missing fg_description.") }
            
            if ($shot.audio.veo_audio_mode -eq "baked_dialogue" -and $shot.shot_type -notmatch "veo") { $criticals.Add("veo_audio_mode is 'baked_dialogue' but shot_type is not 'veo'.") }
            if ($shot.shot_type -match "veo") {
                if ($shot.duration_seconds -notin @(4, 6, 8, 15)) {
                    $criticals.Add("Veo shot duration MUST be exactly 4, 6, 8, or 15 seconds.")
                }
            }

            # Warnings
            if (-not $shot.audio.sfx -or $shot.audio.sfx.Count -eq 0) { $warns.Add("SFX array is completely empty.") }
            if ([string]::IsNullOrWhiteSpace($shot.audio.music.cue) -or $shot.audio.music.behavior -eq "none") { $warns.Add("Music cue is blank or behavior is 'none'.") }

            $shot.warnings = [string[]]($criticals.ToArray() + $warns.ToArray())

            if ($criticals.Count -gt 0) {
                $shot.status = "error"
                $failed++
            } elseif ($warns.Count -gt 0) {
                $shot.status = "warning"
                $warned++
            } else {
                $shot.status = "approved"
                $passed++
            }
        }

        $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Set-Content -Path $jsonPath -Encoding UTF8
        "window.loadStoryboardData($manifestJson);" | Set-Content -Path (Join-Path $storyboard_dir "storyboard_data.js") -Encoding UTF8
        Update-StoryboardDashboard -manifest $manifest -storyboard_dir $storyboard_dir

        if ($mode -eq "approve-shot") {
            $msg = "Pre-flight complete for Shot $shot_id: $($shotsToApprove[0].status.ToUpper())."
            return "CONSOLE::[APPROVE] $msg::END_CONSOLE::$msg"
        } else {
            $msg = "Pre-flight complete for $($shotsToApprove.Count) shots: $passed passed, $warned warned, $failed failed."
            return "CONSOLE::[APPROVE-ALL] $msg::END_CONSOLE::$msg"
        }
    }

    elseif ($mode -eq "decompose") {
        if (-not $existingManifest) { return "ERROR: Storyboard manifest not found. Run mode='init' first." }
        if (-not (Test-Path $local_script_path)) { return "ERROR: Script file not found at '$local_script_path'." }

        if (-not $script:API_KEY) { return "ERROR: Google API key not found." }

        $manifest = $existingManifest
        $scenesProcessed = 0
        $totalShots = 0
        $totalWarnings = 0

        foreach ($scene in $manifest.scenes) {
            # Skip if all shots in this scene are already locked
            if ($scene.shots -and $scene.shots.Count -gt 0 -and ($scene.shots | Where-Object { $_.locked -eq $false }).Count -eq 0) {
                continue
            }

            $scenesProcessed++
            
            # Build Decompose Prompt
            $charText = ($manifest.characters | ForEach-Object { "CHARACTER: $($_.name) - $($_.description)" }) -join "`n"

            $locText = ""
            if ($manifest.locations -is [System.Collections.IDictionary]) {
                $locText = ($manifest.locations.Keys | Where-Object { $_ } | ForEach-Object { "LOCATION: $_ - $($manifest.locations[$_])" }) -join "`n"
            } elseif ($manifest.locations -is [PSCustomObject]) {
                $locText = ($manifest.locations.PSObject.Properties | ForEach-Object { "LOCATION: $($_.Name) - $($_.Value)" }) -join "`n"
            }
            
            # --- Calculate Production Budget ---
            # Q1 = $0.00, Q2-Q9 = $0.01 to $0.50 per second, Q10 = Unlimited
            $ratePerSec = if ($scene.quality_weight -le 1) { 0 } elseif ($scene.quality_weight -ge 10) { 100 } else { ($scene.quality_weight - 1) * 0.06 }
            $sceneBudget = [Math]::Round($ratePerSec * $scene.duration, 2)
            $budgetMsg = if ($scene.quality_weight -ge 10) { "UNLIMITED (Use high-end VEO video for everything)" } else { "`$$sceneBudget total for this scene" }

            $prompt = @"
You are a cinematic producer and director. Your goal is to maximize visual quality while staying within a strict PRODUCTION BUDGET.

SCENE: $($scene.id): $($scene.slug)
DURATION: $($scene.duration) seconds
TOTAL PRODUCTION BUDGET: $budgetMsg

PRICE LIST (2026 API Rates):
- `$0.00 (FREE): text_only, panzoom (Ken Burns), audio (VO/Music)
- `$0.02 per shot: static_image (Standard AI generation)
- `$0.04 per shot: parallax (Requires foreground + background generation)
- `$0.05 - `$0.30 per second: veo (Generative AI video - cost varies by resolution)

SCRIPT TEXT:
$($scene.text)

MANIFEST DATA:
$charText
$locText

PROMPT GUIDE (For 'description' field):
When using 'veo' or 'parallax', structure your description using these keys:
1. SUBJECT: The main object, person, or scenery.
2. ACTION: What the subject is doing.
3. CAMERA: Positioning and motion (e.g., dolly shot, aerial view, worm's eye).
4. LENS: Focus and effects (e.g., shallow focus, macro lens, wide-angle).
5. AMBIANCE: Light and color (e.g., blue tones, warm sunset glow).

CONSTRAINTS:
- Project Resolution: $($manifest.resolution)
- Max Quality Weight for this scene: $($scene.quality_weight)
- VEO DURATION RULE: Generated video shots MUST be exactly 4, 6, or 8 seconds. 
- VEO EXTENDED RULE: For long 720p or 1080p action shots, the AI is now explicitly allowed to use the veo_extended shot type for durations up to 15 seconds maximum.
- 4K HARD STOP: If the project resolution is 4K (Quality 10), the AI is instructed that veo_extended is strictly forbidden and it MUST generate standard 8-second blocks.
- TOTAL TIME: Shot durations MUST sum exactly to $($scene.duration) seconds.
- You must act as a PRODUCER: Decide where to spend on 'veo' or 'parallax' and where to save using 'panzoom' or 'static_image'.
- Use CHARACTER descriptions from manifest VERBATIM.
- VEO AUDIO RULE: If a veo shot contains a character speaking, set veo_audio_mode to "baked_dialogue" and leave vo.script EMPTY — Veo handles the voice. If a veo shot is an action/scenery shot with no dialogue, set veo_audio_mode to "silent" and provide vo/music/sfx separately.
- SFX RULE: Every shot MUST have at least one sfx entry. If the scene is indoors, include ambient room tone. If outdoors, include weather/environment. "No sound" is not valid — silence is itself an sfx entry ("SILENCE: Dead quiet interior, no ambient.").
- VO ROLE RULE: Set vo.role to "narrator" for third-person narration, "character" for a specific character speaking (and set character_id to their manifest ID), or "silent" if there is no spoken word in this shot.
- MUSIC RULE: Do not leave music.cue blank. If the shot continues the previous scene's music, write "continue" in cue and set behavior to "continue". Never use "none" — write what you hear.

JSON FORMAT:
[
  {
    "description": "Visual prompt (Follow the PROMPT GUIDE)...",
    "fg_description": "Foreground prompt if parallax, else empty.",
    "script_line_ref": "Short text snippet...",
    "camera_move": "zoom_in|hold_wide|etc",
    "duration_seconds": 8.0,
    "shot_type": "static_image|parallax|veo_lite|veo_720p|veo_1080p|veo_4k|veo_extended",
    "cut_out": "hard_cut|crossfade",
    "audio": {
      "vo": { "role": "narrator|character|silent", "character_id": "", "script": "..." },
      "music": { "cue": "describe mood/instrumentation", "behavior": "fade_in|continue|fade_out|cut" },
      "sfx": [
        { "label": "LABEL_ALLCAPS", "description": "What the sound sounds like and where it sits." }
      ],
      "veo_audio_mode": "silent|baked_dialogue|baked_ambient"
    },
    "suggested_quality_weight": $($scene.quality_weight)
  }
]
"@

            # API Call
            try {
                $geminiUri = Get-GeminiUri
                $config = @{ maxOutputTokens = 16384; temperature = 0.7; topP = 0.95 }
                $rawText = Invoke-SingleTurnApi -uri $geminiUri -prompt $prompt -spinnerLabel "Director: Decomposing Scene $($scene.id)..." -backend "gemini" -configOverride $config
                
                if ($rawText -like "ERROR:*") {
                    return $rawText
                }

                # If we got a full response object (due to configOverride), extract the text
                if ($rawText.candidates) {
                    $rawText = $rawText.candidates[0].content.parts[0].text.Trim()
                }
                
                # Extract and Parse JSON
                $cleanJson = Extract-Json -text $rawText
                $returnedShots = $null
                try {
                    $returnedShots = $cleanJson | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    # DEBUG: Save raw response to help diagnose truncation/corruption
                    $debugPath = Join-Path $storyboard_dir "last_error_raw.txt"
                    $rawText | Set-Content -Path $debugPath -Encoding UTF8
                    
                    return "ERROR: Scene $($scene.id) failed to parse JSON. Raw response saved to $debugPath for investigation.`nJSON Snippet: $($cleanJson.Substring(0, [Math]::Min(100, $cleanJson.Length)))...`nFull Error: $($_.Exception.Message)"
                }

                if ($null -eq $returnedShots) {
                    return "ERROR: Scene $($scene.id) returned null shots after parsing."
                }
                
                # Ensure it's an array for foreach
                if ($returnedShots -isnot [array]) {
                    $returnedShots = @($returnedShots)
                }
                
                $newShots = [System.Collections.Generic.List[object]]::new()
                $runningDuration = 0
                $staticCount = 0
                $currentShotStartTime = $scene.start_time

                foreach ($rs in $returnedShots) {
                    # Skip malformed shots (likely from truncation repair)
                    if ([string]::IsNullOrWhiteSpace($rs.description) -or ($null -eq $rs.duration_seconds) -or $rs.duration_seconds -le 0) {
                        continue
                    }

                    $totalShots++
                    $shotCount = $newShots.Count + 1
                    $shotId = "$($scene.id).$shotCount"
                    
                    $voRole = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.role } else { "silent" }
                    $voCharId = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.character_id } else { "" }
                    $voScript = if ($rs.audio -and $rs.audio.vo) { $rs.audio.vo.script } else { "" }
                    $musicCue = if ($rs.audio -and $rs.audio.music) { $rs.audio.music.cue } else { "" }
                    $musicBehavior = if ($rs.audio -and $rs.audio.music) { $rs.audio.music.behavior } else { "none" }
                    $veoAudioMode = if ($rs.audio -and $rs.audio.veo_audio_mode) { $rs.audio.veo_audio_mode } else { "silent" }
                    $sfxArray = if ($rs.audio -and $rs.audio.sfx) { @($rs.audio.sfx) | Where-Object { $_ -ne $null } } else { @() }

                    # Create Shot Object via Helper
                    $sObj = New-ShotObject -id $shotId -scene_id $scene.id `
                        -description $rs.description `
                        -quality_weight $rs.suggested_quality_weight `
                        -duration $rs.duration_seconds `
                        -camera_move $rs.camera_move `
                        -shot_type $rs.shot_type `
                        -cut_out $rs.cut_out `
                        -vo_role $voRole `
                        -vo_character_id $voCharId `
                        -vo_script $voScript `
                        -music_cue $musicCue `
                        -music_behavior $musicBehavior `
                        -sfx_array $sfxArray `
                        -veo_audio_mode $veoAudioMode `
                        -status "proposed" `
                        -start_time $currentShotStartTime `
                        -line_ref $rs.script_line_ref `
                        -fg_description $rs.fg_description

                    # Increment timeline
                    $currentShotStartTime += $rs.duration_seconds

                    # --- Validation Rules ---
                    # 1. Parallax min 4s
                    if ($sObj.shot_type -eq "parallax" -and $sObj.duration_seconds -lt 4) {
                        $sObj.warnings += "Parallax shot too short (min 4s recommended)."
                        $totalWarnings++
                    }
                    
                    # 2. 4+ consecutive statics
                    if ($sObj.shot_type -match "static|text|blur") { $staticCount++ } else { $staticCount = 0 }
                    if ($staticCount -ge 4) {
                        $sObj.warnings += "Too many consecutive static shots. Consider motion."
                        $totalWarnings++
                    }

                    # 3. Quality consistency
                    $expectedType = $script:QualityToShotType[[int]$sObj.quality_weight]
                    if ($sObj.shot_type -ne $expectedType -and $sObj.quality_weight -ge 5) {
                        # Minor warning, just for tracking
                    }

                    # 5. Veo baked_dialogue on a non-veo shot_type
                    if ($sObj.audio.veo_audio_mode -eq "baked_dialogue" -and $sObj.shot_type -notmatch "veo") {
                        $sObj.warnings += "veo_audio_mode 'baked_dialogue' set on non-veo shot — should be 'silent'."
                        $totalWarnings++
                    }

                    # 6. SFX array empty
                    if (-not $sObj.audio.sfx -or $sObj.audio.sfx.Count -eq 0) {
                        $sObj.warnings += "No SFX entries — at least one ambient/SFX required per shot."
                        $totalWarnings++
                    }

                    # 7. Blank music cue
                    if ([string]::IsNullOrWhiteSpace($sObj.audio.music.cue) -or $sObj.audio.music.behavior -eq "none") {
                        $sObj.warnings += "Music cue is blank or behavior is 'none' — fill in what you hear."
                        $totalWarnings++
                    }

                    $newShots.Add($sObj)
                    $runningDuration += $sObj.duration_seconds
                }

                # 4. Duration Sum Check
                if ([Math]::Abs($runningDuration - $scene.duration) -gt 0.5) {
                    $newShots[0].warnings += "Scene duration mismatch (Expected: $($scene.duration)s, Got: $($runningDuration)s)."
                    $totalWarnings++
                }

                # Preserve locked shots if they exist
                if ($scene.shots) {
                    $lockedShots = $scene.shots | Where-Object { $_.locked -eq $true }
                    if ($lockedShots) {
                        # This is a bit complex to merge perfectly, so we'll just append proposed shots after locked ones
                        $scene.shots = $lockedShots + $newShots
                    } else {
                        $scene.shots = $newShots
                    }
                } else {
                    $scene.shots = $newShots
                }

                # --- Update & Save Progress (Per Scene) ---
                $manifest.total_shot_count = ($manifest.scenes | ForEach-Object { if ($_.shots) { $_.shots.Count } else { 0 } } | Measure-Object -Sum).Sum
                $manifestJson = $manifest | ConvertTo-Json -Depth 10
        $manifestJson | Set-Content -Path $jsonPath -Encoding UTF8
        "window.loadStoryboardData($manifestJson);" | Set-Content -Path (Join-Path $storyboard_dir "storyboard_data.js") -Encoding UTF8
                Update-StoryboardDashboard -manifest $manifest -storyboard_dir $storyboard_dir
                
                # Breather for the API
                Start-Sleep -Seconds 1

            } catch {
                return "ERROR: Gemini failed to decompose scene $($scene.id). $($_.Exception.Message)"
            }
        }

        $msg = "Decompose complete. Processed $($scenesProcessed) scenes, created $($totalShots) shots with $($totalWarnings) warnings."
        $dashPath = Join-Path $storyboard_dir "storyboard.html"
        return "CONSOLE::[DECOMPOSE] $($msg)::END_CONSOLE::$($msg)`nDashboard: $($dashPath)"
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "create_storyboard"
    Icon        = "🎨"
    RendersToConsole = $false
    Category    = @("Digital Media Production")
    Version     = "1.2.5"
    
    Relationships = @{
        "write_script" = "When both tools are active, 'create_storyboard' uses the script file generated by 'write_script' to build the scene manifest and visual dashboard."
        "nanobanana"   = "Use 'nanobanana' to fulfill the image generation requirements defined by this tool's manifest."
    }

    Behavior    = "Manages a cinematic production project using an 'AI Producer' budget model. `mode='init'` parses a script with cinematic pacing (10-minute target). `mode='decompose'` breaks scenes into shots based on a dollar budget (Q1-Q10). Dashboard allows interactive budget updates."
    
    Description = "Builds and manages a visual storyboard manifest and dashboard with AI production budgeting."
    
    Parameters  = @{
        project_dir            = "string - Optional. Path to the root project folder."
        script_path            = "string - Path to the screenplay script.txt."
        min_length_seconds     = "int - Minimum target duration. Default 60."
        max_length_seconds     = "int - Maximum target duration (aim for 600s/10m). Default 600."
        default_quality_weight = "int - Default quality level (1-10). Default 1."
        scene_weights          = "string - Comma-separated list of weights (e.g. '1,5,1') provided during init."
        length_tier            = "string - 'short' (5-15m) or 'long' (15-90m)."
        scene_id               = "int - Target scene ID for mode='set-quality' or 'regenerate-shot'."
        shot_id                = "string - Target shot ID (e.g., '1.3') for mode='regenerate-shot'."
        note                   = "string - Optional. Director's note for mode='regenerate-shot'."
        weight                 = "int - New quality weight (1-10) for mode='set-quality'."
        style                  = "string - Optional. Visual style (e.g. 'Cyberpunk Anime')."
        mode                   = "string - 'init', 'decompose', 'set-quality', 'regenerate-shot', 'approve-shot', or 'approve-all'. Default 'init'."
    }
    
    Example     = '<tool_call>{ "name": "create_storyboard", "parameters": { "project_dir": "./Project_Alpha", "scene_weights": "1,5,1,1,10", "mode": "init" } }</tool_call>'
    
    FormatLabel = { param($p) "($($p.mode)) -> $($p.project_dir)" }
    
    ToolUseGuidanceMajor = @"
        - 'init': Use this to start a project. It will return an ACTION_REQUIRED message with a scene list.
        - 'set-quality': Use this when the user wants to manually adjust a scene's budget. Requires -scene_id and -weight.
        - 'decompose': Use this to generate the actual shot list once weights are set.
        - 'regenerate-shot': Re-prompts the AI to rewrite a single specific shot (preserves exact duration). Requires -scene_id and -shot_id.
        - 'approve-shot' / 'approve-all': Runs pre-flight validation on shot(s). Changes status to 'approved', 'warning', or 'error'.
        - If the user provides a raw command string like 'create_storyboard -mode set-quality...', execute it exactly as requested.
"@

    Execute     = { param($params) Invoke-CreateStoryboardTool @params }
}
