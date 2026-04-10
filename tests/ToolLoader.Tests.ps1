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

    It "should inject Tool Synergies when related tools are both active" {
        $model = "gemma-3-27b-it"
        $limits = @{ "gemma-3-27b-it" = 2 }
        
        $isolatedRoot = Join-Path $PSScriptRoot "isolated_test_synergy"
        $isolatedTools = Join-Path $isolatedRoot "tools"
        if (-not (Test-Path $isolatedTools)) { New-Item -ItemType Directory -Path $isolatedTools -Force }
        
        $toolA = @'
$ToolMeta = @{
    Name = "tool_a"
    Description = "Tool A Description"
    Relationships = @{ "tool_b" = "Synergy Description A+B" }
}
'@
        $toolB = @'
$ToolMeta = @{
    Name = "tool_b"
    Description = "Tool B Description"
}
'@
        Set-Content -Path (Join-Path $isolatedTools "tool_a.ps1") -Value $toolA
        Set-Content -Path (Join-Path $isolatedTools "tool_b.ps1") -Value $toolB

        $prompt = Get-ToolInstructions -ScriptRoot $isolatedRoot -Model $model -ToolLimits $limits
        
        $prompt | Should Match "## Tool Synergies"
        $prompt | Should Match "#### Synergy: tool_a\+tool_b"
        $prompt | Should Match "Synergy Description A\+B"
        
        Remove-Item $isolatedRoot -Recurse -Force
    }

    It "should NOT inject Tool Synergies when only one of the related tools is active" {
        $model = "gemma-3-27b-it"
        $limits = @{ "gemma-3-27b-it" = 1 } # Only load one tool
        
        $isolatedRoot = Join-Path $PSScriptRoot "isolated_test_no_synergy"
        $isolatedTools = Join-Path $isolatedRoot "tools"
        if (-not (Test-Path $isolatedTools)) { New-Item -ItemType Directory -Path $isolatedTools -Force }
        
        $toolA = @'
$ToolMeta = @{
    Name = "tool_a"
    Description = "Tool A Description"
    Relationships = @{ "tool_b" = "Synergy Description A+B" }
}
'@
        $toolB = @'
$ToolMeta = @{
    Name = "tool_b"
    Description = "Tool B Description"
}
'@
        Set-Content -Path (Join-Path $isolatedTools "tool_a.ps1") -Value $toolA
        Set-Content -Path (Join-Path $isolatedTools "tool_b.ps1") -Value $toolB

        # limits=1 means only tool_a will be loaded (sorted by name)
        $prompt = Get-ToolInstructions -ScriptRoot $isolatedRoot -Model $model -ToolLimits $limits
        
        $prompt | Should Not Match "## Tool Synergies"
        $prompt | Should Not Match "Synergy Description A\+B"
        
        Remove-Item $isolatedRoot -Recurse -Force
    }
}
