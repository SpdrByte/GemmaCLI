# ===============================================
# GemmaCLI Tool - video_editor.ps1 v1.4.0
# Responsibility: Video editing via FFmpeg
#
# EDIT      trim, split, concat, resize, crop, speed, ken_burns, padding
# EFFECTS   mute, add_audio, overlay_text, overlay_image, filter, reverse, stabilize
# UTILITY   metadata, convert, thumbnail, extract_audio, make_gif
# ===============================================

# ── Helpers ─────────────────────────────────────────────────────────────────

function Get-SearchedPath {
    return ($env:PATH -split ';' | Where-Object { $_ } | ForEach-Object { "  $_" }) -join "`n"
}

function Find-FFmpeg {
    $cmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-FFprobe {
    $cmd = Get-Command "ffprobe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Has-Audio {
    param($ffprobe, [string]$file_path)
    if (-not $ffprobe) { return $false }
    $r = Run-FFmpeg $ffprobe @("-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_type", "-of", "csv=p=0", $file_path)
    return ($r.Stdout -match "audio")
}

function Get-VideoOutputPath {
    param(
        [string]$inputPath,
        [string]$suffix,
        [string]$ext = "" 
    )
    $dir  = [System.IO.Path]::GetDirectoryName($inputPath)
    if (-not $dir) { $dir = "." }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    if (-not $ext) { $ext = [System.IO.Path]::GetExtension($inputPath) }
    if (-not $ext.StartsWith(".")) { $ext = ".$ext" }
    $ts   = (Get-Date).ToString("yyyyMMdd_HHmmss")
    return Join-Path $dir "$($base)_$($suffix)_$ts$ext"
}

function Escape-Arg {
    param([string]$arg)
    if ($arg -notmatch '[ \t"]') { return $arg }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    $i = 0
    while ($i -lt $arg.Length) {
        $c = $arg[$i]
        if ($c -eq '\') {
            $numBS = 0
            while ($i -lt $arg.Length -and $arg[$i] -eq '\') { $numBS++; $i++ }
            if ($i -eq $arg.Length) {
                [void]$sb.Append('\' * ($numBS * 2))
            } elseif ($arg[$i] -eq '"') {
                [void]$sb.Append('\' * ($numBS * 2))
                [void]$sb.Append('\"')
                $i++
            } else {
                [void]$sb.Append('\' * $numBS)
            }
        } elseif ($c -eq '"') {
            [void]$sb.Append('\"')
            $i++
        } else {
            [void]$sb.Append($c)
            $i++
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Run-FFmpeg {
    param(
        [string]$ffmpeg,
        [string[]]$ffArgs
    )
    
    # Prepend -nostdin if not already present to prevent hangs in CLI/scripted environments
    $finalArgs = if ($ffArgs -notcontains "-nostdin") { @("-nostdin") + $ffArgs } else { $ffArgs }
    
    $escapedArgs = ($finalArgs | ForEach-Object { Escape-Arg $_ }) -join " "

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $ffmpeg
    $psi.Arguments              = $escapedArgs
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $proc.WaitForExit()
    [System.Threading.Tasks.Task]::WaitAll($stdoutTask, $stderrTask)

    return @{
        ExitCode = $proc.ExitCode
        Stdout   = $stdoutTask.Result
        Stderr   = $stderrTask.Result
    }
}

# ── Operation Functions ──────────────────────────────────────────────────────

function Op-Trim {
    param($ffmpeg, [string]$file_path, [string]$start, [string]$end_time, [string]$duration)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($start)) { return "ERROR: 'start' is required for trim." }

    $out = Get-VideoOutputPath $file_path "trimmed"
    $ffArgs = @("-y", "-ss", $start, "-i", $file_path)
    if ($duration)      { $ffArgs += @("-t", $duration) }
    elseif ($end_time)  { $ffArgs += @("-to", $end_time) }
    $ffArgs += @("-c", "copy", $out)

    $r = Run-FFmpeg $ffmpeg $ffArgs
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg trim failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Trimmed video saved to: $out::END_CONSOLE::OK: Trimmed video saved to '$out'"
}

function Op-Split {
    param($ffmpeg, [string]$file_path, [string]$split_at)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($split_at)) { return "ERROR: 'split_at' is required." }

    $dir  = [System.IO.Path]::GetDirectoryName($file_path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($file_path)
    $ext  = [System.IO.Path]::GetExtension($file_path)
    $ts   = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $out1 = Join-Path $dir "$($base)_part1_$ts$ext"
    $out2 = Join-Path $dir "$($base)_part2_$ts$ext"

    $r1 = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-t", $split_at, "-c", "copy", $out1)
    if ($r1.ExitCode -ne 0) { return "ERROR: FFmpeg split (part 1) failed.`n$($r1.Stderr)" }

    $r2 = Run-FFmpeg $ffmpeg @("-y", "-ss", $split_at, "-i", $file_path, "-c", "copy", $out2)
    if ($r2.ExitCode -ne 0) { return "ERROR: FFmpeg split (part 2) failed.`n$($r2.Stderr)" }

    return "CONSOLE::✅ Split into:`n  Part 1: $out1`n  Part 2: $out2::END_CONSOLE::OK: Split complete. Part 1: '$out1' | Part 2: '$out2'"
}

function Op-Concat {
    param($ffmpeg, [string]$file_paths, [string]$output_format)
    if ([string]::IsNullOrWhiteSpace($file_paths)) { return "ERROR: 'file_paths' is required." }

    $files = $file_paths -split "," | ForEach-Object { $_.Trim().Trim("'").Trim('"') }
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { return "ERROR: File not found: '$f'" }
    }

    $listFile  = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".txt")
    $lines     = $files | ForEach-Object { "file '$($_.Replace('\', '/'))'" }
    [System.IO.File]::WriteAllLines($listFile, $lines, [System.Text.UTF8Encoding]::new($false))

    $ext = if ($output_format) { ".$($output_format.TrimStart('.'))" } else { [System.IO.Path]::GetExtension($files[0]) }
    $out = Get-VideoOutputPath $files[0] "concat" ($ext.TrimStart('.'))

    $r = Run-FFmpeg $ffmpeg @("-y", "-f", "concat", "-safe", "0", "-i", $listFile, "-c", "copy", $out)
    Remove-Item $listFile -Force -ErrorAction SilentlyContinue

    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg concat failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Concatenated $($files.Count) files -> $out::END_CONSOLE::OK: Concatenated $($files.Count) files to '$out'"
}

function Op-Resize {
    param($ffmpeg, [string]$file_path, [string]$resolution)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($resolution)) { return "ERROR: 'resolution' is required (e.g. '1280x720')." }

    $out = Get-VideoOutputPath $file_path "resized"
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "scale=$($resolution.Replace('x', ':'))", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg resize failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Resized to $resolution -> $out::END_CONSOLE::OK: Resized to $resolution, saved to '$out'"
}

function Op-Crop {
    param($ffmpeg, [string]$file_path, [string]$w, [string]$h, [string]$x, [string]$y)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($w) -or [string]::IsNullOrWhiteSpace($h)) { return "ERROR: 'w' and 'h' are required for crop." }
    if (-not $x) { $x = "0" }
    if (-not $y) { $y = "0" }

    $out = Get-VideoOutputPath $file_path "cropped"
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "crop=${w}:${h}:${x}:${y}", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg crop failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Cropped to ${w}x${h} -> $out::END_CONSOLE::OK: Cropped to ${w}x${h}, saved to '$out'"
}

function Op-Speed {
    param($ffmpeg, $ffprobe, [string]$file_path, [string]$speed)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($speed)) { return "ERROR: 'speed' is required." }

    $speedVal = [double]$speed
    $vPts = 1.0 / $speedVal
    $out = Get-VideoOutputPath $file_path "speed$($speed)x"

    if (Has-Audio $ffprobe $file_path) {
        $aTempo = $speedVal
        # Build audio filter chain (atempo is 0.5-2.0 per stage)
        $aFilters = @()
        $remaining = $aTempo
        while ($remaining -gt 2.0) { $aFilters += "atempo=2.0"; $remaining /= 2.0 }
        while ($remaining -lt 0.5) { $aFilters += "atempo=0.5"; $remaining /= 0.5 }
        $aFilters += "atempo=$remaining"
        $aFilterStr = $aFilters -join ","
        $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-filter_complex", "[0:v]setpts=$($vPts)*PTS[v];[0:a]$aFilterStr[a]", "-map", "[v]", "-map", "[a]", $out)
    } else {
        $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "setpts=$($vPts)*PTS", $out)
    }

    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg speed change failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Speed changed to $($speed)x -> $out::END_CONSOLE::OK: Speed changed to $($speed)x, saved to '$out'"
}

function Op-Mute {
    param($ffmpeg, [string]$file_path)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "muted"
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-an", "-vcodec", "copy", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg mute failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Video muted -> $out::END_CONSOLE::OK: Video muted, saved to '$out'"
}

function Op-AddAudio {
    param($ffmpeg, [string]$file_path, [string]$audio_path, [bool]$replace = $true)
    if (-not (Test-Path $file_path)) { return "ERROR: Video file not found: '$file_path'" }
    if (-not (Test-Path $audio_path)) { return "ERROR: Audio file not found: '$audio_path'" }

    $out = Get-VideoOutputPath $file_path "withaudio"
    $ffArgs = @("-y", "-i", $file_path, "-i", $audio_path)
    if ($replace) {
        # Force map video from 0 and audio from 1
        $ffArgs += @("-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-shortest", $out)
    } else {
        # Mix audio from 0 (if exists) and 1
        $filter = "[0:a?][1:a]amix=inputs=2:duration=first:dropout_transition=0[a]"
        $ffArgs += @("-filter_complex", $filter, "-map", "0:v:0", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-shortest", $out)
    }

    $r = Run-FFmpeg $ffmpeg $ffArgs
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg add_audio failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Audio added -> $out::END_CONSOLE::OK: Audio added, saved to '$out'"
}

function Op-KenBurns {
    param($ffmpeg, [string]$file_path, [string]$duration, [string]$zoom_speed, [string]$resolution, [string]$pan)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    # Revert to healthy defaults if parameters are empty/null
    if ([string]::IsNullOrWhiteSpace($duration))   { $duration = "5" }
    if ([string]::IsNullOrWhiteSpace($zoom_speed)) { $zoom_speed = "0.002" }
    if ([string]::IsNullOrWhiteSpace($resolution)) { $resolution = "1920x1080" }
    if ([string]::IsNullOrWhiteSpace($pan))        { $pan = "center" }

    $out = Get-VideoOutputPath $file_path "kenburns" "mp4"
    $fps = 25
    
    # Parse target resolution
    $target = $resolution.Split('x')
    $tw = [int]$target[0]; $th = [int]$target[1]

    # CRITICAL FIX: The internal buffer MUST be larger than the output resolution
    # to give the zoompan filter "room" to move. We use 2x target size.
    $iw_internal = $tw * 2
    $ih_internal = $th * 2

    # Calculate X/Y expressions for the camera movement
    $xExpr = switch ($pan.ToLower()) {
        "left"   { "0" }
        "right"  { "iw-(iw/zoom)" }
        "top"    { "ih/2-(ih/zoom/2)" }
        "bottom" { "ih/2-(ih/zoom/2)" }
        default  { "iw/2-(iw/zoom/2)" }
    }
    $yExpr = switch ($pan.ToLower()) {
        "top"    { "0" }
        "bottom" { "ih-(ih/zoom)" }
        "left"   { "ih/2-(ih/zoom/2)" }
        "right"  { "ih/2-(ih/zoom/2)" }
        default  { "ih/2-(ih/zoom/2)" }
    }

    # ── THE STABLE HIGH-RES PIPELINE ──
    # 1. scale/pad to internal buffer size (e.g. 4K for a 1080p output)
    # 2. zoompan into that buffer and output at the requested resolution
    # We use '1+(on*speed)' to ensure the zoom accumulates over the loop.
    $vf = "scale=${iw_internal}:${ih_internal}:force_original_aspect_ratio=decrease," +
          "pad=${iw_internal}:${ih_internal}:(ow-iw)/2:(oh-ih)/2," +
          "setsar=1," +
          "zoompan=z='1+(on*${zoom_speed})':x='${xExpr}':y='${yExpr}':d=1:s=${resolution}:fps=${fps}," +
          "format=yuv420p"

    $r = Run-FFmpeg $ffmpeg @(
        "-y", 
        "-nostdin", 
        "-loglevel", "warning",
        "-loop", "1", 
        "-t", $duration, 
        "-i", $file_path, 
        "-vf", $vf, 
        "-c:v", "libx264", 
        "-preset", "ultrafast", 
        "-tune", "stillimage",
        $out
    )

    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg ken_burns failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Ken Burns video created (Pan: $pan) -> $out::END_CONSOLE::OK: Ken Burns clip saved to '$out'"
}

function Op-Padding {
    param($ffmpeg, [string]$file_path, [string]$resolution = "1920x1080", [string]$color = "black")
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "padded"
    $target = $resolution.Split('x')
    $tw = $target[0]; $th = $target[1]
    
    $vf = "scale=${tw}:${th}:force_original_aspect_ratio=decrease,pad=${tw}:${th}:(ow-iw)/2:(oh-ih)/2:$color"
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", $vf, "-c:a", "copy", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg padding failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Padded/Letterboxed to $resolution -> $out::END_CONSOLE::OK: Padded video saved to '$out'"
}

function Op-OverlayImage {
    param($ffmpeg, [string]$file_path, [string]$overlay_path, [string]$x, [string]$y)
    if (-not (Test-Path $file_path)) { return "ERROR: Base video not found: '$file_path'" }
    if (-not (Test-Path $overlay_path)) { return "ERROR: Overlay image not found: '$overlay_path'" }

    # Revert to healthy defaults if parameters are empty/null
    if ([string]::IsNullOrWhiteSpace($x)) { $x = "right" }
    if ([string]::IsNullOrWhiteSpace($y)) { $y = "bottom" }

    $out = Get-VideoOutputPath $file_path "overlay"

    # Map position aliases to FFmpeg overlay math
    # W/H = main video, w/h = overlay image
    $xMap = @{ "left" = "10"; "center" = "(W-w)/2"; "right" = "W-w-10" }
    $yMap = @{ "top" = "10"; "middle" = "(H-h)/2"; "center" = "(H-h)/2"; "bottom" = "H-h-10" }

    $finalX = if ($xMap.ContainsKey($x.ToLower())) { $xMap[$x.ToLower()] } else { $x }
    $finalY = if ($yMap.ContainsKey($y.ToLower())) { $yMap[$y.ToLower()] } else { $y }

    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-i", $overlay_path, "-filter_complex", "overlay=${finalX}:${finalY}", "-c:a", "copy", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg overlay_image failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Image overlay applied ($x,$y) -> $out::END_CONSOLE::OK: Overlay video saved to '$out'"
}

function Op-ExtractAudio {
    param($ffmpeg, [string]$file_path, [string]$format = "mp3")
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "audio" $format
    $codec = switch ($format.ToLower().TrimStart('.')) {
        "mp3"  { "libmp3lame" }
        "wav"  { "pcm_s16le" }
        "flac" { "flac" }
        "aac"  { "aac" }
        default { "copy" }
    }
    
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vn", "-acodec", $codec, $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg extract_audio failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Audio extracted to: $out::END_CONSOLE::OK: Audio extracted to '$out'"
}

function Op-Convert {
    param($ffmpeg, [string]$file_path, [string]$output_format)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($output_format)) { return "ERROR: 'output_format' is required." }

    $out = Get-VideoOutputPath $file_path "converted" $output_format
    # Use standard high-compatibility settings for conversion
    $ffArgs = @("-y", "-i", $file_path, "-c:v", "libx264", "-preset", "fast", "-crf", "23", "-c:a", "aac", "-b:a", "128k", $out)
    
    $r = Run-FFmpeg $ffmpeg $ffArgs
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg convert failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Converted to $output_format -> $out::END_CONSOLE::OK: Converted to '$out'"
}

function Op-OverlayText {
    param($ffmpeg, [string]$file_path, [string]$text, [string]$x, [string]$y, [string]$fontsize, [string]$fontcolor, [string]$font_name)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if ([string]::IsNullOrWhiteSpace($text)) { return "ERROR: 'text' is required." }

    # Revert to healthy defaults if parameters are empty/null
    if ([string]::IsNullOrWhiteSpace($x))         { $x = "center" }
    if ([string]::IsNullOrWhiteSpace($y))         { $y = "center" }
    if ([string]::IsNullOrWhiteSpace($fontsize))  { $fontsize = "48" }
    if ([string]::IsNullOrWhiteSpace($fontcolor)) { $fontcolor = "white" }
    if ([string]::IsNullOrWhiteSpace($font_name)) { $font_name = "arial" }

    $out = Get-VideoOutputPath $file_path "text"

    # Map position aliases to FFmpeg math
    $xMap = @{ "left" = "10"; "center" = "(w-text_w)/2"; "right" = "w-text_w-10" }
    $yMap = @{ "top" = "10"; "middle" = "(h-text_h)/2"; "center" = "(h-text_h)/2"; "bottom" = "h-text_h-10" }

    $finalX = if ($xMap.ContainsKey($x.ToLower())) { $xMap[$x.ToLower()] } else { $x }
    $finalY = if ($yMap.ContainsKey($y.ToLower())) { $yMap[$y.ToLower()] } else { $y }

    # Dynamic Font Lookup in Windows Fonts folder
    $fontFile = Join-Path $env:windir "Fonts\$($font_name.ToLower()).ttf"
    if (-not (Test-Path $fontFile)) {
        # Fallback to Arial if specific font not found
        $fontFile = Join-Path $env:windir "Fonts\arial.ttf"
    }
    
    # CRITICAL: Windows colons (C:) must be escaped as (C\:) for FFmpeg filters
    $fontPart = if (Test-Path $fontFile) { ":fontfile='$($fontFile.Replace('\', '/').Replace(':', '\:'))'" } else { "" }
    
    # Properly escaped filter string with variable delimiters
    $filter = "drawtext=text='${text}':x=${finalX}:y=${finalY}:fontsize=${fontsize}:fontcolor=${fontcolor}${fontPart}"
    
    $r = Run-FFmpeg $ffmpeg @("-y", "-nostdin", "-loglevel", "warning", "-i", $file_path, "-vf", $filter, "-c:a", "copy", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg overlay_text failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Text overlay applied ('$text' at $x,$y) -> $out::END_CONSOLE::OK: Text overlay applied, saved to '$out'"
}

function Op-Filter {
    param($ffmpeg, [string]$file_path, [string]$type = "grayscale")
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "filter_$type"
    $vf = switch ($type.ToLower()) {
        "grayscale" { "format=gray" }
        "sepia"     { "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131" }
        "vignette"  { "vignette" }
        "blur"      { "boxblur=5:1" }
        "sharpen"   { "unsharp=5:5:1.0:5:5:0.0" }
        "negative"  { "negate" }
        default     { return "ERROR: Unknown filter type '$type'. Use: grayscale, sepia, vignette, blur, sharpen, negative." }
    }

    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", $vf, "-c:a", "copy", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg filter failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Filter '$type' applied -> $out::END_CONSOLE::OK: Filtered video saved to '$out'"
}

function Op-MakeGif {
    param($ffmpeg, [string]$file_path, [string]$start = "0", [string]$duration = "3", [string]$scale = "480")
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "anim" "gif"
    # High quality GIF creation using a palette
    $palette = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".png")
    
    try {
        # Pass 1: Generate palette
        $r1 = Run-FFmpeg $ffmpeg @("-y", "-ss", $start, "-t", $duration, "-i", $file_path, "-vf", "fps=15,scale=${scale}:-1:flags=lanczos,palettegen", $palette)
        if ($r1.ExitCode -ne 0) { return "ERROR: GIF palette generation failed.`n$($r1.Stderr)" }

        # Pass 2: Generate GIF
        $r2 = Run-FFmpeg $ffmpeg @("-y", "-ss", $start, "-t", $duration, "-i", $file_path, "-i", $palette, "-filter_complex", "fps=15,scale=${scale}:-1:flags=lanczos[x];[x][1:v]paletteuse", $out)
        if ($r2.ExitCode -ne 0) { return "ERROR: GIF creation failed.`n$($r2.Stderr)" }

        return "CONSOLE::✅ High-quality GIF created -> $out::END_CONSOLE::OK: GIF saved to '$out'"
    } finally {
        Remove-Item $palette -Force -ErrorAction SilentlyContinue
    }
}

function Op-Reverse {
    param($ffmpeg, [string]$file_path)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "reversed"
    # Note: Reverse filter buffers everything in RAM, so it's slow/heavy for long videos
    $r = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "reverse", "-af", "areverse", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg reverse failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Video reversed -> $out::END_CONSOLE::OK: Reversed video saved to '$out'"
}

function Op-Stabilize {
    param($ffmpeg, [string]$file_path)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $out = Get-VideoOutputPath $file_path "stable"
    $transform = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".trf")
    
    try {
        # Pass 1: Detect shakes
        $r1 = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "vidstabdetect=result='$($transform.Replace('\', '/'))'", "-f", "null", "-")
        if ($r1.ExitCode -ne 0) { return "ERROR: Stabilization detection failed.`n$($r1.Stderr)" }

        # Pass 2: Apply stabilization
        $r2 = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-vf", "vidstabtransform=input='$($transform.Replace('\', '/'))':smoothing=30:crop=black", "-c:a", "copy", $out)
        if ($r2.ExitCode -ne 0) { return "ERROR: Stabilization transform failed.`n$($r2.Stderr)" }

        return "CONSOLE::✅ Video stabilized -> $out::END_CONSOLE::OK: Stabilized video saved to '$out'"
    } finally {
        Remove-Item $transform -Force -ErrorAction SilentlyContinue
    }
}

