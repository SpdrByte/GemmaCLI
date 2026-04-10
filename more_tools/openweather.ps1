# ===============================================
# GemmaCLI Tool - openweather.ps1 v0.2.0
# Responsibility: Fetches real-time weather data via OpenWeatherMap API.
# ===============================================

function Invoke-OpenWeatherTool {
    param([string]$location)

    $apiKey = Get-StoredKey -keyName "openweather"
    if (-not $apiKey) {
        return "ERROR: OpenWeather API key not found. Please ensure it is configured in the CLI."
    }

    try {
        $encodedLocation = [uri]::EscapeDataString($location)
        # Using metric units by default; model can convert if user asks for Fahrenheit
        $uri = "https://api.openweathermap.org/data/2.5/weather?q=$encodedLocation&appid=$apiKey&units=metric"
        
        $response = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
        
        $city = $response.name
        $temp = $response.main.temp
        $desc = $response.weather[0].description
        $hum  = $response.main.humidity
        $wind = $response.wind.speed

        $deg = [char]0x00B0
        return "Current weather in ${city}: $temp$($deg)C, $desc. Humidity: $hum%, Wind Speed: $wind m/s."
    } catch {
        if ($_.Exception.Message -match "404") {
            return "ERROR: Location '$location' not found. Please provide a valid city name."
        }
        if ($_.Exception.Message -match "401") {
            return "ERROR: Invalid API key. Please reset the key using /resetkey (Note: this currently resets the main key, tool key management coming soon)."
        }
        return "ERROR: Failed to retrieve weather data. $($_.Exception.Message)"
    }
}

$ToolMeta = @{
    Name        = "openweather"
    Icon        = "🌤️"
    RendersToConsole = $false
    RequiresKey = $true
    KeyUrl      = "https://home.openweathermap.org/api_keys"
    Category    = @("Search and Discover")
    Behavior    = "Use this tool to provide current weather conditions for a specific city. If the user doesn't specify a location, ask for one."
    Description = "Fetches real-time weather information (temperature, conditions, wind) for any city."
    Parameters  = @{
        location = "string - the city and optional country code (e.g., 'London, UK' or 'Tokyo')"
    }
    Example     = "<tool_call>{ ""name"": ""openweather"", ""parameters"": { ""location"": ""New York"" } }</tool_call>"
    FormatLabel = { param($p) "$($p.location)" }
    Execute     = { param($params) Invoke-OpenWeatherTool @params }
    ToolUseGuidanceMajor = @"
        - When to use 'openweather': Use this tool whenever the user asks about current weather, temperature, or atmospheric conditions in a specific place.
        - Location context: If the user says 'the weather' or 'weather near me' without a city, you MUST ask them for their city name before calling this tool.
        - Units: The tool returns data in Metric (Celsius). You may convert to Fahrenheit if you detect the user is in the US (multiply by 9/5 and add 32).
"@
}
