# ===============================================
# GemmaCLI Tool - cowsay.ps1 v0.1.0
# Responsibility: Wraps text in an ASCII cow speech bubble.
# ===============================================

function Invoke-CowsayTool {
    param(
        [string]$text,
        [int]$max_width = 40
    )

    if ([string]::IsNullOrWhiteSpace($text)) {
        return "ERROR: text cannot be empty."
    }

    # Split text into lines within the max width
    $lines = @()
    $words = $text -split "\s+"
    $currentLine = ""

    foreach ($word in $words) {
        if ($currentLine.Length + $word.Length + 1 -gt $max_width) {
            $lines += $currentLine.Trim()
            $currentLine = $word
        } else {
            $currentLine += " $word"
        }
    }
    $lines += $currentLine.Trim()

    # Determine bubble width
    $bubbleWidth = 0
    foreach ($line in $lines) {
        if ($line.Length -gt $bubbleWidth) { $bubbleWidth = $line.Length }
    }

    # Construct bubble
    $output = " " + ("_" * ($bubbleWidth + 2)) + "`n"
    if ($lines.Count -eq 1) {
        $output += "< $($lines[0]) >`n"
    } else {
        $output += "/ $($lines[0].PadRight($bubbleWidth)) \`n"
        for ($i = 1; $i -lt $lines.Count - 1; $i++) {
            $output += "| $($lines[$i].PadRight($bubbleWidth)) |`n"
        }
        $output += "\ $($lines[-1].PadRight($bubbleWidth)) /`n"
    }
    $output += " " + ("-" * ($bubbleWidth + 2)) + "`n"

    # Add Cow
    $cow = @"
        \   ^__^
         \  (oo)\_______
            (__)\       )\/
                ||----w |
                ||     ||
"@
    $output += $cow

    return "<code_block>`n$output`n</code_block>"
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "cowsay"
    Behavior    = "Use this tool for entertainment or when explicitly asked. Wraps text in an ASCII cow."
    Description = "Wraps any text in an ASCII cow speech bubble. Classic, unnecessary, and fun."
    Parameters  = @{
        text      = "string - the message the cow should say"
        max_width = "int - maximum width of the speech bubble (default 40)"
    }
    Example     = "<tool_call>{ ""name"": ""cowsay"", ""parameters"": { ""text"": ""Moo! Have a great day!"" } }</tool_call>"
    FormatLabel = { param($params) "🐮 Cowsay -> $($params.text.Substring(0, [math]::Min(20, $params.text.Length)))" }
    Execute     = { param($params) Invoke-CowsayTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'cowsay': This tool is entirely cosmetic and should be used if the user asks for a joke, wants something "fun", mentions being bored, or specifically requests a cowsay message.
        - Important: The tool returns the ASCII art wrapped in `<code_block>` tags. You MUST include the literal content of the TOOL RESULT in your final response so the user can see the cow. Do not just summarize it.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Make a cow say your message in ASCII art.
        - Basic use: Provide the `text` you want the cow to speak.
        - Note: You must show the cow from the tool result to the user.
"@
}