function Op-Metadata {
    param($ffprobe, [string]$file_path)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $ffprobe) { return "ERROR: ffprobe not found." }

    $r = Run-FFmpeg $ffprobe @("-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", $file_path)
    if ($r.ExitCode -ne 0) { return "ERROR: ffprobe failed.`n$($r.Stderr)" }
    return "CONSOLE::Metadata extracted.::END_CONSOLE::$($r.Stdout)"
}

# ── Main Dispatch ─────────────────────────────────────────────────────────────

function Invoke-VideoEditTool {
    param(
        [string]$operation,
        [string]$file_path,
        [string]$start,
        [string]$end_time,
        [string]$duration,
        [string]$split_at,
        [string]$file_paths,
        [string]$output_format,
        [string]$resolution,
        [string]$w, [string]$h, [string]$x, [string]$y,
        [string]$speed,
        [string]$audio_path,
        [bool]$replace_audio = $true,
        [string]$text,
        [string]$at,
        [string]$fontsize,
        [string]$fontcolor,
        [string]$zoom_speed,
        [string]$overlay_path,
        [string]$filter_type,
        [string]$gif_scale,
        [string]$color,
        [string]$pan,
        [string]$font_name
    )

    $ffmpeg  = Find-FFmpeg
    $ffprobe = Find-FFprobe

    if (-not $ffmpeg) { return "ERROR: FFmpeg not found in PATH." }

    $operation = $operation.Trim().ToLower()

    switch ($operation) {
        "trim"          { return Op-Trim          $ffmpeg $file_path $start $end_time $duration }
        "split"         { return Op-Split         $ffmpeg $file_path $split_at }
        "concat"        { return Op-Concat        $ffmpeg $file_paths $output_format }
        "resize"        { return Op-Resize        $ffmpeg $file_path $resolution }
        "crop"          { return Op-Crop          $ffmpeg $file_path $w $h $x $y }
        "speed"         { return Op-Speed         $ffmpeg $ffprobe $file_path $speed }
        "mute"          { return Op-Mute          $ffmpeg $file_path }
        "add_audio"     { return Op-AddAudio      $ffmpeg $file_path $audio_path $replace_audio }
        "extract_audio" { return Op-ExtractAudio  $ffmpeg $file_path }
        "overlay_text"  { return Op-OverlayText   $ffmpeg $file_path $text $x $y $fontsize $fontcolor $font_name }
        "thumbnail"     { return Op-Thumbnail     $ffmpeg $file_path $at }
        "metadata"      { return Op-Metadata      $ffprobe $file_path }
        "convert"       { return Op-Convert       $ffmpeg $file_path $output_format }
        "ken_burns"     { return Op-KenBurns      $ffmpeg $file_path $duration $zoom_speed $resolution $pan }
        "padding"       { return Op-Padding       $ffmpeg $file_path $resolution $color }
        "overlay_image" { return Op-OverlayImage  $ffmpeg $file_path $overlay_path $x $y }
        "filter"        { return Op-Filter        $ffmpeg $file_path $filter_type }
        "make_gif"      { return Op-MakeGif       $ffmpeg $file_path $start $duration $gif_scale }
        "reverse"       { return Op-Reverse       $ffmpeg $file_path }
        "stabilize"     { return Op-Stabilize     $ffmpeg $file_path }
        default         { return "ERROR: Unknown operation '$operation'." }
    }
}

