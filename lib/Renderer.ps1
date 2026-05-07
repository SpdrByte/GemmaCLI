# lib/Renderer.ps1 v0.1.0
# Responsibility: The "Text Processing Pipeline". 
# Handles syntax highlighting, markdown parsing, and platform-specific text adjustments.

function Format-Markdown {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $esc = [char]27
    $reset = "$esc[0m"
    
    # 1. Bold: **text** -> ANSI Bold
    $bold = "$esc[1m"
    $Text = [regex]::Replace($Text, '(?<!\S)\*\*([^*\s][^*]*?)\*\*(?!\S)', {
        param($m)
        return "${bold}$($m.Groups[1].Value)${reset}"
    })

    # 2. Italic: *text* -> ANSI Italic
    $italic = "$esc[3m"
    $Text = [regex]::Replace($Text, '(?<!\S)\*([^*\s][^*]*?)\*(?!\S)', {
        param($m)
        return "${italic}$($m.Groups[1].Value)${reset}"
    })

    # 3. Inline Code: `text` -> ANSI Reverse/Inverted
    $code = "$esc[7m"
    $Text = [regex]::Replace($Text, '`(.*?)`', {
        param($m)
        return "${code} $($m.Groups[1].Value) ${reset}"
    })

    # 4. Headings: # Header -> Bold Cyan
    $Text = [regex]::Replace($Text, '(?m)^#+\s+(.*)$', {
        param($m)
        return "$esc[1;36m$($m.Groups[1].Value)${reset}"
    })

    # 5. Bullet points: * or - at start of line -> Bullet character
    $Text = [regex]::Replace($Text, '(?m)^[\s]*[\*\-]\s+', "  $([char]0x2022) ")

    # 6. Numbered lists: 1. -> ANSI Blue index
    $blue = "$esc[34m"
    $Text = [regex]::Replace($Text, '(?m)^[\s]*(\d+)\.\s+', {
        param($m)
        return "  ${blue}$($m.Groups[1].Value).${reset} "
    })

    return $Text
}

function Convert-ToHyperlink {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    
    $esc = [char]27
    $pathRegex = '\b([A-Za-z]:\\[^ "''><\n\t\r\)\(]+)\b'
    $urlRegex  = '\b(https?://[^ "''><\n\t\r\)\(]+)\b'

    $Text = [regex]::Replace($Text, $urlRegex, {
        param($m)
        $url = $m.Groups[1].Value
        return "$($esc)]8;;$($url)$($esc)\$($url)$($esc)]8;;$($esc)\"
    })

    $Text = [regex]::Replace($Text, $pathRegex, {
        param($m)
        $path = $m.Groups[1].Value
        $uri  = "file:///" + $path.Replace('\', '/')
        return "$($esc)]8;;$($uri)$($esc)\$($path)$($esc)]8;;$($esc)\"
    })

    return $Text
}

function Get-VisualWidth {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    
    # STRIP ANSI ESCAPE SEQUENCES for width calculation
    # Supports: \x1b[...m (colors), \x1b]8;;...\x1b\ (OSC8 links)
    $clean = $Text -replace "\x1B\[[0-9;]*[mK]", ""
    $clean = $clean -replace "\x1B]8;;.*?\x1B\\", "" 
    $clean = $clean -replace "\x1B]8;;.*?\x07", ""   # Alternative OSC8 terminator
    
    $si = [System.Globalization.StringInfo]::new($clean)
    $len = $si.LengthInTextElements
    
    $width = 0
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($clean)
    while ($enumerator.MoveNext()) {
        $el = $enumerator.GetTextElement()
        if ([char]::IsHighSurrogate($el[0]) -or $el.Length -gt 1) {
            $width += 2
        } else {
            $width += 1
        }
    }
    return $width
}

function Format-TextForSpeech {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    
    # Strip thoughts, channels, and code blocks
    $clean = $text -replace '(?s)<thought>.*?</thought>', ''
    $clean = $clean -replace '(?s)<\|channel>thought.*?<channel\|>', ''
    $clean = $clean -replace '(?s)<code_block>.*?</code_block>', ' [Code block omitted] '
    $clean = $clean -replace '(?s)```.*?```', ' [Code block omitted] '
    
    # Strip markdown markers
    $clean = $clean -replace '\*\*', ''
    $clean = $clean -replace '\*', ''
    
    return $clean.Trim()
}
