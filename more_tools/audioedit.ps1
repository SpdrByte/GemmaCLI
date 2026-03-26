# ===============================================
# GemmaCLI Tool - audioedit.ps1 v1.0.4
# Responsibility: Audio editing via FFmpeg (Gyan.FFmpeg v8.1+)
# Supported operations:
#   trim        - Cut a clip by start time and duration/end
#   split       - Split a file at a timestamp into two files
#   concat      - Join multiple audio files into one
#   convert     - Re-encode to a different format / codec
#   volume      - Adjust volume by dB or multiplier
#   normalize   - Normalize loudness to EBU R128 target (-23 LUFS default)
#   fade        - Apply fade-in and/or fade-out
#   speed       - Change playback speed (pitch-corrected via atempo)
#   channels    - Convert stereo<->mono or extract a channel
#   metadata    - Read or write audio file tags (title, artist, album, etc.)
# ===============================================

# ── Helpers ─────────────────────────────────────────────────────────────────

function Get-SearchedPath {
    # Returns the current PATH entries as a readable list for error messages.
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

function Get-AudioOutputPath {
    param(
        [string]$inputPath,
        [string]$suffix,
        [string]$ext = ""  # leave empty to preserve source extension
    )
    $dir  = [System.IO.Path]::GetDirectoryName($inputPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    if (-not $ext) { $ext = [System.IO.Path]::GetExtension($inputPath) }
    if (-not $ext.StartsWith(".")) { $ext = ".$ext" }
    $ts   = (Get-Date).ToString("yyyyMMdd_HHmmss")
    return Join-Path $dir "$($base)_$($suffix)_$ts$ext"
}

function Escape-Arg {
    # Implements Windows command-line quoting rules (Raymond Chen / MSDN spec).
    # Wraps in double-quotes when the arg contains spaces, tabs, or double-quotes.
    # Internal double-quotes are escaped as \"; trailing backslashes before the
    # closing quote are doubled. Compatible with .NET Framework 4.x and .NET 5+.
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
    # Build a correctly escaped Arguments string — compatible with both
    # .NET Framework 4.x (used in PS Start-Job) and .NET 5+ (pwsh).
    $escapedArgs = ($ffArgs | ForEach-Object { Escape-Arg $_ }) -join " "

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $ffmpeg
    $psi.Arguments              = $escapedArgs
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true

    $proc   = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{ ExitCode = $proc.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

# ── Operation Functions ──────────────────────────────────────────────────────

function Op-Trim {
    param($ffmpeg, [string]$file_path, [string]$start, [string]$end_time, [string]$duration)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $start) { return "ERROR: 'start' is required for trim (e.g. '00:00:10' or '10')." }
    if (-not $end_time -and -not $duration) { return "ERROR: Provide either 'end_time' or 'duration'." }

    $out = Get-AudioOutputPath $file_path "trimmed"
    $ffArgs = @("-y", "-ss", $start)
    if ($duration) { $ffArgs += @("-t", $duration) }
    elseif ($end_time) { $ffArgs += @("-to", $end_time) }
    $ffArgs += @("-i", $file_path, "-c", "copy", $out)

    $r = Run-FFmpeg $ffmpeg $ffArgs
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg trim failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Trimmed audio saved to: $out::END_CONSOLE::OK: Trimmed audio saved to '$out'"
}

function Op-Split {
    param($ffmpeg, [string]$file_path, [string]$split_at)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $split_at) { return "ERROR: 'split_at' timestamp is required (e.g. '00:01:30')." }

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

    $msg = "✅ Split into:`n  Part 1: $out1`n  Part 2: $out2"
    return "CONSOLE::$msg::END_CONSOLE::OK: Split complete. Part 1: '$out1' | Part 2: '$out2'"
}

function Op-Concat {
    param($ffmpeg, [string]$file_paths, [string]$output_format)
    if (-not $file_paths) { return "ERROR: 'file_paths' is required — provide a comma-separated list of files." }

    $files = $file_paths -split "," | ForEach-Object { $_.Trim().Trim("'").Trim('"') }
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { return "ERROR: File not found: '$f'" }
    }

    # Build a temp concat list file.
    # IMPORTANT: Must be written WITHOUT a BOM — Set-Content -Encoding UTF8 in
    # Windows PowerShell 5.1 always prepends a BOM, which FFmpeg's concat
    # demuxer cannot parse (it sees the BOM as unknown keyword and fails).
    # [System.Text.UTF8Encoding]::new($false) gives UTF-8 without BOM on
    # both .NET Framework 4.x and .NET 5+.
    $listFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".txt")
    $lines = $files | ForEach-Object {
        # FFmpeg concat demuxer accepts forward slashes on Windows
        $fwd = $_.Replace('\', '/')
        "file '$fwd'"
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($listFile, $lines, $utf8NoBom)

    $ext = if ($output_format) { ".$($output_format.TrimStart('.'))" } else { [System.IO.Path]::GetExtension($files[0]) }
    $out = Get-AudioOutputPath $files[0] "concat" ($ext.TrimStart('.'))

    $r = Run-FFmpeg $ffmpeg @("-y", "-f", "concat", "-safe", "0", "-i", $listFile, "-c", "copy", $out)
    Remove-Item $listFile -Force -ErrorAction SilentlyContinue

    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg concat failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Concatenated $($files.Count) files -> $out::END_CONSOLE::OK: Concatenated $($files.Count) files to '$out'"
}

function Op-Convert {
    param($ffmpeg, [string]$file_path, [string]$output_format, [string]$bitrate, [string]$sample_rate)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $output_format) { return "ERROR: 'output_format' is required (e.g. 'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a')." }

    $out    = Get-AudioOutputPath $file_path "converted" $output_format
    $ffArgs = @("-y", "-i", $file_path)
    if ($bitrate)     { $ffArgs += @("-b:a", $bitrate) }
    if ($sample_rate) { $ffArgs += @("-ar", $sample_rate) }
    $ffArgs += $out

    $r = Run-FFmpeg $ffmpeg $ffArgs
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg convert failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Converted to $output_format -> $out::END_CONSOLE::OK: Converted to '$out'"
}

function Op-Volume {
    param($ffmpeg, [string]$file_path, [string]$adjustment)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $adjustment) { return "ERROR: 'adjustment' is required. Use dB (e.g. '+6dB', '-3dB') or a multiplier (e.g. '1.5', '0.5')." }

    # Normalise the adjustment string for FFmpeg's volume filter
    $volExpr = $adjustment.Trim()
    # If it already has 'dB' suffix, pass as-is; otherwise assume it's a linear multiplier
    if ($volExpr -notmatch "dB$") {
        # Treat as linear multiplier — FFmpeg accepts plain numbers
        # Just ensure it parses as a number
        if ($volExpr -notmatch "^[\d.]+$") {
            return "ERROR: 'adjustment' must be a dB value (e.g. '+6dB') or a positive multiplier (e.g. '1.5')."
        }
    }

    $out = Get-AudioOutputPath $file_path "vol"
    $r   = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", "volume=$volExpr", $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg volume adjustment failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Volume adjusted ($adjustment) -> $out::END_CONSOLE::OK: Volume adjusted to '$out'"
}