# ── Self-registration block ───────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "video_editor"
    Icon             = "🎬"
    RendersToConsole = $false
    Category         = @("Digital Media Production")
    Version          = "1.1.9"

    Relationships = @{
        "create_storyboard" = "When both tools are active, you can use 'video_editor' to stitch storyboard frames into a cinematic preview or add transitions between scenes."
        "write_script"      = "Use 'video_editor' to help visualize or assemble clips based on the script's visual beats."
    }

    Tutorial = @"
I am a professional-grade video assembly engine. Here are some of my advanced capabilities:
- **ken_burns**: Generates a dynamic cinematic clip from a static image.
    - **Pan**: Specify 'left', 'right', 'top', 'bottom', or 'center' to control the movement direction.
    - **Zoom**: Use 'zoom_speed' values like 0.002 (subtle) to 0.01 (very fast). Default is 0.002.
    - **Aspect Ratio**: I automatically fit your image into the frame with black padding, ensuring it never stretches.
- **padding**: Implements professional letterboxing or pillarboxing, allowing you to fit inconsistent image sizes into a standardized frame (like 1080p) without distortion.
- **overlay_image**: Enables watermarking or logo placement at precise coordinates.
- **filter**: Adds support for artistic color and clarity adjustments, including Grayscale, Sepia, Vignette, Blur, Sharpen, and Negative.
- **make_gif**: Creates high-quality animated GIFs using a professional two-pass palette generation technique.
- **reverse**: Flips both the visual and audio timeline to play backward.
- **stabilize**: Performs a complex two-pass analysis to remove camera shake from handheld footage.

