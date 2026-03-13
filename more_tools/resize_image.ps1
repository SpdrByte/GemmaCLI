# ===============================================
# GemmaCLI Tool - resize_image.ps1 v0.1.1
# Responsibility: Resizes an image to specific dimensions (stretching).
# ===============================================

function Invoke-ResizeImageTool {
    param(
        [string]$file_path,
        [int]$width,
        [int]$height
    )

    if (-not (Test-Path $file_path)) {
        return "ERROR: File not found at '$file_path'"
    }

    $ext = [System.IO.Path]::GetExtension($file_path).ToLower()
    $supported = @(".png", ".jpg", ".jpeg", ".gif")
    if ($ext -notin $supported) {
        return "ERROR: Unsupported file format '$ext'. This tool only supports PNG, JPG, and GIF. (Note: WEBP and HEIC are not supported by this native tool)."
    }

    try {
        Add-Type -AssemblyName System.Drawing
        
        $srcImage = [System.Drawing.Image]::FromFile((Resolve-Path $file_path))
        
        # --- Perform Resize (Stretch) ---
        $bmp = [System.Drawing.Bitmap]::new($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        
        # High quality rendering settings
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        # Draw source image into the full destination rectangle (stretching)
        $destRect = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
        $graphics.DrawImage($srcImage, $destRect)

        # Generate output path
        $ext = [System.IO.Path]::GetExtension($file_path)
        if (-not $ext) { $ext = ".png" }
        $dir = [System.IO.Path]::GetDirectoryName($file_path)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($file_path)
        $outputPath = Join-Path $dir "$($base)_resized_$((Get-Date).Ticks)$ext"

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

        $msg = "Image successfully resized to $($width)x$($height) (Stretched).`nSaved to: $outputPath"
        return "CONSOLE::$msg::END_CONSOLE::$msg"

    } catch {
        return "ERROR: Failed to resize image. $($_.Exception.Message)"
    }
}

# --- Self-registration block ---
$ToolMeta = @{
    Name        = "resize_image"
    Behavior    = "Use this tool to resize an image to specific dimensions. Supported formats: PNG, JPG, JPEG, and GIF. Does NOT support WEBP or HEIC. Note that this tool will stretch the image to fit the requested width and height exactly."
    Description = "Resizes/Stretches an image (PNG, JPG, GIF). Specify width and height."
    Parameters  = @{
        file_path = "string - Full path to the image file."
        width     = "int - Target width in pixels."
        height    = "int - Target height in pixels."
    }
    Example     = "<tool_call>{ ""name"": ""resize_image"", ""parameters"": { ""file_path"": ""C:\temp\image.png"", ""width"": 1920, ""height"": 1080 } }</tool_call>"
    FormatLabel = { param($p) "📐 Resize -> $(Split-Path $p.file_path -Leaf) to $($p.width)x$($p.height)" }
    Execute     = { param($params) Invoke-ResizeImageTool @params }
}
