# tests/gemmagotchi.Tests.ps1
# Updated for v0.5.0 (5-tier hunger, sounds, midnight reset)

Describe "Gemmagotchi Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../tools/gemmagotchi.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../more_tools/gemmagotchi.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content

        # Setup temporary environment
        $script:tempDir = Join-Path $env:TEMP "gemmagotchi_test_$(Get-Random)"
        New-Item -Path $script:tempDir -ItemType Directory -Force | Out-Null
        $script:testDbDir = Join-Path $script:tempDir "database"
        New-Item -Path $script:testDbDir -ItemType Directory -Force | Out-Null
        
        $script:testDbPath = Join-Path $script:testDbDir "gemmagotchi.json"

        # Mock global variable from GemmaCLI.ps1
        $script:scriptDir = $script:tempDir
        
        # Initial database state (50.0 = HUNGRY)
        $initialState = @{
            hunger = 50.0
            state = "neutral"
            last_update = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            last_fed = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            debug = $false
        }
        $initialState | ConvertTo-Json | Set-Content $script:testDbPath -Encoding UTF8
    }

    AfterAll {
        if (Test-Path $script:tempDir) {
            Remove-Item $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Tool Logic and Database Actions" {
        Mock Write-Host { } # Prevent console spam during tests

        It "should return 'HUNGRY' status when hunger is 50" {
            $result = Invoke-GemmagotchiTool -action "status"
            $result | Should Match "HUNGRY"
            $result | Should Match "Hunger: 50%"
            # Should also include the sound instruction for hungry (chord)
            $result | Should Match "CONSOLE::PLAY_SOUND:chord::END_CONSOLE::"
        }

        It "should decrease hunger by 15% when action is 'feed'" {
            # Reset to 50
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.hunger = 50.0
            $state | ConvertTo-Json | Set-Content $script:testDbPath
            
            $result = Invoke-GemmagotchiTool -action "feed"
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.hunger | Should Be 35.0
            $result | Should Match "Fed!"
            $result | Should Match "PLAY_SOUND:notify"
        }

        It "should toggle debug mode when action is 'debug'" {
            Invoke-GemmagotchiTool -action "debug"
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.debug | Should Be $true
            
            Invoke-GemmagotchiTool -action "debug"
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.debug | Should Be $false
        }

        It "should reset hunger to 50.0 when action is 'reset'" {
            # First change hunger to something else
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.hunger = 10.0
            $state | ConvertTo-Json | Set-Content $script:testDbPath
            
            Invoke-GemmagotchiTool -action "reset"
            $state = Get-Content $script:testDbPath | ConvertFrom-Json
            $state.hunger | Should Be 50.0
        }
    }

    Context "Rendering" {
        It "should call Write-Host multiple times for rendering" {
            $script:writeHostCalls = 0
            Mock Write-Host { $script:writeHostCalls++ }
            
            Invoke-GemmagotchiTool -action "status" | Out-Null
            $script:writeHostCalls | Should BeGreaterThan 5
        }
    }
}