Try: 'video_editor operation="ken_burns" file_path="my_photo.jpg" duration="5" pan="right" zoom_speed="0.005"'
"@

    Behavior = @"
Use this tool to perform video editing operations via FFmpeg.
Choose 'operation' from the list below and supply only the parameters relevant to that operation.

── EDIT ────────────────────────────────────────────────────────────────────────
  trim          - Cut a clip. Params: file_path, start. Optional: end_time OR duration.
  split         - Split at timestamp. Params: file_path, split_at.
  concat        - Join files. Params: file_paths (comma-separated).
  resize        - Scale video. Params: file_path, resolution (e.g. 1920x1080).
  crop          - Crop frame. Params: file_path, w, h. Optional: x, y.
  speed         - Change speed. Params: file_path, speed (e.g. 2.0).
  ken_burns     - Panning/Zooming over static image. Params: file_path. Optional: duration, zoom_speed (0.002-0.01), resolution, pan (left, right, top, bottom, center).
  padding       - Letterbox/Pillarbox. Params: file_path, resolution. Optional: color (default black).

── EFFECTS ─────────────────────────────────────────────────────────────────────
  mute          - Remove audio. Params: file_path.
  add_audio     - Overlay or replace audio. Params: video file_path, audio_path. Optional: replace_audio (bool).
  overlay_text  - Draw text. Params: file_path, text. Optional: x, y, fontsize, fontcolor.
  overlay_image - Overlay watermark/logo. Params: file_path, overlay_path. Optional: x, y.
  filter        - Apply artistic filters. Params: file_path, filter_type (grayscale, sepia, vignette, blur, sharpen, negative).
  reverse       - Play backward. Params: file_path.
  stabilize     - Remove camera shake (two-pass). Params: file_path.

