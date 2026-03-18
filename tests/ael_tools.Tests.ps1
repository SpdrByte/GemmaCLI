# tests/ael_tools.Tests.ps1
# Responsibility: Validate ESP board database and AEL circuit validation logic.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir

Describe "ESP Boards Tool" {
    BeforeAll {
        # Mocking Draw-Box to avoid UI output during tests
        function Draw-Box { param($Lines, $Title, $Color) }
        . (Join-Path $projectRoot "tools/esp_boards.ps1")
    }

    It "should list all supported boards" {
        $result = Invoke-ESPBoards -action "list_boards" -scriptDir $projectRoot
        $result | Should Match "Supported ESP32 boards"
        $result | Should Match "CONSOLE::"
        $result | Should Match "esp32c3_supermini"
    }

    It "should list pins for a specific board" {
        $result = Invoke-ESPBoards -action "list_pins" -board "esp32c3_supermini" -scriptDir $projectRoot
        $result | Should Match "ESP32-C3 SuperMini"
        $result | Should Match "GPIO8"
        $result | Should Match "3V3"
    }

    It "should filter pins by protocol (I2C)" {
        $result = Invoke-ESPBoards -action "filter_protocol" -board "esp32c3_supermini" -protocol "I2C" -scriptDir $projectRoot
        $result | Should Match "I2C_SDA"
        $result | Should Match "GPIO8"
    }

    It "should check if a pin exists" {
        $resultJson = (Invoke-ESPBoards -action "check_pin" -board "esp32c3_supermini" -pin "GPIO8" -scriptDir $projectRoot) -replace "(?s)^CONSOLE::.*::END_CONSOLE::", ""
        $result = $resultJson | ConvertFrom-Json
        $result.exists | Should Be $true
        $result.type | Should Be "IO"
    }

    It "should return an error for non-existent pins" {
        $resultJson = (Invoke-ESPBoards -action "check_pin" -board "esp32c3_supermini" -pin "GPIO99" -scriptDir $projectRoot) -replace "(?s)^CONSOLE::.*::END_CONSOLE::", ""
        $result = $resultJson | ConvertFrom-Json
        $result.exists | Should Be $false
    }
}

Describe "AEL Validation Tool" {
    BeforeAll {
        # Mocking Draw-Box and Render-ValidationResult to avoid UI output
        function Draw-Box { param($Lines, $Title, $Color) }
        function Render-ValidationResult { param($jsonResult) }
        . (Join-Path $projectRoot "tools/ael_validate.ps1")
    }

    It "should validate a correct AEL circuit" {
        $ael = @"
BOARD esp32c3_supermini AS esp
COMP led1 LED
COMP r1 RES value=220R
WIRE esp.GPIO2 -> led1.A
WIRE led1.C -> r1.A
WIRE r1.B -> esp.GND
"@
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.valid | Should Be $true
        $result.errors.Count | Should Be 0
    }

    It "should detect unknown component types" {
        $ael = "COMP x1 UNKNOWN_TYPE"
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.valid | Should Be $false
        $result.errors[0].code | Should Be "UNKNOWN_COMPONENT"
    }

    It "should detect unknown pin references" {
        $ael = @"
BOARD esp32c3_supermini AS esp
WIRE esp.GPIO_NONEXISTENT -> esp.GND
"@
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.valid | Should Be $false
        $result.errors[0].code | Should Be "UNKNOWN_PIN"
    }

    It "should detect invalid signal directions (WIRE from INPUT)" {
        $ael = @"
BOARD esp32c3_supermini AS esp
COMP btn BUTTON
WIRE btn.B -> esp.GPIO3
WIRE esp.GPIO3 -> esp.GND
"@
        # Note: GPIO3 is IO (ok), but let's test a real failure if we had an INPUT pin
        # ESP32-DevKit GPIO34 is INPUT only
        $ael = @"
BOARD esp32_devkit AS esp
WIRE esp.GPIO34 -> esp.GND
"@
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.valid | Should Be $false
        $result.errors[0].code | Should Be "INVALID_SIGNAL_DIRECTION"
    }

    It "should detect voltage mismatches" {
        $ael = @"
BOARD esp32c3_supermini AS esp
COMP display OLED_I2C
POWER esp.5V -> display.VCC
"@
        # OLED_I2C vcc_range is 3.0-3.6V. esp.5V is 5.0V.
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.valid | Should Be $false
        $result.errors[0].code | Should Be "VOLTAGE_MISMATCH"
    }

    It "should warn about multiple pins on the same board pin" {
        $ael = @"
BOARD esp32c3_supermini AS esp
COMP led1 LED
COMP led2 LED
WIRE esp.GPIO2 -> led1.A
WIRE esp.GPIO2 -> led2.A
"@
        $resultJson = (Invoke-AELValidate -aelText $ael -scriptDir $projectRoot)
        $result = $resultJson | ConvertFrom-Json
        $result.warnings[0].code | Should Be "PIN_ALREADY_ASSIGNED"
    }
}
