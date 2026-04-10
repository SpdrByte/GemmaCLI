# tests/coingecko.Tests.ps1

Describe "CoinGecko Tool" {
    BeforeAll {
        $toolPath = Join-Path $PSScriptRoot "../tools/coingecko.ps1"
        if (-not (Test-Path $toolPath)) {
            $toolPath = Join-Path $PSScriptRoot "../more_tools/coingecko.ps1"
        }
        $content = Get-Content -Path $toolPath -Raw -Encoding UTF8
        Invoke-Expression $content
    }

    It "should return a price for a valid cryptocurrency" {
        $result = Invoke-CoinGeckoTool -coin "bitcoin"
        $result | Should Match "bitcoin"
        $result | Should Match "usd"
    }

    It "should return an error for an invalid cryptocurrency" {
        $result = Invoke-CoinGeckoTool -coin "not-a-real-coin-xyz"
        $result | Should Match "ERROR"
    }
}
