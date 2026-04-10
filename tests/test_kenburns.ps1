# FFmpeg Ken Burns Diagnostic Test
# This script tests the zoompan logic with extreme values to verify movement.

$ffmpeg = Get-Command "ffmpeg" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $ffmpeg) { Write-Error "FFmpeg not found."; exit }

$testImage = "assets/Dual.png" # Using an existing project asset
if (-not (Test-Path $testImage)) { Write-Error "Test image missing."; exit }

$duration = 3
$fps = 25
$zoom_speed = 0.01 # Extreme speed for visibility
$pan = "right"
$resolution = "1280x720"
$out = "kenburns_test_diagnostic.mp4"

# Math from Op-KenBurns
$xExpr = "iw-(iw/zoom)"
$yExpr = "ih/2-(ih/zoom/2)"

# Pipeline with 2x internal scaling for room to move
$vf = "scale=2560:1440:force_original_aspect_ratio=decrease,pad=2560:1440:(ow-iw)/2:(oh-ih)/2,setsar=1," +
      "zoompan=z='zoom+${zoom_speed}':x='${xExpr}':y='${yExpr}':d=1:s=${resolution}:fps=${fps}," +
      "format=yuv420p"

Write-Host "Running diagnostic render (Extreme Zoom + Pan Right)..." -ForegroundColor Cyan

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $ffmpeg
$psi.Arguments = "-y -loop 1 -t $duration -i ""$testImage"" -vf ""$vf"" -c:v libx264 -preset ultrafast ""$out"""
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($proc.ExitCode -eq 0) {
    Write-Host "✅ Diagnostic render complete: $out" -ForegroundColor Green
    # Check file size to ensure it's not empty
    $size = (Get-Item $out).Length
    Write-Host "File size: $size bytes"
} else {
    Write-Host "❌ Diagnostic render failed!" -ForegroundColor Red
    Write-Host $stderr
}