function Op-Normalize {
    param($ffmpeg, [string]$ffprobe, [string]$file_path, [string]$target_lufs)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $ffprobe) { return "ERROR: ffprobe not found in PATH. It is required for normalization." }

    $lufs = if ($target_lufs) { $target_lufs } else { "-23" }  # EBU R128 broadcast standard

    # Pass 1: measure current loudness
    $r1 = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", "loudnorm=I=$($lufs):TP=-1.5:LRA=11:print_format=json", "-f", "null", "NUL")
    # FFmpeg writes loudnorm JSON to stderr
    $jsonMatch = [regex]::Match($r1.Stderr, '(?s)\{[^{}]*"input_i"[^{}]*\}')
    if (-not $jsonMatch.Success) {
        return "ERROR: Could not parse loudnorm measurement from FFmpeg.`n$($r1.Stderr)"
    }

    try {
        $measured = $jsonMatch.Value | ConvertFrom-Json
    } catch {
        return "ERROR: Failed to parse loudnorm JSON.`n$($jsonMatch.Value)"
    }

    # Pass 2: apply linear normalization using measured values
    $filterStr = "loudnorm=I=$($lufs):TP=-1.5:LRA=11" +
                 ":measured_I=$($measured.input_i)" +
                 ":measured_TP=$($measured.input_tp)" +
                 ":measured_LRA=$($measured.input_lra)" +
                 ":measured_thresh=$($measured.input_thresh)" +
                 ":offset=$($measured.target_offset)" +
                 ":linear=true:print_format=summary"

    $out = Get-AudioOutputPath $file_path "normalized"
    $r2  = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", $filterStr, $out)
    if ($r2.ExitCode -ne 0) { return "ERROR: FFmpeg normalization (pass 2) failed.`n$($r2.Stderr)" }
    return "CONSOLE::✅ Normalized to $lufs LUFS -> $out::END_CONSOLE::OK: Normalized to $lufs LUFS, saved to '$out'"
}

