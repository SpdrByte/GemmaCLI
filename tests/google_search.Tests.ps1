# tests/google_search.Tests.ps1
$toolFile = "google_search.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Get-ChildItem -Path "$projectRoot/tools/$toolFile", "$projectRoot/more_tools/$toolFile" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

Describe "Google Search Tool" {
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
        $ToolMeta.Name | Should Be "google_search"
        $ToolMeta.Parameters.ContainsKey("query") | Should Be $true
    }

    It "should execute and return a search result" {
        # Note: This actually calls the API if keys are present, 
        # or we could mock Invoke-SingleTurnApi.
        # For a professional test, we mock the API dependency.
        
        Mock Invoke-SingleTurnApi { return "Paris is the capital of France." }
        
        $result = Invoke-GoogleSearchTool -query "What is the capital of France?"
        $result | Should Match "Paris"
    }
}
