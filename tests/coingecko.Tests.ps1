# tests/coingecko.Tests.ps1

Describe "CoinGecko Tool" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../more_tools/coingecko.ps1")
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