function Op-Fade {
    param($ffmpeg, $ffprobe, [string]$file_path, [string]$fade_in, [string]$fade_out)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $fade_in -and -not $fade_out) { return "ERROR: Provide at least one of 'fade_in' or 'fade_out' (duration in seconds, e.g. '2')." }

    # ffprobe is required to measure file duration for accurate fade-out placement.
    # It is always present alongside ffmpeg in a standard FFmpeg install.
    $filters = @()

    if ($fade_in) { $filters += "afade=t=in:st=0:d=$fade_in" }

    if ($fade_out) {
        $probeResult = Run-FFmpeg $ffprobe @("-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", $file_path)
        if ($probeResult.ExitCode -ne 0 -or $probeResult.Stdout.Trim() -notmatch "^[\d.]+$") {
            return "ERROR: Could not determine file duration for fade-out (ffprobe failed).`n$($probeResult.Stderr)"
        }
        $duration  = [double]$probeResult.Stdout.Trim()
        $fadeStart = [Math]::Max(0, $duration - [double]$fade_out)
        $filters  += "afade=t=out:st=$($fadeStart.ToString([System.Globalization.CultureInfo]::InvariantCulture)):d=$fade_out"
    }

    $filterStr = $filters -join ","
    $out = Get-AudioOutputPath $file_path "faded"
    $r   = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", $filterStr, $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg fade failed.`n$($r.Stderr)" }

    $desc = @()
    if ($fade_in)  { $desc += "fade-in ${fade_in}s" }
    if ($fade_out) { $desc += "fade-out ${fade_out}s" }
    $descStr = $desc -join " + "
    return "CONSOLE::✅ Applied $descStr -> $out::END_CONSOLE::OK: Applied $descStr, saved to '$out'"
}

function Op-Speed {
    param($ffmpeg, [string]$file_path, [string]$speed)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }
    if (-not $speed) { return "ERROR: 'speed' is required (e.g. '1.5' for 1.5x, '0.75' for 75% speed)." }

    $speedVal = 0.0
    if (-not [double]::TryParse($speed, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$speedVal)) {
        return "ERROR: 'speed' must be a number (e.g. '1.5')."
    }
    if ($speedVal -lt 0.5 -or $speedVal -gt 100.0) {
        return "ERROR: 'speed' must be between 0.5 and 100. For very large ranges, multiple atempo filters are chained automatically."
    }

    # atempo only supports 0.5–100 per filter stage; chain if needed
    $filters = @()
    $remaining = $speedVal
    while ($remaining -gt 2.0) {
        $filters  += "atempo=2.0"
        $remaining = $remaining / 2.0
    }
    while ($remaining -lt 0.5) {
        $filters  += "atempo=0.5"
        $remaining = $remaining / 0.5
    }
    $remaining_str = $remaining.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $filters += "atempo=$remaining_str"

    $filterStr = $filters -join ","
    $out = Get-AudioOutputPath $file_path "speed$($speed)x"
    $r   = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", $filterStr, $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg speed change failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Speed changed to $($speed)x -> $out::END_CONSOLE::OK: Speed changed to $($speed)x, saved to '$out'"
}