── UTILITY ─────────────────────────────────────────────────────────────────────
  extract_audio - Export sound. Params: file_path. Optional: output_format (mp3, wav, flac, aac).
  make_gif      - Create animated GIF. Params: file_path. Optional: start, duration, gif_scale (default 480).
  thumbnail     - Extract frame. Params: file_path. Optional: at (timestamp).
  metadata      - View deep info. Params: file_path.
  convert       - Re-encode video. Params: file_path, output_format.
"@

    Description = "Advanced Video Editor using FFmpeg - Editing, VFX, Ken Burns, Filters, and Utilities."

    Parameters = @{
        operation     = "string - Required. trim, split, concat, resize, crop, speed, mute, add_audio, extract_audio, overlay_text, overlay_image, ken_burns, padding, filter, reverse, stabilize, thumbnail, metadata, convert, make_gif."
        file_path     = "string - Path to input file."
        start         = "string - Start time."
        end_time      = "string - End time."
        duration      = "string - Duration."
        split_at      = "string - Split timestamp."
        file_paths    = "string - Comma-separated files."
        output_format = "string - Target format."
        resolution    = "string - e.g. 1920x1080."
        w             = "string - Width."
        h             = "string - Height."
        x             = "string - X offset."
        y             = "string - Y offset."
        speed         = "string - Speed multiplier."
        audio_path    = "string - Audio file path."
        replace_audio = "boolean - Replace vs mix audio."
        text          = "string - Overlay text content."
        at            = "string - Frame timestamp."
        fontsize      = "string - Font size."
        fontcolor     = "string - Font color."
        zoom_speed    = "string - Ken Burns speed (0.002 to 0.01 recommended)."
        overlay_path  = "string - Watermark/Overlay image path."
        filter_type   = "string - grayscale, sepia, vignette, blur, sharpen, negative."
        gif_scale     = "string - GIF width (default 480)."
        color         = "string - Padding color (default black)."
        pan           = "string - Ken Burns direction: left, right, top, bottom, center."
    }

    Example = '<tool_call>{ "name": "video_editor", "parameters": { "operation": "ken_burns", "file_path": "scene.jpg", "duration": "5", "pan": "right", "zoom_speed": "0.005" } }</tool_call>'

    FormatLabel = { param($p) "[$($p.operation)] -> $(if($p.file_path){Split-Path $p.file_path -Leaf}else{'...'})" }

    Execute = { param($params) Invoke-VideoEditTool @params }
}

