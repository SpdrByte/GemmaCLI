# ===============================================
# GemmaCLI Tool - render_text.ps1 v1.1.0
# Responsibility: Renders high-quality text images using System.Drawing.
# Supports custom dimensions, fonts, colors, and precise alignment.
# ===============================================

function Invoke-RenderTextTool {
    param(
        [Parameter(Mandatory=$true)]
        [string]$text,
        [int]$width = 1920,
        [int]$height = 1080,
        [string]$font_name = "Arial",
        [float]$font_size = 72,
        [string]$font_color = "White",
        [string]$bg_color = "Transparent",
        [string]$alignment = "center",      # left, center, right
        [string]$line_alignment = "middle", # top, middle, bottom
        [string]$output_path,
        [int]$padding = 20
    )

    # --- Helper: Parse Color ---
    function Get-DrawingColor {
        param([string]$colorStr)
        if ([string]::IsNullOrWhiteSpace($colorStr)) { return [System.Drawing.Color]::Transparent }
        
        # 1. Check for Hex (#RRGGBB or #AARRGGBB)
        if ($colorStr -match "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$") {
            return [System.Drawing.ColorTranslator]::FromHtml($colorStr)
        }
        
        # 2. Check for RGB (R,G,B)
        if ($colorStr -match "^(\d{1,3}),\s*(\d{1,3}),\s*(\d{1,3})$") {
            return [System.Drawing.Color]::FromArgb($matches[1], $matches[2], $matches[3])
        }

        # 3. Try named color
        try {
            return [System.Drawing.Color]::FromName($colorStr)
        } catch {
            return [System.Drawing.Color]::White # Fallback
        }
    }

    try {
        Add-Type -AssemblyName System.Drawing

        # Prepare Bitmap and Graphics
        $bmp = [System.Drawing.Bitmap]::new($width, $height)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)

        # High Quality Settings
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        # Background
        $drawBgColor = Get-DrawingColor $bg_color
        $g.Clear($drawBgColor)

        # Font and Brush
        $font = [System.Drawing.Font]::new($font_name, $font_size)
        $drawFontColor = Get-DrawingColor $font_color
        $brush = [System.Drawing.SolidBrush]::new($drawFontColor)

        # Alignment
        $format = [System.Drawing.StringFormat]::new()
        $format.Alignment = switch ($alignment.ToLower()) {
            "left"   { [System.Drawing.StringAlignment]::Near }
            "right"  { [System.Drawing.StringAlignment]::Far }
            default  { [System.Drawing.StringAlignment]::Center }
        }
        $format.LineAlignment = switch ($line_alignment.ToLower()) {
            "top"    { [System.Drawing.StringAlignment]::Near }
            "bottom" { [System.Drawing.StringAlignment]::Far }
            default  { [System.Drawing.StringAlignment]::Center }
        }

        # Draw Area (Rect minus padding)
        $rect = [System.Drawing.RectangleF]::new($padding, $padding, $width - ($padding * 2), $height - ($padding * 2))

        # Render
        # System.Drawing handles \n automatically
        $g.DrawString($text, $font, $brush, $rect, $format)

        # Finalize Path
        if ([string]::IsNullOrWhiteSpace($output_path)) {
            $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $output_path = Join-Path $pwd "rendered_text_$ts.png"
        }

        $bmp.Save($output_path, [System.Drawing.Imaging.ImageFormat]::Png)

        # Cleanup
        $brush.Dispose()
        $font.Dispose()
        $g.Dispose()
        $bmp.Dispose()

        $successMsg = "Successfully rendered text to: $output_path"
        return "CONSOLE::✅ $successMsg::END_CONSOLE::$successMsg"

    } catch {
        return "ERROR: Failed to render text. $($_.Exception.Message)"
    }
}

# --- Self-registration block ---
$ToolMeta = @{
    Name        = "render_text"
    Icon        = "📝"
    RendersToConsole = $false
    Category    = @("Digital Media Production")
    Version     = "1.0.0"
    
    Relationships = @{
        "video_editor" = "Use 'render_text' to create transparent PNG title cards or overlays, then use 'video_editor' (operation='overlay_image') to place them onto your video."
    }

    Behavior    = "Generates a PNG image containing rendered text. You can customize the font, size, color, background (including transparency), and alignment. Use '\n' for newlines."
    
    Description = "Renders text to a PNG image with custom fonts, colors, and alignment."
    
    Parameters  = @{
        text           = "string - REQUIRED. The text to render. Use \n for newlines."
        width          = "int - Target width in pixels. Default 1920."
        height         = "int - Target height in pixels. Default 1080."
        font_name      = "string - Name of the font family (e.g. 'Arial', 'Consolas'). Default 'Arial'."
        font_size      = "float - Size of the font. Default 72."
        font_color     = "string - Color of the text. Supports Names (White), Hex (#RRGGBB), or RGB (255,255,255). Default 'White'."
        bg_color       = "string - Background color. Default 'Transparent'. Supports Hex/RGB."
        alignment      = "string - Horizontal alignment: 'left', 'center', 'right'. Default 'center'."
        line_alignment = "string - Vertical alignment: 'top', 'middle', 'bottom'. Default 'middle'."
        output_path    = "string - Optional. Destination for the PNG file."
        padding        = "int - Margin around the text in pixels. Default 20."
    }
    
    Example     = '<tool_call>{ "name": "render_text", "parameters": { "text": "Hello\nWorld", "font_color": "Cyan", "bg_color": "Black", "alignment": "center" } }</tool_call>'
    
    FormatLabel = { param($p) "$(if($p.text.length -gt 20){$p.text.substring(0,20)+'...'}else{$p.text})" }
    
    Execute     = { param($params) Invoke-RenderTextTool @params }
}