function Op-Channels {
    param($ffmpeg, [string]$file_path, [string]$mode)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $validModes = @("mono", "stereo", "left", "right")
    $mode = $mode.Trim().ToLower()
    if ($mode -notin $validModes) {
        return "ERROR: 'mode' must be one of: mono, stereo, left, right. Got: '$mode'"
    }

    $filter = switch ($mode) {
        "mono"   { "pan=mono|c0=0.5*c0+0.5*c1" }
        "stereo" { "pan=stereo|c0=c0|c1=c0" }   # mono->stereo duplication
        "left"   { "pan=mono|c0=c0" }
        "right"  { "pan=mono|c0=c1" }
    }

    $out = Get-AudioOutputPath $file_path $mode
    $r   = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-af", $filter, $out)
    if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg channel operation failed.`n$($r.Stderr)" }
    return "CONSOLE::✅ Channel mode '$mode' applied -> $out::END_CONSOLE::OK: Channel mode '$mode' applied, saved to '$out'"
}

function Op-Metadata {
    param($ffmpeg, [string]$ffprobe, [string]$file_path, [string]$action, [string]$title, [string]$artist, [string]$album, [string]$year, [string]$genre, [string]$comment, [string]$track)
    if (-not (Test-Path $file_path)) { return "ERROR: File not found: '$file_path'" }

    $action = $action.Trim().ToLower()

    if ($action -eq "read") {
        if (-not $ffprobe) { return "ERROR: ffprobe not found in PATH. It is required to read metadata." }
        $r = Run-FFmpeg $ffprobe @("-v", "quiet", "-print_format", "json", "-show_format", $file_path)
        if ($r.ExitCode -ne 0) { return "ERROR: ffprobe failed.`n$($r.Stderr)" }
        try {
            $info = $r.Stdout | ConvertFrom-Json
            $tags = $info.format.tags
            if (-not $tags) { return "OK: No metadata tags found in '$file_path'." }
            $lines = @("Metadata for: $(Split-Path $file_path -Leaf)")
            $tags.PSObject.Properties | ForEach-Object { $lines += "  $($_.Name): $($_.Value)" }
            $result = $lines -join "`n"
            return "CONSOLE::$result::END_CONSOLE::$result"
        } catch {
            return "ERROR: Could not parse ffprobe output.`n$($r.Stdout)"
        }
    }

    if ($action -eq "write") {
        $metaArgs = @("-y", "-i", $file_path)
        $hasMeta  = $false
        foreach ($kv in @(
            @("title",   $title),
            @("artist",  $artist),
            @("album",   $album),
            @("date",    $year),
            @("genre",   $genre),
            @("comment", $comment),
            @("track",   $track)
        )) {
            if ($kv[1]) {
                $metaArgs += @("-metadata", "$($kv[0])=$($kv[1])")
                $hasMeta   = $true
            }
        }
        if (-not $hasMeta) { return "ERROR: Provide at least one metadata field to write (title, artist, album, year, genre, comment, track)." }
        $metaArgs += @("-c", "copy")
        $out       = Get-AudioOutputPath $file_path "tagged"
        $metaArgs += $out

        $r = Run-FFmpeg $ffmpeg $metaArgs
        if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg metadata write failed.`n$($r.Stderr)" }
        return "CONSOLE::✅ Metadata written -> $out::END_CONSOLE::OK: Metadata written, saved to '$out'"
    }

    if ($action -eq "strip") {
        $out = Get-AudioOutputPath $file_path "stripped"
        $r   = Run-FFmpeg $ffmpeg @("-y", "-i", $file_path, "-map_metadata", "-1", "-c", "copy", $out)
        if ($r.ExitCode -ne 0) { return "ERROR: FFmpeg metadata strip failed.`n$($r.Stderr)" }
        return "CONSOLE::✅ All metadata stripped -> $out::END_CONSOLE::OK: Metadata stripped, saved to '$out'"
    }

    return "ERROR: 'action' must be 'read', 'write', or 'strip'. Got: '$action'"
}

