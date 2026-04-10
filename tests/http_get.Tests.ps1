# tests/http_get.Tests.ps1

Describe "HTTP Get Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../tools/http_get.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../more_tools/http_get.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should return content from a valid URL" {
        Mock Invoke-RestMethod { return "Mock Response" }
        $result = Invoke-HttpGetTool -url "http://example.com"
        $result | Should Be "Mock Response"
    }

    It "should return an error for an invalid URL" {
        Mock Invoke-RestMethod { throw "Invalid URL" }
        $result = Invoke-HttpGetTool -url "http://invalid-url"
        $result | Should Match "ERROR: Failed to get content from URL"
    }
}
