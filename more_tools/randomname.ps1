# ===============================================
# GemmaCLI Tool - randomname.ps1 v0.2
# Responsibility: Generates a random name with specified criteria.
# ===============================================

function Invoke-RandomNameTool {
    param(
        [string]$sex,
        [string]$style
    )

    $maleModernNames   = @("Ethan", "Noah", "Liam", "Mason", "Jacob", "Jared", "Joe",
                           "Ryan", "Tyler", "Brandon", "Austin", "Dylan", "Logan", "Hunter")
    $femaleModernNames = @("Olivia", "Emma", "Ava", "Sophia", "Isabella",
                           "Mia", "Charlotte", "Amelia", "Harper", "Ella", "Chloe", "Lily")

    $maleSciFiNames    = @("Jax", "Kael", "Zane", "Rylo", "Corvus",
                           "Oryn", "Drex", "Voss", "Talon", "Crix", "Nexus", "Arlo")
    $femaleSciFiNames  = @("Lyra", "Nova", "Astra", "Vega", "Seraphina",
                           "Zara", "Nyx", "Cleo", "Ionic", "Phaedra", "Solara", "Rhea")

    $maleFantasyNames  = @("Aric", "Torin", "Lysander", "Kieran", "Eamon",
                           "Aldric", "Theron", "Caelan", "Dorian", "Faelen", "Gideon", "Hadrian")
    $femaleFantasyNames= @("Elara", "Seraphine", "Isolde", "Rowan", "Aeliana",
                           "Sylara", "Brynn", "Calista", "Dawneth", "Fiora", "Gwendolyn", "Thessaly")

    # Normalize inputs
    $sexNorm   = $sex.Trim()
    $styleNorm = $style.Trim().ToLower()

    switch ($styleNorm) {
        "modern"  { $names = if ($sexNorm -eq "Female") { $femaleModernNames  } else { $maleModernNames  } }
        "sci-fi"  { $names = if ($sexNorm -eq "Female") { $femaleSciFiNames   } else { $maleSciFiNames   } }
        "fantasy" { $names = if ($sexNorm -eq "Female") { $femaleFantasyNames } else { $maleFantasyNames } }
        default   { return "ERROR: Invalid style '$style'. Choose from 'modern', 'sci-fi', or 'fantasy'." }
    }

    if ($names) {
        $randomName = Get-Random -InputObject $names
        return "Random name generated: $randomName  (Sex: $sexNorm, Style: $styleNorm)"
    } else {
        return "ERROR: Could not generate name."
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "randomname"
    Behavior    = "Generates a random name based on specified sex and style. Use when the user asks for a random name, a character name, or a name suggestion."
    Description = "Returns a random name given a sex (Male/Female) and a style (modern, sci-fi, fantasy)."
    Parameters  = @{
        sex   = "string - 'Male' or 'Female'"
        style = "string - 'modern', 'sci-fi', or 'fantasy'"
    }
    Example     = "<tool_call>{ ""name"": ""randomname"", ""parameters"": { ""sex"": ""Male"", ""style"": ""modern"" } }</tool_call>"
    FormatLabel = { param($params) "🎲 RandomName -> Sex: $($params.sex), Style: $($params.style)" }
    Execute     = {
        param($params)
        Invoke-RandomNameTool -sex $params.sex -style $params.style
    }
    ToolUseGuidanceMajor = @"
        - When to use 'randomname': Use this tool when the user wants a random or suggested name for a character, person, or entity, or when creating a name for a story, rpg adventure, or interactive game being played with user requiring a name.
        - Required parameters for 'randomname':
          - 'sex': Must be 'Male' or 'Female'. Infer from context if not stated explicitly.
          - 'style': Must be one of 'modern', 'sci-fi', or 'fantasy'. Infer from context (e.g. a game setting, story genre) if not stated.
        - If neither sex nor style is clear from context, ask the user before calling the tool.
"@
    ToolUseGuidanceMinor = @"
        - Purpose: Generate a random name for a character or person.
        - Provide 'sex' (Male/Female) and 'style' (modern, sci-fi, fantasy).
        - Infer missing parameters from context when possible.
"@
}