# ── Main Dispatch ─────────────────────────────────────────────────────────────

function Invoke-AudioEditTool {
    param(
        [string]$operation,
        [string]$file_path,
        # trim / split
        [string]$start,
        [string]$end_time,
        [string]$duration,
        [string]$split_at,
        # concat
        [string]$file_paths,
        # convert
        [string]$output_format,
        [string]$bitrate,
        [string]$sample_rate,
        # volume
        [string]$adjustment,
        # normalize
        [string]$target_lufs,
        # fade
        [string]$fade_in,
        [string]$fade_out,
        # speed
        [string]$speed,
        # channels
        [string]$mode,
        # metadata
        [string]$action,
        [string]$title,
        [string]$artist,
        [string]$album,
        [string]$year,
        [string]$genre,
        [string]$comment,
        [string]$track
    )

    $ffmpeg  = Find-FFmpeg
    $ffprobe = Find-FFprobe

    if (-not $ffmpeg) {
        $searchedPath = Get-SearchedPath
        return "ERROR: FFmpeg (ffmpeg.exe) was not found in your system PATH.`n`nTo fix this:`n  1. Install FFmpeg: winget install Gyan.FFmpeg`n  2. Restart your terminal so the new PATH takes effect.`n  3. Verify with: ffmpeg -version`n`nPATH directories searched:`n$searchedPath"
    }

    if (-not $ffprobe) {
        $searchedPath = Get-SearchedPath
        return "ERROR: FFprobe (ffprobe.exe) was not found in your system PATH. It is included with FFmpeg — if FFmpeg is installed, ffprobe.exe should be in the same folder.`n`nPATH directories searched:`n$searchedPath"
    }

    $operation = $operation.Trim().ToLower()

    switch ($operation) {
        "trim"      { return Op-Trim     $ffmpeg $file_path $start $end_time $duration }
        "split"     { return Op-Split    $ffmpeg $file_path $split_at }
        "concat"    { return Op-Concat   $ffmpeg $file_paths $output_format }
        "convert"   { return Op-Convert  $ffmpeg $file_path $output_format $bitrate $sample_rate }
        "volume"    { return Op-Volume   $ffmpeg $file_path $adjustment }
        "normalize" { return Op-Normalize $ffmpeg $ffprobe $file_path $target_lufs }
        "fade"      { return Op-Fade     $ffmpeg $ffprobe $file_path $fade_in $fade_out }
        "speed"     { return Op-Speed    $ffmpeg $file_path $speed }
        "channels"  { return Op-Channels $ffmpeg $file_path $mode }
        "metadata"  { return Op-Metadata $ffmpeg $ffprobe $file_path $action $title $artist $album $year $genre $comment $track }
        default {
            return "ERROR: Unknown operation '$operation'. Valid operations: trim, split, concat, convert, volume, normalize, fade, speed, channels, metadata."
        }
    }
}

# ── Self-registration block ───────────────────────────────────────────────────

