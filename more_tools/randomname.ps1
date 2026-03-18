# ===============================================
# GemmaCLI Tool - randomname.ps1 v0.3.0
# Responsibility: Generates a random name with specified criteria.
# ===============================================

function Invoke-RandomNameTool {
    param(
        [string]$sex,
        [string]$style
    )

    $maleModernNames   = @("Emmitt", "Ethan", "Noah", "Liam", "Mason", "Jacob", "Jared", "Joe", "Ryan", "Tyler", "Brandon", "Austin", "Dylan", "Logan", "Hunter", "Mr. Black", "Officer Miller", "Dr. Vance", "Coach Murphy", "The Professor", "Sgt. Hartman", "Victor 'The Snake' Rossi", "Julian Graves")
    $femaleModernNames = @("Olivia", "Emma", "Ava", "Sophia", "Isabella", "Mia", "Charlotte", "Amelia", "Harper", "Ella", "Chloe", "Lily", "Ms. Gable", "Detective Thorne", "Dr. Sarah Jenkins", "Auntie May", "The Widow Ross", "Sloane 'Ace' Cassidy", "Principal Skinner", "Elena the Architect")

    $maleSciFiNames    = @("Jax", "Kael", "Zane", "Rylo", "Corvus", "Oryn", "Drex", "Voss", "Talon", "Crix", "Nexus", "Arlo", "Unit 734", "Commander Vex", "Xylos of Sector 4", "Cypher-9", "Techno-Priest Malen", "The Exile", "Orbit-Zero", "Captain Star-Drifter", "Quasar-Jack")
    $femaleSciFiNames  = @("Luna", "Lyra", "Nova", "Astra", "Vega", "Seraphina", "Zara", "Nyx", "Cleo", "Ionic", "Phaedra", "Solara", "Rhea", "Pilot Juno", "Oracle Prime", "Echo-7", "The Galactic Matriarch", "Nebula the Rogue", "Zenith-Alpha", "Commander Iris", "Starlight-Sia")

    $maleFantasyNames  = @("Aric", "Torin", "Lysander", "Kieran", "Eamon", "Aldric", "Theron", "Caelan", "Dorian", "Faelen", "Gideon", "Hadrian", "Shegath the Wicked", "Bilfo of Cameronwood", "Grog the Stout", "Lord Valerius", "Thalric the Bold", "Brynjar of the Iron Hills", "The Shadow-Stalker", "Old Man Grom", "Sir Cedric the Brave", "Kaelen of the Silver Oath")
    $femaleFantasyNames= @("Ara", "Elara", "Seraphine", "Isolde", "Rowan", "Aeliana", "Sylara", "Brynn", "Calista", "Dawneth", "Fiora", "Gwendolyn", "Thessaly", "Morgana the Cursed", "Lady Whisper", "Elowen of the Glade", "The Witch of the Wilds", "Queen Valeriana", "Mira the Swift", "Lyanna the Rose", "Sariel of the Star-Fall")


    # Normalize inputs
    $sexNorm   = if ($sex) { $sex.Trim() } else { "Male" }
    $styleNorm = if ($style) { $style.Trim().ToLower() } else { "modern" }

    switch ($styleNorm) {
        "modern"  { $names = if ($sexNorm -eq "Female") { $femaleModernNames  } else { $maleModernNames  } }
        "sci-fi"  { $names = if ($sexNorm -eq "Female") { $femaleSciFiNames   } else { $maleSciFiNames   } }
        "fantasy" { $names = if ($sexNorm -eq "Female") { $femaleFantasyNames } else { $maleFantasyNames } }
        default   { return "ERROR: Invalid style '$style'. Choose from 'modern', 'sci-fi', or 'fantasy'." }
    }

    if ($names) {
        $randomName = Get-Random -InputObject $names
        $msg = "🎲 Random name generated: $randomName"
        $technical = "Random name generated: $randomName (Sex: $sexNorm, Style: $styleNorm)"
        return "CONSOLE::$msg::END_CONSOLE::$technical"
    } else {
        return "ERROR: Could not generate name."
    }
}

# ── Self-registration block ──────────────────────────────────────────────────

$ToolMeta = @{
    Name        = "randomname"
    RendersToConsole = $false
    Category    = @("Gaming/Entertainment")
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
