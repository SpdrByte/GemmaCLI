# tests/brave_search.Tests.ps1

Describe "Brave Search Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../tools/brave_search.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../more_tools/brave_search.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should return an error if the API key is missing" {
        $oldKey = $env:BRAVE_API_KEY
        $env:BRAVE_API_KEY = $null
        $result = Invoke-BraveSearchTool -query "test"
        $result | Should Match "ERROR: Brave API key not found"
        $env:BRAVE_API_KEY = $oldKey
    }

    It "should return search results for a valid query" {
        $env:BRAVE_API_KEY = "dummy-key"
        Mock Invoke-RestMethod {
            return @{
                web = @{
                    results = @(
                        @{ title = "Test Title"; url = "https://example.com"; description = "Test Desc" }
                    )
                }
            }
        }
        $result = Invoke-BraveSearchTool -query "test"
        $result | Should Match "TITLE: Test Title"
        $result | Should Match "URL: https://example.com"
    }
}