$ToolMeta = @{
    Name             = "audioedit"
    RendersToConsole = $false
    Category         = @("Digital Media Production")

    Behavior = @"
Use this tool to perform audio editing operations via FFmpeg. Always confirm the file path exists before invoking.
Choose 'operation' from the list below and supply only the parameters relevant to that operation.

OPERATIONS:
  trim        - Cut a clip. Requires: file_path, start. Provide end_time OR duration.
  split       - Split into two files at a timestamp. Requires: file_path, split_at.
  concat      - Join multiple files. Requires: file_paths (comma-separated list). Optional: output_format.
  convert     - Re-encode to a new format. Requires: file_path, output_format (e.g. 'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'). Optional: bitrate (e.g. '192k'), sample_rate (e.g. '44100').
  volume      - Adjust volume. Requires: file_path, adjustment (e.g. '+6dB', '-3dB', or '1.5' multiplier).
  normalize   - EBU R128 loudness normalization (two-pass). Requires: file_path. Optional: target_lufs (default '-23').
  fade        - Add fade-in and/or fade-out. Requires: file_path. Optional: fade_in (seconds), fade_out (seconds).
  speed       - Change speed (pitch-corrected). Requires: file_path, speed (e.g. '1.5' = 50% faster, '0.75' = 75% speed). Range: 0.5–100.
  channels    - Convert channel layout. Requires: file_path, mode (one of: mono, stereo, left, right).
  metadata    - Read/write/strip tags. Requires: file_path, action (read | write | strip). For write: supply any of title, artist, album, year, genre, comment, track.

OUTPUT: All operations produce a new auto-named file in the same directory as the input. The original is never modified.
FORMATS SUPPORTED: mp3, wav, flac, aac, ogg, m4a, opus, wma, and any format FFmpeg supports.
"@

    Description = "Audio editor using FFmpeg: trim, split, concat, convert, volume, normalize, fade, speed change, channel conversion, and metadata read/write."

    Parameters = @{
        operation     = "string - Required. One of: trim, split, concat, convert, volume, normalize, fade, speed, channels, metadata."
        file_path     = "string - Path to the input audio file (not needed for 'concat', which uses file_paths instead)."
        # trim
        start         = "string - [trim] Start time (e.g. '00:00:10' or '10')."
        end_time      = "string - [trim] End time (e.g. '00:01:30'). Use instead of duration."
        duration      = "string - [trim] Duration to keep (e.g. '30' for 30s). Use instead of end_time."
        # split
        split_at      = "string - [split] Timestamp where the file is split into two parts."
        # concat
        file_paths    = "string - [concat] Comma-separated list of file paths to join in order."
        # convert
        output_format = "string - [convert/concat] Target file extension/format (e.g. 'mp3', 'wav', 'flac')."
        bitrate       = "string - [convert] Audio bitrate (e.g. '192k', '320k')."
        sample_rate   = "string - [convert] Sample rate in Hz (e.g. '44100', '48000')."
        # volume
        adjustment    = "string - [volume] dB adjustment (e.g. '+6dB', '-3dB') or linear multiplier (e.g. '1.5')."
        # normalize
        target_lufs   = "string - [normalize] Target loudness in LUFS (e.g. '-23'). Default is '-23' (EBU R128)."
        # fade
        fade_in       = "string - [fade] Fade-in duration in seconds (e.g. '2')."
        fade_out      = "string - [fade] Fade-out duration in seconds (e.g. '3')."
        # speed
        speed         = "string - [speed] Playback speed multiplier (e.g. '1.5' = faster, '0.75' = slower). Range 0.5-100."
        # channels
        mode          = "string - [channels] Channel layout: 'mono' (mix to mono), 'stereo' (duplicate mono), 'left' (extract left), 'right' (extract right)."
        # metadata
        action        = "string - [metadata] 'read' to display tags, 'write' to set tags, 'strip' to remove all tags."
        title         = "string - [metadata write] Track title tag."
        artist        = "string - [metadata write] Artist tag."
        album         = "string - [metadata write] Album tag."
        year          = "string - [metadata write] Year tag."
        genre         = "string - [metadata write] Genre tag."
        comment       = "string - [metadata write] Comment tag."
        track         = "string - [metadata write] Track number tag."
    }

    Example = '<tool_call>{ "name": "audioedit", "parameters": { "operation": "trim", "file_path": "C:\\Music\\song.mp3", "start": "00:00:30", "duration": "60" } }</tool_call>'

    FormatLabel = {
        param($p)
        $icon = switch ($p.operation) {
            "trim"      { "✂️" }
            "split"     { "🔀" }
            "concat"    { "🔗" }
            "convert"   { "🔄" }
            "volume"    { "🔊" }
            "normalize" { "📊" }
            "fade"      { "🌅" }
            "speed"     { "⚡" }
            "channels"  { "🎚️" }
            "metadata"  { "🏷️" }
            default     { "🎵" }
        }
        $target = if ($p.file_path) { Split-Path $p.file_path -Leaf } elseif ($p.file_paths) { "multiple files" } else { "?" }
        "$icon audioedit [$($p.operation)] -> $target"
    }

    Execute = { param($params) Invoke-AudioEditTool @params }
}