# tests/ToolLoader.Tests.ps1
Describe "ToolLoader Module" {
    BeforeAll {
        $libPath = Join-Path $PSScriptRoot "../lib/ToolLoader.ps1"
        $content = Get-Content -Path $libPath -Raw -Encoding UTF8
        Invoke-Expression $content
        
        # Isolated tools directory for testing
        $script:testToolsDir = Join-Path $PSScriptRoot "test_tools"
        if (-not (Test-Path $script:testToolsDir)) { New-Item -ItemType Directory -Path $script:testToolsDir -Force }
        
        # Mock the tools and script variables
        $script:MODEL = "gemma-3-27b-it"
        $script:TOOL_LIMITS = @{ "gemma-3-27b-it" = 1; "gemma-3-4b-it" = 1 }
        
        # Mock a single tool in the test tools directory
        $mockToolContent = @'
$ToolMeta = @{
    Name = "mock_tool"
    Description = "Test Description"
    Parameters = @{ param1 = "string" }
    Example = "Test Example"
    FormatLabel = { "mock" }
    Execute = { "mock" }
    ToolUseGuidanceMajor = "Detailed Guidance"
    ToolUseGuidanceMinor = "Simplified Guidance"
}
'@
        $mockToolPath = Join-Path $script:testToolsDir "mock_tool.ps1"
        Set-Content -Path $mockToolPath -Value $mockToolContent
    }

    AfterAll {
        if (Test-Path $script:testToolsDir) { Remove-Item $script:testToolsDir -Recurse -Force }
    }

    It "should generate a detailed prompt with guidance for a major model (27b)" {
        $model = "gemma-3-27b-it"
        $limits = @{ "gemma-3-27b-it" = 1 }
        
        # We need to temporarily point the tool loader to our test tools directory
        # Since Get-ToolInstructions hardcodes the 'tools' subfolder relative to ScriptRoot,
        # we pass the parent of our testToolsDir.
        $testScriptRoot = Split-Path $script:testToolsDir -Parent
        # Wait, Get-ToolInstructions does: Join-Path $ScriptRoot "tools"
        # So we need a folder named 'tools' inside our testScriptRoot.
        
        $isolatedRoot = Join-Path $PSScriptRoot "isolated_test"
        $isolatedTools = Join-Path $isolatedRoot "tools"
        if (-not (Test-Path $isolatedTools)) { New-Item -ItemType Directory -Path $isolatedTools -Force }
        Move-Item -Path (Join-Path $script:testToolsDir "mock_tool.ps1") -Destination $isolatedTools -Force
        
        $prompt = Get-ToolInstructions -ScriptRoot $isolatedRoot -Model $model -ToolLimits $limits
        
        $prompt | Should Match "Description"
        $prompt | Should Match "Example"
        $prompt | Should Match "Usage Guidance \(Detailed\)"
        $prompt | Should Match "Detailed Guidance"
        
        Remove-Item $isolatedRoot -Recurse -Force
    }

    It "should generate a prompt with simplified guidance for a minor model (4b)" {
        $model = "gemma-3-4b-it"
        $limits = @{ "gemma-3-4b-it" = 1 }
        
        $isolatedRoot = Join-Path $PSScriptRoot "isolated_test_minor"
        $isolatedTools = Join-Path $isolatedRoot "tools"
        if (-not (Test-Path $isolatedTools)) { New-Item -ItemType Directory -Path $isolatedTools -Force }
        
        # Re-create mock tool in the new isolated path
        $mockToolContent = @'
$ToolMeta = @{
    Name = "mock_tool"
    Description = "Test Description"
    Parameters = @{ param1 = "string" }
    Example = "Test Example"
    FormatLabel = { "mock" }
    Execute = { "mock" }
    ToolUseGuidanceMajor = "Detailed Guidance"
    ToolUseGuidanceMinor = "Simplified Guidance"
}
'@
        Set-Content -Path (Join-Path $isolatedTools "mock_tool.ps1") -Value $mockToolContent

        $prompt = Get-ToolInstructions -ScriptRoot $isolatedRoot -Model $model -ToolLimits $limits
        
        $prompt | Should Match "Description"
        $prompt | Should Match "Example"
        $prompt | Should Match "Usage Guidance \(Simplified\)"
        $prompt | Should Match "Simplified Guidance"
        
        Remove-Item $isolatedRoot -Recurse -Force
    }
}
