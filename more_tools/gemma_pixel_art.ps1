# ===============================================
# GemmaCLI Tool - gemma_pixel_art.ps1 v0.2.0
# Responsibility: Renders a 20x16 pixel art canvas using sparse coordinate updates.
# ===============================================

function Invoke-GemmaPixelArtTool {
    param(
        [string[]]$updates,
        [string]$title = "Gemma's Masterpiece"
    )

    # --- Initialize 16x16 Buffer ----------------------------------------------
    # Default: Black, Solid (219)
    $width = 16
    $height = 16
    $buffer = New-Object 'object[,]' $height, $width
    for ($r = 0; $r -lt $height; $r++) {
        for ($c = 0; $c -lt $width; $c++) {
            $buffer[$r, $c] = @{ Color = "Black"; Char = [char]0x2588 }
        }
    }

    # --- Character Mapping ----------------------------------------------------
    $charMap = @{
        "solid"  = [char]0x2588 # █
        "dense"  = [char]0x2593 # ▓
        "medium" = [char]0x2592 # ▒
        "light"  = [char]0x2591 # ░
    }

    # --- Apply Sparse Updates -------------------------------------------------
    # Format: "X,Y,Color,Shade" (1-indexed for the AI; X=Col, Y=Row)
    foreach ($u in $updates) {
        if ($u -match '(\d+),(\d+),(\w+),(\w+)') {
            $c = [int]$matches[1] - 1
            $r = [int]$matches[2] - 1
            $color = $matches[3]
            $shade = $matches[4].ToLower()

            if ($r -ge 0 -and $r -lt $height -and $c -ge 0 -and $c -lt $width) {
                $buffer[$r, $c].Color = $color
                if ($charMap.ContainsKey($shade)) {
                    $buffer[$r, $c].Char = $charMap[$shade]
                }
            }
        }
    }

    # --- Render to Console ----------------------------------------------------
    Write-Host "`n  --- $title ---" -ForegroundColor Cyan
    for ($r = 0; $r -lt $height; $r++) {
        Write-Host "  " -NoNewline
        for ($c = 0; $c -lt $width; $c++) {
            $pixel = $buffer[$r, $c]
            # Draw double chars because console cells are tall/narrow
            Write-Host "$($pixel.Char)$($pixel.Char)" -ForegroundColor $pixel.Color -NoNewline
        }
        Write-Host ""
    }
    Write-Host "  " + ("--" * $width) -ForegroundColor Gray

    return "CONSOLE::Art rendered to terminal.::END_CONSOLE::OK: Your artwork '$title' has been displayed to the user."
}

$ToolMeta = @{
    Name             = "gemma_pixel_art"
    Icon             = "👾"
    RendersToConsole = $true
    Category         = @("Creative/Media")
    Description      = "Draws a 16x16 pixel art image (renders as 32 characters wide, 16 rows high) in the terminal using a sparse coordinate system."
    Parameters       = @{
        updates = "array of strings - Each string is 'X,Y,Color,Shade' (e.g., '1,1,Red,Solid'). Coordinates: X (Column) is 1-16, Y (Row) is 1-16. (1,1) is the Top-Left corner."
        title   = "string - A title for your artwork."
    }
    Example          = "<tool_call>{ `"name`": `"gemma_pixel_art`", `"parameters`": { `"updates`": [`"8,8,Red,Solid`", `"9,8,Red,Solid`", `"8,9,White,Medium``], `"title`": `"Red Eye`" } }</tool_call>"
    FormatLabel      = { param($p) "$($p.title)" }
    Execute          = { param($params) Invoke-GemmaPixelArtTool @params }
    Behavior         = "The logical canvas is 16x16. Each logical pixel is rendered as a pair of characters (Width x 2). (1,1) is Top-Left, (16,1) is Top-Right, (1,16) is Bottom-Left, (16,16) is Bottom-Right. Assume the canvas is initially all Black Solid blocks. Only provide 'updates' for pixels that should be a different color or shade. Use 'solid', 'dense', 'medium', or 'light' for shading. Colors: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White."
}