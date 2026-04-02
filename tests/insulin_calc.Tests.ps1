# tests/insulin_calc.Tests.ps1

Describe "Insulin Calculator Tool" {
    BeforeAll {
        $toolFile = "insulin_calc.ps1"
        $toolPath = Get-ChildItem -Path "$PSScriptRoot/../tools/$toolFile", "$PSScriptRoot/../more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if (-not $toolPath) { throw "Tool $toolFile not found" }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
        
        # Provide UI functions
        . (Join-Path $PSScriptRoot "../lib/UI.ps1")
        
        # Ensure nutrition database is available for tests
        $script:scriptDir = Join-Path $PSScriptRoot ".."
    }

    Context "Safety Features" {
        Mock Draw-Box { }
        Mock Write-Host { }
        It "should abort if manual carb entries do not match" {
            $result = Invoke-InsulinCalcTool -carbs_manual_1 20 -carbs_manual_2 25 -icr 10
            $result | Should Match "ERROR: Carb count mismatch"
            $result | Should Match "PLAY_SOUND:Windows Critical Stop"
        }

        It "should trigger a high dose warning for doses >= 10 units" {
            # 100g carbs / 10 ICR = 10 units
            $result = Invoke-InsulinCalcTool -carbs_manual_1 100 -carbs_manual_2 100 -icr 10
            $result | Should Match "PLAY_SOUND:Windows Battery Critical"
            $result | Should Match "Calculated 10 units"
        }
    }

    Context "Database Lookup (Verified Source)" {
        It "should use database values when food_item is found (Apple 100g = 14g carbs)" {
            $result = Invoke-InsulinCalcTool -food_item "apple" -amount 100 -carbs_manual_1 50 -carbs_manual_2 50 -icr 10
            # Should ignore the manual 50g and use the database 14g
            $result | Should Match "14 grams of carbs"
            $result | Should Match "VERIFIED DATABASE"
        }

        It "should warn if food_item is not found in database" {
            $result = Invoke-InsulinCalcTool -food_item "unknown_food" -amount 100 -carbs_manual_1 20 -carbs_manual_2 20 -icr 10
            $result | Should Match "PLAY_SOUND:Windows Hardware Fail"
            $result | Should Match "UNVERIFIED"
        }
    }
}
