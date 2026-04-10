# tests/ToolRelationships.Tests.ps1
# Responsibility: Verify that tools have the correct Relationship metadata defined.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir

function Get-ToolMeta {
    param([string]$toolName)
    $path = Get-ChildItem -Path "$projectRoot/tools/$toolName", "$projectRoot/more_tools/$toolName" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { return $null }
    $content = Get-Content -Path $path -Raw -Encoding UTF8
    $ToolMeta = $null
    Invoke-Expression $content
    return $ToolMeta
}

Describe "Tool Relationship Metadata" {
    
    Context "Arduino Boards Tool" {
        It "should have a relationship with ael_validate" {
            $meta = Get-ToolMeta "arduino_boards.ps1"
            $meta.Relationships | Should Not Be $null
            $meta.Relationships.ContainsKey("ael_validate") | Should Be $true
            $meta.Relationships["ael_validate"] | Should Match "synergy"
        }
    }

    Context "ESP Boards Tool" {
        It "should have a relationship with ael_validate" {
            $meta = Get-ToolMeta "esp_boards.ps1"
            $meta.Relationships | Should Not Be $null
            $meta.Relationships.ContainsKey("ael_validate") | Should Be $true
            $meta.Relationships["ael_validate"] | Should Match "synergy"
        }
    }

    Context "AEL Validation Tool" {
        It "should have relationships with arduino_boards and esp_boards" {
            $meta = Get-ToolMeta "ael_validate.ps1"
            $meta.Relationships | Should Not Be $null
            $meta.Relationships.ContainsKey("arduino_boards") | Should Be $true
            $meta.Relationships.ContainsKey("esp_boards") | Should Be $true
        }
    }

    Context "Adventure Tool" {
        It "should have a relationship with gemma_pixel_art" {
            $meta = Get-ToolMeta "adventure.ps1"
            $meta.Relationships | Should Not Be $null
            $meta.Relationships.ContainsKey("gemma_pixel_art") | Should Be $true
            $meta.Relationships["gemma_pixel_art"] | Should Match "visual scene descriptions"
        }
    }
}
