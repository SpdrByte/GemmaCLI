# tests/http_get.Tests.ps1

Describe "HTTP Get Tool" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../more_tools/http_get.ps1")
    }

    It "should return content from a valid URL" {
        $result = Invoke-HttpGetTool -url "https://httpbin.org/get"
        $result | Should Not BeNullOrEmpty
    }

    It "should return an error for an invalid URL" {
        { Invoke-HttpGetTool -url "http://invalid-url-that-does-not-exist-abc.xyz" } | Should Throw
    }
}
