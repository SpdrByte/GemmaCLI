# tests/google_maps.Tests.ps1
$toolFile = "google_maps.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Get-ChildItem -Path "$projectRoot/tools/$toolFile", "$projectRoot/more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

Describe "Google Maps Tool" {
    BeforeAll {
        if (-not $toolPath) { throw "Tool $toolFile not found" }
        # Mocking dependencies
        function Get-StoredKey { param($k) return "mock_key" }
        function Invoke-SingleTurnApi { }
        function Resolve-ModelId { param($h) return "gemini-3.1-flash-lite-preview" }
        function Draw-Box { param($Lines, $Title, $Color) }
        function Start-Spinner { param($Label) }
        function Stop-Spinner { }
        
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should define the tool metadata" {
        $ToolMeta.Name | Should Be "google_maps"
        $ToolMeta.Parameters.ContainsKey("query") | Should Be $true
    }

    It "should execute and return a grounded result" {
        Mock Invoke-SingleTurnApi { return "I found several Italian restaurants in Austin, including Vespaio and Juliet Italian Kitchen." }
        
        $result = Invoke-GoogleMapsTool -query "Italian restaurants" -location_context "Austin, TX"
        $result | Should Match "Italian restaurants"
        $result | Should Match "Austin"
    }
}
