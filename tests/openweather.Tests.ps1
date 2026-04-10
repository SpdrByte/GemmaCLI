# tests/openweather.Tests.ps1
$toolFile = "openweather.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Get-ChildItem -Path "$projectRoot/tools/$toolFile", "$projectRoot/more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

Describe "OpenWeather Tool" {
    BeforeAll {
        if (-not $toolPath) { throw "Tool $toolFile not found" }
        # Mocking dependencies
        function Get-StoredKey { param($k) return "mock_key" }
        function Draw-Box { param($Lines, $Title, $Color) }
        
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should define the tool metadata" {
        $ToolMeta.Name | Should Be "openweather"
        $ToolMeta.RequiresKey | Should Be $true
        $ToolMeta.KeyUrl | Should Match "openweathermap.org"
    }

    It "should execute and return weather data" {
        $mockResponse = @{
            name = "London"
            main = @{ temp = 15; humidity = 80 }
            weather = @(@{ description = "cloudy" })
            wind = @{ speed = 5.5 }
        }
        
        Mock Invoke-RestMethod { return $mockResponse }
        
        $result = Invoke-OpenWeatherTool -location "London"
        $result | Should Match "London"
        $result | Should Match "15.C" # Using . to match any character instead of encoding-sensitive degree symbol
        $result | Should Match "cloudy"
    }

    It "should handle 404 errors for invalid locations" {
        Mock Invoke-RestMethod { throw "The remote server returned an error: (404) Not Found." }
        
        $result = Invoke-OpenWeatherTool -location "InvalidCityName"
        $result | Should Match "not found"
    }
}
