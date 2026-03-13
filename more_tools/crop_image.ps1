# ===============================================
# GemmaCLI Tool - crop_image.ps1 v0.1.0
# Responsibility: Crops an image using simple positioning labels.
# ===============================================

function Invoke-CropImageTool {
    param(
        [string]$file_path,
        [int]$width,
        [int]$height,
        [string]$vertical_position = "middle",   # top, middle, bottom
        [string]$horizontal_position = "center"  # left, center, right
    )

    if (-not (Test-Path $file_path)) {
        return "ERROR: File not found at '$file_path'"
    }

    try {
        Add-Type -AssemblyName System.Drawing
        
        $srcImage = [System.Drawing.Image]::FromFile((Resolve-Path $file_path))
        $srcW = $srcImage.Width
        $srcH = $srcImage.Height

        # Clamp requested size to source bounds
        if ($width -gt $srcW)  { $width  = $srcW }
        if ($height -gt $srcH) { $height = $srcH }

        # --- Calculate X (Horizontal) ---
        $x = switch ($horizontal_position.ToLower()) {
            "left"   { 0 }
            "right"  { $srcW - $width }
            "center" { [int](($srcW - $width) / 2) }
            default  { [int](($srcW - $width) / 2) }
        }

        # --- Calculate Y (Vertical) ---
        $y = switch ($vertical_position.ToLower()) {
            "top"    { 0 }
            "bottom" { $srcH - $height }
            "middle" { [int](($srcH - $height) / 2) }
            default  { [int](($srcH - $height) / 2) }
        }

        # Ensure coordinates are not negative
        if ($x -lt 0) { $x = 0 }
        if ($y -lt 0) { $y = 0 }

        # --- Perform Crop ---
        $rect = [System.Drawing.Rectangle]::new($x, $y, $width, $height)
        $bmp  = [System.Drawing.Bitmap]::new($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        
        # High quality rendering settings
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $graphics.DrawImage($srcImage, 0, 0, $rect, [System.Drawing.GraphicsUnit]::Pixel)

        # Generate output path
        $ext = [System.IO.Path]::GetExtension($file_path)
        if (-not $ext) { $ext = ".png" }
        $dir = [System.IO.Path]::GetDirectoryName($file_path)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($file_path)
        $outputPath = Join-Path $dir "$($base)_cropped_$((Get-Date).Ticks)$ext"

        # Save result (matching extension format)
        $format = switch ($ext.ToLower()) {
            ".jpg"  { [System.Drawing.Imaging.ImageFormat]::Jpeg }
            ".jpeg" { [System.Drawing.Imaging.ImageFormat]::Jpeg }
            ".gif"  { [System.Drawing.Imaging.ImageFormat]::Gif }
            default { [System.Drawing.Imaging.ImageFormat]::Png }
        }

        $bmp.Save($outputPath, $format)

        # Cleanup
        $graphics.Dispose()
        $bmp.Dispose()
        $srcImage.Dispose()

        return "Image successfully cropped to $($width)x$($height) starting from $vertical_position-$horizontal_position.`nSaved to: $outputPath"

    } catch {
        return "ERROR: Failed to crop image. $($_.Exception.Message)"
    }
}

# --- Self-registration block ---
$ToolMeta = @{
    Name        = "crop_image"
    Behavior    = "Use this tool to crop an existing image to a specific size. You can position the crop box using simple vertical and horizontal labels."
    Description = "Crops an image. Specify width, height, and positions (top/middle/bottom and left/center/right)."
    Parameters  = @{
        file_path           = "string - Full path to the image file."
        width               = "int - Target width in pixels."
        height              = "int - Target height in pixels."
        vertical_position   = "string - 'top', 'middle', or 'bottom'. Default is 'middle'."
        horizontal_position = "string - 'left', 'center', or 'right'. Default is 'center'."
    }
    Example     = "<tool_call>{ ""name"": ""crop_image"", ""parameters"": { ""file_path"": ""C:\temp\image.png"", ""width"": 500, ""height"": 500, ""vertical_position"": ""top"", ""horizontal_position"": ""left"" } }</tool_call>"
    FormatLabel = { param($p) "✂️ Crop -> $(Split-Path $p.file_path -Leaf) to $($p.width)x$($p.height)" }
    Execute     = { param($params) Invoke-CropImageTool @params }
}
