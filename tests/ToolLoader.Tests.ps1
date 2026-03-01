# tests/ToolLoader.Tests.ps1
Describe "ToolLoader Module" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "../lib/ToolLoader.ps1")
        # Mock the tools and script variables
        $script:MODEL = "gemma-3-27b-it"
        $script:TOOL_LIMITS = @{ "gemma-3-27b-it" = 1; "gemma-3-12b-it" = 1 }
        
        # Mock a single tool in the tools directory for testing
        $mockToolContent = @'
$ToolMeta = @{
    Name = "mock_tool"
    Behavior = "Test Behavior"
    Description = "Test Description"
    Parameters = @{ param1 = "string" }
    Example = "Test Example"
    FormatLabel = { "mock" }
    Execute = { "mock" }
}
'@
        Set-Content -Path (Join-Path $PSScriptRoot "../tools/mock_tool.ps1") -Value $mockToolContent
        
        # Mock instructions.json
        $mockInstructions = @{ system_prompt = "%%AVAILABLE_TOOLS%%" } | ConvertTo-Json
        Set-Content -Path (Join-Path $PSScriptRoot "../instructions.json") -Value $mockInstructions
    }

    AfterAll {
        Remove-Item (Join-Path $PSScriptRoot "../tools/mock_tool.ps1") -Force
        Remove-Item (Join-Path $PSScriptRoot "../instructions.json") -Force
    }

    It "should generate a detailed prompt for a 27b model" {
        $script:MODEL = "gemma-3-27b-it"
        Initialize-Tools -ScriptRoot (Get-Location) -Model $script:MODEL -ToolLimits $script:TOOL_LIMITS
        $script:systemPrompt | Should Match "Behavior"
        $script:systemPrompt | Should Match "Example"
    }

    It "should generate a brief prompt for a 12b model" {
        $script:MODEL = "gemma-3-12b-it"
        Initialize-Tools -ScriptRoot (Get-Location) -Model $script:MODEL -ToolLimits $script:TOOL_LIMITS
        $script:systemPrompt | Should Not Match "Behavior"
        $script:systemPrompt | Should Not Match "Example"
    }
}
