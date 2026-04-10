# tests/adventure.Tests.ps1
$toolFile = "adventure.ps1"
$adventureToolPath = Get-ChildItem -Path "$PSScriptRoot/../tools/$toolFile", "$PSScriptRoot/../more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

Describe "Adventure Tool" {
    BeforeAll {
        if (-not $adventureToolPath) { throw "Tool $toolFile not found" }
        . $adventureToolPath
    }

    BeforeEach {
        Invoke-AdventureTool -action "reset" | Out-Null
    }

    It "should create a player with sex and description" {
        $result = Invoke-AdventureTool -action "add_character" -value "Kev|player|Male|A brave warrior"
        $result | Should Match "Kev"
        $result | Should Match "Male"
        $result | Should Match "A brave warrior"
    }

    It "should show sex and description in status" {
        Invoke-AdventureTool -action "add_character" -value "Kev|player|Male|A brave warrior" | Out-Null
        Invoke-AdventureTool -action "move" -value "Kev|The Tavern" | Out-Null
        
        $status = Invoke-AdventureTool -action "status"
        $status | Should Match "Kev"
        $status | Should Match "Male"
        $status | Should Match "Description: A brave warrior"
        $status | Should Match "The Tavern"
    }

    It "should show combat initiative order in status" {
        Invoke-AdventureTool -action "add_character" -value "Kev|player|Male|Warrior" | Out-Null
        Invoke-AdventureTool -action "add_character" -value "Goblin|npc|10|10|Club-d4" | Out-Null
        
        Invoke-AdventureTool -action "start_combat" -value "Kev,Goblin" | Out-Null
        
        $status = Invoke-AdventureTool -action "status"
        $status | Should Match "COMBAT ACTIVE"
        $status | Should Match "Initiative Order"
        $status | Should Match "Kev"
        $status | Should Match "Goblin"
    }
}
